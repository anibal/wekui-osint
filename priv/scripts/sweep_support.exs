# Puts a bounded batch of unverified claims through the support gate and reports what it
# found, so the flag rate is measured before 2,240 claims are judged (LIVE: needs a key,
# costs money).
#
#     DRY=1 mix run priv/scripts/sweep_support.exs          # what it would judge
#     DEEPINFRA_API_KEY=… BATCH=200 mix run priv/scripts/sweep_support.exs
#
# WHY BOUNDED. The gate had read 356 of 2,596 claims. Sweeping the rest in one go bakes
# roughly 500 flags into the record on an instrument measured against 17 rulings — good
# (14/17, against v1's 10/17) but not proven at scale. So: judge a batch, read the flag
# rate against the 21% the old prompt produced, read a sample, then decide.
#
# WHAT IT WRITES. A support verdict and a note per claim, and nothing else. The gate is
# FLAG-ONLY — nothing is withheld from a reader, and a later pass overwrites a verdict,
# so this is reversible by re-running. It never merges, retracts or files anything.
#
# WHAT IT SKIPS. Claims with no ratified theme. `Verify.judge/2` refuses those without
# calling the model: a claim with no rule cannot be checked against one.
#
# Overridable: EVENT, BATCH, CONCURRENCY, SUPPORT_PROMPT, SUPPORT_MODEL, DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Pipelines.Verify

event_name = System.get_env("EVENT", "litoral-central-2026")
batch = System.get_env("BATCH", "200") |> String.to_integer()
concurrency = System.get_env("CONCURRENCY", "8") |> String.to_integer()
prompt_file = System.get_env("SUPPORT_PROMPT", "prompts/support.v2.txt")
model = System.get_env("SUPPORT_MODEL", "deepseek-ai/DeepSeek-V4-Flash")
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

IO.puts("\nSupport gate on #{event.name} — #{prompt_file}\n")

claims = Narrative.current_claims!(event.id)
unverified = Enum.filter(claims, &(&1.support == :unverified))
{judgeable, untethered} = Enum.split_with(unverified, & &1.theme_id)

say.("#{length(claims)} current claims · #{length(unverified)} unverified")

say.("#{length(judgeable)} carry a ratified rule; #{length(untethered)} do not and are skipped")

chosen = judgeable |> Enum.sort_by(& &1.id) |> Enum.take(batch)
say.("judging #{length(chosen)}")

if dry? or chosen == [] do
  IO.puts("")
else
  started = System.monotonic_time(:second)

  # `timeout: :infinity` is the standing rule here: a worker that answers slowly is not
  # a worker that failed, and a killed task loses the money already spent on it.
  results =
    chosen
    |> Task.async_stream(
      fn claim ->
        case Verify.run(claim, prompt_file: prompt_file, model: model) do
          {:ok, verified} -> {:ok, verified}
          {:error, error} -> {:error, claim, error}
        end
      end,
      max_concurrency: concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)

  elapsed = System.monotonic_time(:second) - started

  verdicts =
    results
    |> Enum.filter(&match?({:ok, _claim}, &1))
    |> Enum.map(fn {:ok, claim} -> claim end)

  failed = Enum.filter(results, &match?({:error, _claim, _error}, &1))
  tally = Enum.frequencies_by(verdicts, & &1.support)
  flagged = Map.get(tally, :overstated, 0) + Map.get(tally, :unsupported, 0)

  IO.puts("")
  say.("supported   #{Map.get(tally, :supported, 0)}")
  say.("overstated  #{Map.get(tally, :overstated, 0)}")
  say.("unsupported #{Map.get(tally, :unsupported, 0)}")

  if verdicts != [] do
    rate = Float.round(flagged * 100 / length(verdicts), 1)
    say.("FLAG RATE #{rate}% — the previous prompt produced 21% over 356 claims")
  end

  if failed != [] do
    say.(
      "#{length(failed)} unreadable: #{failed |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> Enum.take(3) |> inspect()}"
    )
  end

  say.("in #{elapsed}s")

  # A rate is not a reading. Print flags to be read, because the only thing that says
  # whether the instrument is right is a person looking at what it caught.
  IO.puts("\n  A sample of what it flagged:\n")

  verdicts
  |> Enum.filter(&(&1.support in [:overstated, :unsupported]))
  |> Enum.take(8)
  |> Enum.each(fn claim ->
    say.("• #{claim.support} — «#{claim.kind}» #{claim.subject}")
    say.("  #{String.slice(claim.support_note || "—", 0, 160)}")
  end)

  IO.puts("")
end
