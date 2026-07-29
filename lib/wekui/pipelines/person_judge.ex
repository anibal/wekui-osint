defmodule Wekui.Pipelines.PersonJudge do
  @moduledoc """
  Decides which [[person]] rows are one human being written more than once, and folds
  them — the mechanism behind [[open-persons-are-not-deduplicated]].

  `Wekui.Narrative.PersonDuplicates` narrows the roster into small blocks. This partitions
  each block and performs the merges, receipted in a `:person_judge`
  `Wekui.Pipelines.Run`.

  ## Why a machine may merge here, when it may never merge a claim

  A merge is a **deprecation, never a rewrite**: the folded row keeps its name, carries
  `merged_into_id` and the reason, and its claims are carried onto the survivor. Nothing
  is deleted, so a wrong answer is legible and reversible afterwards. That is what makes
  delegating it safe without a person's signature in front of it. It is still a machine's
  act, so it is a Run and never a `Wekui.Curation.Act` — `Wekui.Curation` refuses an agent
  as curator outright.

  ## Two stages, and the split between them was measured

  **Rung 1 — position.** `same_by_position?/2` answers when the first name agrees and the
  shorter name says nothing the longer one does not. Those pairs merge without asking
  anything and never reach the judge. In code because as prose it did not hold: told in
  its own text that *"Belkis and Belkys are one name"*, the model split them in every run,
  because the family rule beside it outranked the spelling rule.

  **Rung 5 — the residue.** What position cannot settle — a nickname, a one-word name, a
  reordered married name — goes to the model with the block's names, who each was named
  BESIDE, and the instruction to read that the right way round.

  ## The signal that had to be inverted

  Blocking selects rows sharing a place and a day, so inside a block that context is
  near-constant and discriminates nothing. Worse, in a disaster corpus *same building,
  same day* means **family** — households are buried together and asked after in one post.
  Offered as evidence of sameness it merged whole families; inverted — *being named
  together is evidence they are DIFFERENT* — it scored **20 of 22 known pairs on both
  runs**, cut over-merging by a quarter, and was the only prompt tried that gave the same
  answer twice.

  Both remaining errors were SPLITS, which is the direction to fail in: a person wrongly
  left apart is a redundancy a reader sees through, and two people wrongly merged is one
  family's relative erased into another's.
  """

  alias Wekui.Clients.Worker
  alias Wekui.Narrative
  alias Wekui.Narrative.PersonDuplicates
  alias Wekui.Narrative.PersonMerge
  alias Wekui.Pipelines

  @prompt "prompts/person_judge.v1.txt"

  @doc """
  Judges `blocks` from `PersonDuplicates.find/1` and returns
  `{:ok, %{position:, judged:, refused:}}` — the pairs settled by position, the pairs the
  model called one person, and the blocks it could not answer.

  Nothing is merged here; `sweep/3` performs the folds.
  """
  def run(event, blocks, opts \\ [])

  def run(_event, [], _opts), do: {:ok, empty()}

  def run(event, blocks, opts) do
    if Worker.ready?() do
      model = Keyword.get(opts, :model, "deepseek-ai/DeepSeek-V4-Flash")
      prompt = opts[:prompt] || File.read!(@prompt)
      beside = PersonDuplicates.beside(event.id)

      {:ok, Enum.reduce(blocks, empty(), &judge_block(&1, beside, prompt, model, &2))}
    else
      {:error, {:state_gate, :worker_not_ready}}
    end
  end

  @doc """
  Finds, judges and folds duplicate Persons on `event`, leaving a `:person_judge` Run
  performed by `actor`. `opts[:limit]` bounds how many blocks are judged — measure before
  extending — and `opts[:dry]` judges without folding anything.
  """
  def sweep(event, actor, opts \\ []) do
    blocks = event.id |> PersonDuplicates.find() |> take(opts[:limit])

    run =
      Pipelines.start_run!(%{
        event_id: event.id,
        actor_id: actor.id,
        kind: :person_judge,
        options: %{"blocks" => length(blocks), "dry" => !!opts[:dry]}
      })

    case run(event, blocks, opts) do
      {:ok, found} ->
        merged = if opts[:dry], do: [], else: fold_all(found)

        {:ok,
         Pipelines.finalize_run!(run, %{
           summary: %{
             "position" => length(found.position),
             "judged" => length(found.judged),
             "refused" => length(found.refused),
             "merged" => length(merged),
             "folds" => Enum.map(merged, fn {kept, gone, why} -> [kept, gone, why] end)
           }
         })}

      {:error, error} ->
        {:error, error, run}
    end
  end

  defp take(blocks, nil), do: blocks
  defp take(blocks, limit), do: Enum.take(blocks, limit)

  ## ─────────────────────────── judging ───────────────────────────

  defp judge_block(block, beside, prompt, model, acc) do
    {settled, residue} = by_position(block.persons)

    if length(residue) < 2 do
      # Position answered everything in this block. Nothing to pay for.
      %{acc | position: acc.position ++ settled}
    else
      case ask(residue, beside, prompt, model) do
        {:ok, pairs} ->
          %{acc | position: acc.position ++ settled, judged: acc.judged ++ pairs}

        {:error, why} ->
          %{acc | position: acc.position ++ settled, refused: acc.refused ++ [{block, why}]}
      end
    end
  end

  # Every pair the names already settle, and whoever is left over.
  defp by_position(persons) do
    settled =
      for {a, i} <- Enum.with_index(persons),
          b <- Enum.drop(persons, i + 1),
          PersonDuplicates.same_by_position?(a.full_name, b.full_name),
          do: {a, b, "the first name and the surnames are the same"}

    named = settled |> Enum.flat_map(fn {a, b, _why} -> [a.id, b.id] end) |> MapSet.new()

    {settled, Enum.reject(persons, &MapSet.member?(named, &1.id))}
  end

  defp ask(persons, beside, prompt, model) do
    with {:ok, %{content: content}} <-
           Worker.complete(render(persons, beside, prompt), model: model),
         {:ok, groups} <- parse(content) do
      {:ok, pairs(groups, persons)}
    else
      {:error, why} -> {:error, why}
      _unreadable -> {:error, :unreadable}
    end
  end

  defp render(persons, beside, prompt) do
    position = persons |> Enum.with_index(1) |> Map.new(fn {person, n} -> {person.id, n} end)

    listed =
      persons
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {person, n} ->
        others =
          beside
          |> Map.get(person.id, MapSet.new())
          |> Enum.map(&position[&1])
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        note =
          if others == [],
            do: "",
            else: "   (named in the same report as #{Enum.map_join(others, ", ", &"##{&1}")})"

        "#{n}. #{person.full_name}#{note}"
      end)

    String.replace(prompt, "{{entries}}", listed)
  end

  # A group of N is N-1 folds; the fold itself decides which row survives.
  defp pairs(groups, persons) do
    Enum.flat_map(groups, fn group ->
      members =
        group
        |> Map.get("same", [])
        |> Enum.map(&Enum.at(persons, number(&1) - 1))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)

      why = Map.get(group, "why") || "judged one person"

      case members do
        [head | rest] when rest != [] -> Enum.map(rest, &{head, &1, why})
        _alone_or_empty -> []
      end
    end)
  end

  # The model is told to number its groups and sometimes stringifies the number — the
  # same leniency every parser here has needed.
  defp number(n) when is_integer(n), do: n

  defp number(n) when is_binary(n) do
    case Integer.parse(n) do
      {parsed, _rest} -> parsed
      :error -> 0
    end
  end

  defp number(_other), do: 0

  ## ─────────────────────────── folding ───────────────────────────

  # Blocks overlap on purpose, so a block may name a row an earlier fold already closed.
  # `PersonMerge` refuses an already-merged row, so a fold that no longer applies is
  # skipped rather than forced.
  defp fold_all(found) do
    Enum.reduce(found.position ++ found.judged, [], fn {a, b, why}, done ->
      case PersonMerge.merge(reload(a), reload(b), why) do
        {:ok, survivor} -> done ++ [{survivor.full_name, folded_name(a, b, survivor), why}]
        {:error, _not_applicable} -> done
      end
    end)
  end

  defp reload(person), do: Narrative.get_person!(person.id)

  defp folded_name(a, b, survivor),
    do: if(a.id == survivor.id, do: b.full_name, else: a.full_name)

  defp parse(content) do
    case content |> strip_fence() |> Jason.decode() do
      {:ok, %{"groups" => groups}} when is_list(groups) -> {:ok, groups}
      {:ok, _no_groups} -> {:error, :no_groups}
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  defp strip_fence(content) do
    content
    |> String.trim()
    |> String.replace(~r/\A```(?:json)?\s*/, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
  end

  defp empty, do: %{position: [], judged: [], refused: []}
end
