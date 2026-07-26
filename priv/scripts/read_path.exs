# Task 0b — the read path's first real run (LIVE: needs a key, costs pennies).
#
#     DEEPINFRA_API_KEY=… mix run priv/scripts/read_path.exs
#
# One orchestrated pass over the event task 0a built — extract → resolve → verify
# → render — leaving one auditable Run receipt. Extraction and the support gate
# call the inference worker for real; everything else is deterministic.
#
# The event already holding claims is not re-extracted (that would mint duplicates
# until the merge-judge lands); it re-passes resolve, verify and render. Pass
# EXTRACT=force to re-extract anyway.
#
# Overridable: EVENT, PLACE_ID or PLACE_NAME, FROM, TO, EXTRACT, VERIFY,
# EXTRACTION_PROMPT, EXTRACTION_MODEL.

require Ash.Query

# dev logs every query at :debug, which drowns a script's own output.
Logger.configure(level: :info)

alias Wekui.Capture
alias Wekui.Core
alias Wekui.Pipelines

event_name = System.get_env("EVENT", "litoral-central-2026")
place_name = System.get_env("PLACE_NAME", "Caraballeda")
prompt_file = System.get_env("EXTRACTION_PROMPT", "prompts/extraction.v5.txt")
model = System.get_env("EXTRACTION_MODEL", "deepseek-ai/DeepSeek-V4-Flash")

say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)} — run priv/scripts/pilot_event.exs")
    found -> found
  end

places = Core.list_active_places!(event.id)

place =
  case System.get_env("PLACE_ID") do
    nil -> Enum.find(places, &(&1.canonical_name == place_name))
    id -> Enum.find(places, &(&1.id == id))
  end

place || Mix.raise("no active place #{inspect(System.get_env("PLACE_ID") || place_name)}")

# The agent is content-addressed on (model, prompt): registering the same pair
# returns the row task 0a already made, which is precisely the one to name.
agent = Core.register_agent!(%{event_id: event.id, model: model, prompt: File.read!(prompt_file)})

stamps = event.id |> Capture.list_posts!() |> Enum.map(& &1.posted_at)

parse_at = fn
  nil, fallback -> fallback
  value, _fallback -> value |> DateTime.from_iso8601() |> elem(1)
end

from = parse_at.(System.get_env("FROM"), Enum.min(stamps, DateTime, fn -> event.t0 end))

to =
  parse_at.(
    System.get_env("TO"),
    stamps |> Enum.max(DateTime, fn -> event.t0 end) |> DateTime.add(1, :second)
  )

opts =
  []
  |> then(&if System.get_env("EXTRACT") == "force", do: [{:extract, :force} | &1], else: &1)
  |> then(
    &if System.get_env("VERIFY") == "skip_verdicted",
      do: [{:verify, :skip_verdicted} | &1],
      else: &1
  )

IO.puts("\n── the read path ────────────────────────────────────────────────\n")
say.("event  #{event.name} (#{event.id})")
say.("place  #{place.canonical_name} (#{place.id})")
say.("window #{DateTime.to_iso8601(from)} → #{DateTime.to_iso8601(to)}")
say.("agent  #{agent.id} (#{agent.model})")
IO.puts("")

case Pipelines.run_read_path(event, agent, %{place_id: place.id, from: from, to: to}, opts) do
  {:error, {:preflight, reason}} ->
    Mix.raise("preflight refused: #{reason} — no receipt was opened")

  {:error, error} ->
    Mix.raise("the run did not finish: #{inspect(error)} — its receipt is still :running")

  {:ok, run} ->
    summary = run.summary

    say.("receipt #{run.id} — #{run.status}")
    say.("extract  #{inspect(summary["extract"])}")
    say.("resolve  #{inspect(summary["resolve"])}")
    say.("verify   #{inspect(summary["verify"])}")
    say.("render   #{inspect(summary["render"])}")
    say.("gates    #{inspect(summary["gates"])}")

    IO.puts("""

      ── the beat ──

      #{summary["beat"]["prose"]}

      sources: #{Enum.map_join(summary["beat"]["sources"], "  ", &"[#{&1["n"]}] #{&1["x_id"]}")}
    """)
end
