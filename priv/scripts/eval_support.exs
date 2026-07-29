# Measures a support-gate prompt against the claims that already carry a verdict, so a
# revision is judged before it touches 2,240 unverified claims (LIVE: needs a key, costs
# money).
#
#     DRY=1 mix run priv/scripts/eval_support.exs             # the sample, nothing spent
#     DEEPINFRA_API_KEY=… SAMPLE=20 mix run priv/scripts/eval_support.exs
#     PROMPT=prompts/support.v1.txt mix run priv/scripts/eval_support.exs   # the baseline
#
# WHAT IT MEASURES. Agreement with the recorded verdict, per stratum. Both strata matter
# and they matter differently:
#
#   * on claims v1 FLAGGED, a disagreement means the new prompt would let a bad claim
#     stand — the failure that ends up in a memorial;
#   * on claims v1 PASSED, a disagreement is either the new prompt catching what the old
#     one missed, or over-flagging. Only reading them tells you which, so it prints them.
#
# The recorded verdicts are NOT ground truth — they are one non-deterministic reading by
# an instrument known to be a first draft. This measures MOVEMENT and shows the cases;
# it never reports an accuracy.
#
# It writes nothing. `Verify.judge/2` exists so an evaluation cannot overwrite the
# baseline it is measured against.
#
# RUN IT N TIMES. The model is MoE and non-deterministic; one clean run proves nothing.
#
# Overridable: EVENT, PROMPT, MODEL, SAMPLE (per stratum), DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Pipelines.Verify

event_name = System.get_env("EVENT", "litoral-central-2026")
prompt_file = System.get_env("PROMPT", "prompts/support.v2.txt")
model = System.get_env("MODEL", "deepseek-ai/DeepSeek-V4-Flash")
sample = System.get_env("SAMPLE", "15") |> String.to_integer()
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

IO.puts("\nEvaluating #{prompt_file} on #{event.name}\n")

judged = event.id |> Narrative.current_claims!() |> Enum.reject(&(&1.support == :unverified))

{flagged, passed} = Enum.split_with(judged, &(&1.support in [:overstated, :unsupported]))

# Deterministic sample: sorted by id, not shuffled, so two runs of two prompts see the
# same claims. Comparing prompts on different samples measures the sample.
take = fn claims -> claims |> Enum.sort_by(& &1.id) |> Enum.take(sample) end
chosen = %{flagged: take.(flagged), passed: take.(passed)}

say.(
  "#{length(judged)} claims carry a verdict: #{length(flagged)} flagged, #{length(passed)} passed"
)

say.(
  "sampling #{length(chosen.flagged)} + #{length(chosen.passed)} = #{length(chosen.flagged) + length(chosen.passed)} calls"
)

if dry? do
  IO.puts("\n  DRY — the first three flagged in the sample:\n")

  for claim <- Enum.take(chosen.flagged, 3) do
    say.("• #{claim.support} — #{claim.kind} — #{claim.subject}")
    say.("  #{String.slice(claim.support_note || "", 0, 120)}")
  end
else
  started = System.monotonic_time(:second)

  results =
    Map.new(chosen, fn {stratum, claims} ->
      judged =
        Enum.map(claims, fn claim ->
          case Verify.judge(claim, prompt_file: prompt_file, model: model) do
            {:ok, verdict, note} -> %{claim: claim, verdict: verdict, note: note}
            {:error, error} -> %{claim: claim, verdict: {:error, error}, note: nil}
          end
        end)

      {stratum, judged}
    end)

  elapsed = System.monotonic_time(:second) - started

  for {stratum, judged} <- results do
    agreed = Enum.count(judged, &(&1.verdict == &1.claim.support))
    errors = Enum.count(judged, &match?({:error, _}, &1.verdict))

    IO.puts("")

    say.(
      "#{stratum}: #{agreed}/#{length(judged)} agreed with the recorded verdict" <>
        if(errors > 0, do: " (#{errors} unreadable)", else: "")
    )

    moved = Enum.reject(judged, &(&1.verdict == &1.claim.support))

    for entry <- Enum.take(moved, 6) do
      say.("  #{entry.claim.support} → #{inspect(entry.verdict)}")
      say.("    «#{entry.claim.kind}» — #{entry.claim.subject}")
      say.("    was:  #{String.slice(entry.claim.support_note || "—", 0, 110)}")
      say.("    now:  #{String.slice(entry.note || "—", 0, 110)}")
    end
  end

  # The note must be readable beside posts in Spanish. An English note makes a person
  # translate before they can rule.
  notes =
    results
    |> Map.values()
    |> List.flatten()
    |> Enum.map(& &1.note)
    |> Enum.reject(&(&1 in [nil, ""]))

  # Count English-only markers against Spanish-only ones. A single keyword list does not
  # work: "post" and "claim" appear verbatim in the Spanish notes, so a naive detector
  # called 18 of 20 Spanish notes English — an instrument reporting a number instead of
  # what it was doing, the same defect this whole week has been about.
  hits = fn note, pattern -> pattern |> Regex.scan(note) |> length() end

  english_only =
    ~r/\b(the|does|doesn|but|only|which|there|they|were|with|that|this|and|mention|states?|stated)\b/i

  spanish_only =
    ~r/\b(el|la|los|las|que|del|una|un|afirma|menciona|s[oó]lo|pero|est[aá]|hay|con|de)\b/i

  english = Enum.count(notes, &(hits.(&1, english_only) > hits.(&1, spanish_only)))

  IO.puts("")
  say.("notes reading as English: #{english} of #{length(notes)}")
  say.("in #{elapsed}s")
end

IO.puts("")
