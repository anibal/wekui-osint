defmodule Wekui.Pipelines.PairJudge do
  @moduledoc """
  Decides whether two [[claim]]s are one happening told twice — rung five of
  `docs/mechanisms.md`, the **adversarial prompt**: two independent readings, each told
  to REFUTE, and only agreement resolves.

  `Wekui.Narrative.Duplicates` finds candidates by comparing words. Words are exactly
  what deceives in this corpus: `research-2026-07-23-clustering-spike` measured **981
  posts, 7.4%, sharing one missing-person template and differing only in the name of
  the person who is missing**. They read as near-identical and they mean opposite
  things. So the finder is deliberately generous, and something has to be sceptical
  after it — 3,213 pairs is not a review, it is a second job.

  **Both readings are told to argue DIFFERENT**, and told to answer DIFFERENT when they
  cannot tell. The asymmetry is not about accuracy:

    * two accounts of one happening left apart is a redundancy a reader can see through;
    * two happenings merged is **a person erased from the record** — one family's
      missing relative folded into another's, with nothing to announce the loss.

  ## The two readings are not one reading twice

  The second pass **swaps A and B**. Pairwise judging carries a positional bias that a
  bare re-roll does not disturb; swapping the order does. Two passes that agree across
  a swap have agreed about the pair, not about the layout.

  ## Where it stops, and what it may move

  It never merges. A merge is a [[curation]] act and stays a person's
  ([[decision-2026-07-27-curation-is-a-record]]) — and `Wekui.Curation` refuses an agent
  as curator outright. What this may do is **withdraw a machine's proposal**: a pair the
  finder offered and the judges refused leaves the queue, receipted in a
  `Wekui.Pipelines.Run` of kind `:pair_judge`, which is where the machine's acts belong.

  So each pair lands in one of three places:

    * `same` — both readings, across the swap, said one happening. Asked first.
    * `split` — the readings disagreed. Still asked, and marked, because a disagreement
      between two sceptics is precisely what a person should look at.
    * `different` — at least one reading refused, or neither ruled. Withdrawn.

  A pair no reading ruled on is `different`, because silence must never merge two
  happenings: design against the failure that cannot be seen after it happens.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Core
  alias Wekui.Narrative
  alias Wekui.Narrative.Duplicates
  alias Wekui.Pipelines

  @prompt "prompts/pair_judge.v1.txt"

  # How many pairs one reading sees. Small enough that the rules at the top of the
  # prompt stay near the pairs they govern — a rule stated once, far from the thing it
  # governs, is dropped by a small model.
  @batch 25

  @doc """
  Judges `pairs` — `[%{claim:, other:, score:}]` from `Wekui.Narrative.Duplicates` —
  and returns `{:ok, %{same:, different:, split:}}`.

  Each entry is `%{pair:, verdicts:, why:}`. Batches of #{@batch}, two readings each,
  the second with A and B swapped. A batch whose model call fails is not an error: its
  pairs land in `different` unruled, since a pair nobody read is a pair nobody may
  merge.
  """
  def run(pairs, opts \\ [])

  def run([], _opts), do: {:ok, empty()}

  def run(pairs, opts) do
    if Worker.ready?() do
      model = Keyword.get(opts, :model, "deepseek-ai/DeepSeek-V4-Flash")
      prompt = opts[:prompt] || File.read!(@prompt)
      said = describe_all(pairs)

      judged =
        pairs
        |> Enum.chunk_every(Keyword.get(opts, :batch, @batch))
        |> Enum.reduce(empty(), fn batch, acc ->
          merge(acc, judge_batch(batch, said, prompt, model))
        end)

      {:ok, judged}
    else
      {:error, {:state_gate, :worker_not_ready}}
    end
  end

  @doc """
  Finds every candidate pair on `event`, judges it, and writes the verdicts into a
  `:pair_judge` `Wekui.Pipelines.Run` performed by `actor`.

  The receipt is what the report reads: a pair the judges refused never reaches a
  person again, and the reason it did not is on the record.
  """
  def sweep(event, actor, opts \\ []) do
    pairs = Duplicates.find(event.id)

    run =
      Pipelines.start_run!(%{
        event_id: event.id,
        actor_id: actor.id,
        kind: :pair_judge,
        options: %{"pairs" => length(pairs), "batch" => Keyword.get(opts, :batch, @batch)}
      })

    case run(pairs, opts) do
      {:ok, judged} ->
        {:ok, Pipelines.finalize_run!(run, %{summary: summarize(judged)})}

      {:error, error} ->
        {:error, error, run}
    end
  end

  @doc """
  The pairs a `:pair_judge` run withdrew, as `MapSet` of the two claim ids — what the
  report subtracts so a refused pair is never asked again.
  """
  def withdrawn(event_id) do
    ruled(event_id, "different")
  end

  @doc "The pairs a `:pair_judge` run called one happening — asked first."
  def upheld(event_id) do
    ruled(event_id, "same")
  end

  @doc """
  Every pair a `:pair_judge` run has ruled on at all — upheld, withdrawn, **or split**.

  A split is included on purpose. Two sceptics disagreed, and rolling a third reading
  until they agree is picking the run that reads cleanest, which `prompt-craft` names as
  the way to fool yourself about a non-deterministic model. A disagreement is a finding,
  not a retry.
  """
  def ruled_on(event_id) do
    ~w(same different split)
    |> Enum.map(&ruled(event_id, &1))
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp ruled(event_id, key) do
    for run <- Pipelines.list_runs!(event_id),
        run.kind == :pair_judge,
        run.status == :completed,
        [a, b] <- Map.get(run.summary || %{}, key, []),
        into: MapSet.new(),
        do: MapSet.new([a, b])
  end

  ## ─────────────────────────── judging ───────────────────────────

  defp judge_batch(batch, said, prompt, model) do
    straight = read(batch, said, prompt, model, :straight)
    swapped = read(batch, said, prompt, model, :swapped)

    batch
    |> Enum.with_index(1)
    |> Enum.reduce(empty(), fn {pair, n}, acc ->
      verdicts = [verdict(straight, n), verdict(swapped, n)]
      entry = %{pair: pair, verdicts: verdicts, why: [why(straight, n), why(swapped, n)]}

      cond do
        Enum.all?(verdicts, &(&1 == "SAME")) -> %{acc | same: acc.same ++ [entry]}
        Enum.any?(verdicts, &(&1 == "SAME")) -> %{acc | split: acc.split ++ [entry]}
        true -> %{acc | different: acc.different ++ [entry]}
      end
    end)
  end

  # One reading. A failure returns no verdicts at all, which reads downstream as
  # DIFFERENT — the safe direction.
  defp read(batch, said, prompt, model, order) do
    rendered = String.replace(prompt, "{{pairs}}", render(batch, said, order))

    with {:ok, %{content: content}} <- Worker.complete(rendered, model: model),
         {:ok, verdicts} <- parse(content) do
      Map.new(verdicts, fn v -> {number(v["n"]), v} end)
    else
      _unread -> %{}
    end
  end

  defp render(batch, said, order) do
    batch
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {pair, n} ->
      {a, b} =
        case order do
          :straight -> {pair.other, pair.claim}
          :swapped -> {pair.claim, pair.other}
        end

      "#{n}.\n   A: #{said[a.id]}\n   B: #{said[b.id]}"
    end)
  end

  defp verdict(read, n), do: read |> Map.get(n, %{}) |> Map.get("verdict")
  defp why(read, n), do: read |> Map.get(n, %{}) |> Map.get("why")

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"verdicts" => verdicts}} when is_list(verdicts) -> {:ok, verdicts}
      {:ok, _no_verdicts} -> {:error, :no_verdicts}
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  # The prompt says no fence and the model fences anyway, sometimes. Output hygiene is
  # asked for and never trusted.
  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  # The model is told to number its verdicts and sometimes stringifies the number, the
  # same leniency the citation parser needed.
  defp number(n) when is_integer(n), do: n

  defp number(n) when is_binary(n) do
    case Integer.parse(n) do
      {parsed, _rest} -> parsed
      :error -> nil
    end
  end

  defp number(_other), do: nil

  ## ─────────────────────────── describing ───────────────────────────

  # Every claim in every pair, described once. Pairs share claims heavily — the finder
  # offers one claim against several others — so describing per pair would read the
  # same rows many times over.
  defp describe_all(pairs) do
    claims =
      pairs
      |> Enum.flat_map(&[&1.claim, &1.other])
      |> Map.new(&{&1.id, &1})

    places = place_names(claims)

    Map.new(claims, fn {id, claim} -> {id, describe(claim, places)} end)
  end

  # What a judge needs and nothing more: the change, whom it is about, how it stands,
  # where and when. Full names never appear — they live on the [[person]] behind the
  # handle gate, and a judge does not need them to tell two happenings apart.
  defp describe(claim, places) do
    [
      claim.kind,
      claim.subject,
      claim.status,
      Map.get(places, claim.id),
      claim.first_seen_at && DateTime.to_iso8601(claim.first_seen_at)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp place_names(claims) do
    gazetteer =
      claims
      |> Enum.map(fn {_id, claim} -> claim.event_id end)
      |> Enum.uniq()
      |> Enum.flat_map(&Core.list_places!/1)
      |> Map.new(&{&1.id, "#{&1.canonical_name} (#{&1.type})"})

    Map.new(claims, fn {id, _claim} ->
      names =
        id
        |> Narrative.list_claim_places!()
        |> Enum.map(&Map.get(gazetteer, &1.place_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")

      {id, if(names == "", do: nil, else: names)}
    end)
  end

  ## ─────────────────────────── plumbing ───────────────────────────

  defp empty, do: %{same: [], different: [], split: []}

  defp merge(acc, batch) do
    %{
      same: acc.same ++ batch.same,
      different: acc.different ++ batch.different,
      split: acc.split ++ batch.split
    }
  end

  # The receipt carries the pairs by id, plus one reason per withheld pair so a later
  # reader can see WHY the queue is shorter than the finder made it.
  defp summarize(judged) do
    %{
      "same" => ids(judged.same),
      "different" => ids(judged.different),
      "split" => ids(judged.split),
      "counts" => %{
        "same" => length(judged.same),
        "different" => length(judged.different),
        "split" => length(judged.split)
      },
      "why" =>
        Map.new(judged.different ++ judged.split, fn entry ->
          {"#{entry.pair.other.id}:#{entry.pair.claim.id}",
           entry.why |> Enum.reject(&is_nil/1) |> Enum.join(" / ")}
        end)
    }
  end

  defp ids(entries), do: Enum.map(entries, &[&1.pair.other.id, &1.pair.claim.id])
end
