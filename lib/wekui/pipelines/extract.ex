defmodule Wekui.Pipelines.Extract do
  @moduledoc """
  The claim-extraction pipeline: a batch of accepted [[post]]s (a place × window) in,
  structured [[claim]]s out. It renders the extractor Actor(agent)'s pinned prompt for
  the batch, calls the inference `Wekui.Clients.Worker`, parses the claims JSON, and
  writes each claim with its evidence, the [[person]]s it names, and the gazetteer
  [[place]]s its `place_mention` resolves to (`Wekui.Narrative.PlaceResolver`) — the
  agent authors every claim, and the person red line gates every write.

  Posts are cited by their `x_id` (the id shown to the model); a claim that cites
  nothing in the batch, or whose subject slips a private name past the gate, is skipped
  and counted. Best-effort per claim — a first end-to-end wiring, not yet a Run receipt.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Narrative
  alias Wekui.Narrative.PlaceResolver
  alias Wekui.Narrative.ThemeResolver
  alias Wekui.Normalize
  alias Wekui.Taxonomy

  @doc """
  Extracts claims from `posts` (a batch of Posts) using `agent` (the extractor,
  whose `prompt` is the pinned template and whose `model` drives the worker), and
  writes them for `event`. `opts`: `:place_scope`, `:t_start`, `:t_end`, `:prior`.

  Returns `{:ok, %{claims:, drafted:, skipped:, skips:}}`, or `{:error, reason}` when
  the worker is unready, unreachable, or its output does not parse.
  """
  def run(event, agent, posts, opts \\ []) do
    if Worker.ready?() do
      with rendered <- render(event, agent, posts, opts),
           {:ok, %{content: content}} <- Worker.complete(rendered, model: agent.model),
           {:ok, claims, unfitted, topics} <- parse(content) do
        by_xid = Map.new(posts, &{to_string(&1.x_id), &1})
        written = Enum.map(claims, &write_claim(event, agent, &1, by_xid))
        {:ok, summarize(written, unfitted, topics, posts)}
      end
    else
      {:error, {:state_gate, :worker_not_ready}}
    end
  end

  defp render(event, agent, posts, opts) do
    material =
      Enum.map_join(posts, "\n", fn p ->
        "[id #{p.x_id}] #{DateTime.to_iso8601(p.posted_at)} — #{p.text}"
      end)

    agent.prompt
    |> String.replace("{{event_name}}", event.name)
    |> String.replace("{{t0}}", DateTime.to_iso8601(event.t0))
    |> String.replace("{{place_scope}}", Keyword.get(opts, :place_scope, "the event"))
    |> String.replace("{{t_start}}", iso(Keyword.get(opts, :t_start)))
    |> String.replace("{{t_end}}", iso(Keyword.get(opts, :t_end)))
    |> String.replace("{{prior}}", Keyword.get(opts, :prior, "(ninguno)"))
    |> String.replace("{{vocabulary}}", vocabulary(event))
    |> String.replace("{{material}}", material)
  end

  # The ratified vocabulary, rendered for the model: what it may say happened, and what
  # it may NOT turn into a claim. The rule matters more than the name — a name alone
  # does not stop a reader stretching it over evidence that does not bear it — so each
  # theme carries its `applies_when` verbatim.
  #
  # The TOPICS are here for the refusal they make possible — naming a plea AS a plea is
  # what stops the model reaching for the nearest happening. They are rendered as a
  # SEPARATE, explicitly unselectable list: v8 showed them in the same shape as the
  # happenings and the model duly filed ten claims under `Solicitud de información`,
  # which the write path then refused. An answer list must not contain answers that are
  # not allowed.
  defp vocabulary(event) do
    {happenings, topics} =
      event.id
      |> Taxonomy.list_active_themes!()
      |> Enum.split_with(&(&1.nature == :happening))

    """
    HAPPENINGS — the ONLY names that may appear in a claim's "theme":
    #{lines(happenings)}

    TOPICS — these are NOT claims and must never appear in "theme". A post that is only
    doing one of these belongs in "topics", where naming it is a complete answer:
    #{lines(topics)}
    """
  end

  defp lines(themes) do
    Enum.map_join(themes, "\n", fn theme ->
      "- «#{theme.name}» — applies when: #{theme.applies_when}"
    end)
  end

  defp iso(nil), do: ""
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"claims" => claims} = answer} when is_list(claims) ->
        {:ok, claims, List.wrap(answer["unfitted"]), List.wrap(answer["topics"])}

      {:ok, _no_claims_key} ->
        {:error, :no_claims}

      {:error, error} ->
        {:error, {:invalid_json, error}}
    end
  end

  # Models sometimes wrap the JSON in a ```json fence despite the instruction not to.
  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  defp write_claim(event, agent, claim, by_xid) do
    posts =
      (claim["citations"] || [])
      |> Enum.map(&Map.get(by_xid, to_string(&1)))
      |> Enum.reject(&is_nil/1)

    case posts do
      [] ->
        {:skip, :no_valid_citations}

      [first | _rest] ->
        write_filed(event, agent, claim, posts, first)
    end
  end

  # NO THEME, NO CLAIM. A happening the vocabulary cannot name does not become a claim
  # that says nothing and reaches nobody — it belongs in `unfitted`, where a person
  # decides whether the vocabulary should grow.
  #
  # This also closes a leak by construction: an unfiled claim was still storing the
  # model's free prose, and free prose about this corpus contains private names.
  defp write_filed(event, agent, claim, posts, first) do
    case theme_id(event, claim) do
      nil ->
        {:skip, {:no_theme, to_string(claim["theme"] || "")}}

      theme_id ->
        attrs = %{
          event_id: event.id,
          theme_id: theme_id,
          kind: to_string(claim["kind"] || "otro"),
          subject: claim["subject_role"],
          magnitude: claim["magnitude"],
          place_mention: claim["place_mention"],
          status: claim["status"],
          first_seen_at: first.posted_at,
          actor_id: agent.id,
          confidence: confidence(claim["confidence"])
        }

        case Narrative.draft_claim(attrs) do
          {:ok, drafted} ->
            Enum.each(posts, &Narrative.cite_post!(%{claim_id: drafted.id, post_id: &1.id}))
            link_persons(event, drafted, claim["names"] || [])
            PlaceResolver.resolve(drafted, actor_id: agent.id, post_id: first.id)
            {:ok, drafted}

          {:error, error} ->
            {:skip, {:rejected, error}}
        end
    end
  end

  # The model chose from a CLOSED list, so the name is matched exactly (folded). The
  # fuzzy resolver is the fallback for a model that answered off-list or for a legacy
  # claim, and it refuses far more than it accepts — by design
  # (`Wekui.Narrative.ThemeResolver`).
  defp theme_id(event, claim) do
    named = Normalize.fold(to_string(claim["theme"] || ""))

    chosen =
      event.id
      |> Taxonomy.list_active_themes!()
      |> Enum.filter(&(&1.nature == :happening))
      |> Enum.find(&(Normalize.fold(&1.name) == named))

    cond do
      chosen -> chosen.id
      true -> fallback(event, claim["kind"])
    end
  end

  defp fallback(event, kind) do
    case ThemeResolver.resolve(event.id, to_string(kind || "")) do
      {:ok, theme} -> theme.id
      :no_theme -> nil
    end
  end

  defp link_persons(event, claim, names) do
    for name <- names, is_binary(name) and String.trim(name) != "" do
      person = Narrative.identify_person!(%{event_id: event.id, full_name: name})
      Narrative.link_person!(%{claim_id: claim.id, person_id: person.id})
    end
  end

  defp confidence(n) when is_number(n), do: n * 1.0

  defp confidence(s) when is_binary(s) do
    case Float.parse(s) do
      {float, _rest} -> float
      :error -> nil
    end
  end

  defp confidence(_absent), do: nil

  # EVERY POST IS ACCOUNTED FOR. A batch splits into the posts a claim cites, the
  # posts the model reported as evidencing something the vocabulary has no word for,
  # and the rest — which evidenced nothing. Before this, a post that fit nothing simply
  # vanished, and a silence is not auditable (`docs/mechanisms.md`).
  defp summarize(results, unfitted, topics, posts) do
    cited =
      for({:ok, claim} <- results, do: claim.id)
      |> Enum.flat_map(&Narrative.list_claim_citations!/1)
      |> MapSet.new(& &1.post_id)

    %{
      claims: length(results),
      drafted: Enum.count(results, &match?({:ok, _}, &1)),
      skipped: Enum.count(results, &match?({:skip, _}, &1)),
      skips: for({:skip, reason} <- results, do: reason),
      posts: length(posts),
      cited: MapSet.size(cited),
      unfitted: Enum.map(unfitted, &to_string(&1["what_happened"] || "")),
      topics: Enum.frequencies(Enum.map(topics, &to_string(&1["topic"] || ""))),
      unread: length(posts) - MapSet.size(cited)
    }
  end
end
