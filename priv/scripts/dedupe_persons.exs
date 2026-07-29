# Folds the Person rows that are one human being written down twice (LIVE: needs a key,
# costs money — and unlike the other sweeps this one CHANGES WHO THE RECORD SAYS WAS
# MISSING).
#
#     DRY=1 mix run priv/scripts/dedupe_persons.exs        # judge, fold nothing
#     DEEPINFRA_API_KEY=… mix run priv/scripts/dedupe_persons.exs
#
# WHY IT EXISTS. `identify` upserts on a name written the same way twice, and that is not
# how people write: 668 Person rows on the pilot event carried ZERO exact name collisions
# while one woman held four of them — `Belkys Josefina Barreto García`, `Belkis Josefina
# Barreto García`, `Belkys Barreto`, `Belkis Barreto`. A person counted twice is counted
# twice in everything the record later says.
#
# WHAT IT DOES. `PersonDuplicates` blocks candidates deterministically; position settles
# what it can with no model call at all; the model sees only the residue. A fold is a
# DEPRECATION, never a rewrite — the folded row keeps its name, carries `merged_into_id`
# and the reason, and every claim that named it also names the survivor. That is what
# makes it reversible, and reversibility is why a machine may do it
# ([[decision-2026-07-29-a-machine-may-fold-a-person]]).
#
# RUN DRY FIRST AND READ IT. This is the one sweep whose mistakes are people.
#
# Overridable: EVENT, LIMIT (blocks, 0 for all), PERSON_JUDGE_PROMPT, PERSON_JUDGE_MODEL, DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Narrative.PersonDuplicates
alias Wekui.Pipelines.PersonJudge

event_name = System.get_env("EVENT", "litoral-central-2026")
limit = System.get_env("LIMIT", "0") |> String.to_integer()
prompt_file = System.get_env("PERSON_JUDGE_PROMPT", "prompts/person_judge.v1.txt")
model = System.get_env("PERSON_JUDGE_MODEL", "deepseek-ai/DeepSeek-V4-Flash")
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

IO.puts("\nFolding duplicate people on #{event.name}#{if dry?, do: " — DRY", else: ""}\n")

before = length(Narrative.current_persons!(event.id))
blocks = PersonDuplicates.find(event.id)

say.("#{before} current Person rows")

say.(
  "#{length(blocks)} candidate block(s); largest holds #{blocks |> Enum.map(& &1.size) |> Enum.max(fn -> 0 end)}"
)

if blocks == [] do
  IO.puts("\n  nothing to fold.\n")
else
  agent =
    Core.register_agent!(%{
      event_id: event.id,
      model: model,
      prompt: File.read!(prompt_file)
    })

  started = System.monotonic_time(:second)

  opts = [dry: dry?, model: model, prompt: File.read!(prompt_file)]
  opts = if limit > 0, do: Keyword.put(opts, :limit, limit), else: opts

  # A DRY RUN THAT DOES NOT SAY WHAT IT WOULD DO IS NOT A DRY RUN. `sweep/3` only fills
  # `folds` when it actually folds, so a dry pass judges HERE and prints every proposal
  # — each one is a person. It does not then call `sweep/3`: judging twice would double
  # the spend to print the same answer.
  if dry? do
    chosen = if limit > 0, do: Enum.take(blocks, limit), else: blocks

    proposed =
      case PersonJudge.run(event, chosen, opts) do
        {:ok, found} -> found
        {:error, error} -> Mix.raise("the judge failed: #{inspect(error)}")
      end

    show = fn pairs, label ->
      IO.puts("\n  #{label} (#{length(pairs)}):\n")

      for {a, b, why} <- pairs do
        say.("• «#{a.full_name}»  +  «#{b.full_name}»")
        say.("  #{why}")
      end
    end

    show.(proposed.position, "Settled by position — no model called")
    show.(proposed.judged, "Judged by the model")

    if proposed.refused != [], do: say.("#{length(proposed.refused)} block(s) refused")

    IO.puts("")
    say.("nothing was folded. Re-run without DRY=1 to apply.")
    say.("in #{System.monotonic_time(:second) - started}s")
  else
    case PersonJudge.sweep(event, agent, opts) do
      {:ok, run} ->
        elapsed = System.monotonic_time(:second) - started
        s = run.summary

        IO.puts("")
        say.("settled by position (no model called) #{s["position"]}")
        say.("judged by the model                   #{s["judged"]}")
        say.("refused                               #{s["refused"]}")
        say.("FOLDED                                #{s["merged"]}")

        after_count = length(Narrative.current_persons!(event.id))
        say.("#{before} → #{after_count} current Person rows")
        say.("in #{elapsed}s. Receipt #{run.id}.")

        # Every fold, printed. This is the one sweep where each decision should be read:
        # a wrong fold is one family's relative folded into another's. The receipt
        # carries the NAMES, not ids, so this survives the rows changing later.
        if s["folds"] != [] do
          IO.puts("\n  Every fold it made:\n")

          for [kept, gone, why] <- s["folds"] do
            say.("• kept «#{kept}»  folded «#{gone}»")
            say.("  #{why}")
          end
        end

      {:error, error, run} ->
        say.("the sweep failed: #{inspect(error)} (receipt #{run.id})")
    end
  end
end

IO.puts("")
