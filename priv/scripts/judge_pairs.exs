# Puts two adversarial readings over the duplicate finder's proposals, so a person is
# handed pairs worth a minute instead of thousands of rows (LIVE: needs a key, costs
# money).
#
#     DRY=1 mix run priv/scripts/judge_pairs.exs        # how many pairs, and a sample
#     DEEPINFRA_API_KEY=… LIMIT=100 mix run priv/scripts/judge_pairs.exs
#
# WHY IT EXISTS. `Wekui.Narrative.Duplicates` is deliberately generous: it compares
# words, and words are what deceive here — 981 posts share one missing-person template
# and differ only in the name of the person who is missing. Generosity is right for the
# finder and unusable for a reader, and 3,213 pairs is not a review, it is a second job.
#
# WHAT IT MAY DO. Withdraw a machine's proposal, and nothing else. A merge is a
# curation act and stays a person's — `Wekui.Curation` refuses an agent as curator
# outright — so this writes no claim, only a `:pair_judge` run receipt the report reads.
#
# WHAT IT JUDGES, AND WHAT IT REFUSES TO. Only pairs that stand ALONE — the two claims
# join each other and nothing else. Inside a dense group, pairwise judging is the wrong
# instrument and no amount of spend fixes it: refute the edge between "equipo USAR El
# Salvador" and "equipo USAR de Perú" and the two are still in one group through the
# generic "equipo extranjero" that joins them both. Measured on the corpus, twelve
# groups held 77% of all 3,213 pairs and one clique of 61 claims held 1,516 of them, so
# judging every pair would have spent nearly half the money on the one shape where the
# answer cannot mean anything. A dense group needs a PARTITION, and a partition is a
# person's.
#
# WHY A LIMIT. Measure first, then extend: run a bounded sample, read what the readings
# disagreed about, and only then spend on the rest.
#
# Overridable: EVENT, LIMIT (pairs to judge, 0 for all), BATCH (pairs per call),
# ALL=1 (judge pairs inside dense groups too — see above before you do), EVENT,
# PAIR_JUDGE_PROMPT, PAIR_JUDGE_MODEL, DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Core
alias Wekui.Narrative.Duplicates
alias Wekui.Pipelines
alias Wekui.Pipelines.PairJudge

event_name = System.get_env("EVENT", "litoral-central-2026")
limit = System.get_env("LIMIT", "0") |> String.to_integer()
batch_size = System.get_env("BATCH", "25") |> String.to_integer()
all? = System.get_env("ALL") == "1"
prompt_file = System.get_env("PAIR_JUDGE_PROMPT", "prompts/pair_judge.v1.txt")
model = System.get_env("PAIR_JUDGE_MODEL", "deepseek-ai/DeepSeek-V4-Flash")
dry? = System.get_env("DRY") == "1"

say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

IO.puts("\nJudging duplicate proposals on #{event.name}\n")

# Pairs already ruled on are not asked again — upheld, withdrawn, or SPLIT. A split
# stays a split: rolling a third reading until two agree is picking the run that reads
# cleanest, which is how you fool yourself about a non-deterministic model.
settled = PairJudge.ruled_on(event.id)

pairs =
  event.id
  |> Duplicates.find()
  |> Enum.reject(&MapSet.member?(settled, MapSet.new([&1.claim.id, &1.other.id])))

say.("#{length(pairs)} unjudged pair(s); #{MapSet.size(settled)} already ruled on")

groups = Duplicates.cluster(pairs)
{alone, dense} = Enum.split_with(groups, &(&1.size == 2))
dense_pairs = dense |> Enum.map(&length(&1.pairs)) |> Enum.sum()

say.("#{length(groups)} group(s): #{length(alone)} standing alone, #{length(dense)} dense")

say.(
  "pairwise judging is valid on the #{length(alone)} that stand alone; the dense ones " <>
    "hold #{dense_pairs} pair(s) and need a partition, not a verdict per edge"
)

judgeable = if all?, do: pairs, else: Enum.flat_map(alone, & &1.pairs)
if all?, do: say.("ALL=1 — judging inside dense groups too; read the header first")

chosen = if limit > 0, do: Enum.take(judgeable, limit), else: judgeable

if chosen == [] do
  say.("nothing to judge.")
else
  say.("judging #{length(chosen)} in batches of #{batch_size}, two readings each")

  if dry? do
    IO.puts("\n  DRY — the first three, as a reading would see them:\n")

    for pair <- Enum.take(chosen, 3) do
      say.("• #{pair.other.kind} — #{pair.other.subject}")
      say.("  vs #{pair.claim.kind} — #{pair.claim.subject}  (#{Float.round(pair.score, 2)})")
    end
  else
    agent =
      Core.register_agent!(%{
        event_id: event.id,
        model: model,
        prompt: File.read!(prompt_file)
      })

    started = System.monotonic_time(:second)

    case PairJudge.run(chosen, model: model, batch: batch_size, prompt: File.read!(prompt_file)) do
      {:ok, judged} ->
        elapsed = System.monotonic_time(:second) - started

        run =
          Pipelines.start_run!(%{
            event_id: event.id,
            actor_id: agent.id,
            kind: :pair_judge,
            options: %{"pairs" => length(chosen), "batch" => batch_size, "limit" => limit}
          })

        summary = %{
          "same" => Enum.map(judged.same, &[&1.pair.other.id, &1.pair.claim.id]),
          "different" => Enum.map(judged.different, &[&1.pair.other.id, &1.pair.claim.id]),
          "split" => Enum.map(judged.split, &[&1.pair.other.id, &1.pair.claim.id]),
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

        Pipelines.finalize_run!(run, %{summary: summary})

        total = length(chosen)
        pct = fn n -> Float.round(n * 100 / total, 1) end

        IO.puts("")

        say.(
          "upheld   #{length(judged.same)} (#{pct.(length(judged.same))}%) — both said one happening"
        )

        say.(
          "split    #{length(judged.split)} (#{pct.(length(judged.split))}%) — the readings disagreed"
        )

        say.("withdrawn #{length(judged.different)} (#{pct.(length(judged.different))}%)")
        say.("in #{elapsed}s. Receipt #{run.id}.")

        # What a reading DISAGREED about is the only cheap teacher here: the finder's
        # defect shows in the split, not in the agreement.
        if judged.split != [] do
          IO.puts("\n  Where the two readings disagreed:\n")

          for entry <- Enum.take(judged.split, 5) do
            say.("• #{entry.pair.other.kind} — #{entry.pair.other.subject}")
            say.("  vs #{entry.pair.claim.kind} — #{entry.pair.claim.subject}")
            say.("  #{entry.why |> Enum.reject(&is_nil/1) |> Enum.join("  ||  ")}")
          end
        end

        if judged.same != [] do
          IO.puts("\n  Upheld — what a person is being asked to merge:\n")

          for entry <- Enum.take(judged.same, 5) do
            say.("• #{entry.pair.other.kind} — #{entry.pair.other.subject}")
            say.("  vs #{entry.pair.claim.kind} — #{entry.pair.claim.subject}")
            say.("  #{entry.why |> Enum.reject(&is_nil/1) |> Enum.join("  ||  ")}")
          end
        end

      {:error, error} ->
        say.("the readings failed: #{inspect(error)}")
    end
  end
end

IO.puts("")
