# Reads the corpus in batches, methodically, and reports what it learned (LIVE: needs
# a key, costs money).
#
#     DRY=1 mix run priv/scripts/sweep.exs           # what it would read
#     DEEPINFRA_API_KEY=… mix run priv/scripts/sweep.exs
#
# Aiming each batch by hand was the binding constraint: 25 posts per call and a human
# choosing the window every time. This walks the corpus itself.
#
# HOW IT BATCHES. By POST COUNT, not by clock. A time window gives wildly uneven
# batches — one hour of day 1 holds a hundred posts and one hour of day 8 holds nine —
# and the wall is on what the model has to WRITE, which scales with posts and not with
# minutes ([[open-extraction-does-not-batch]]).
#
# WHAT COUNTS AS UNREAD. A post no claim ABLE TO SPEAK cites. A claim with no theme is
# silent, so a post cited only by silent claims has not been read by the vocabulary.
#
# WHAT IT DOES NOT DO. Only extract, per batch — which resolves each new claim as it is
# written. Verify and render are event-wide passes that re-walk every current claim, so
# running them per batch is quadratic for no gain; do one `read_path_batch.exs` after
# the sweep to verify, render and leave a receipt.
#
# It stops early on three conditions, and says which: nothing left to read, the budget
# of batches is spent, or a batch fails. A sweep that stops silently is not a sweep.
#
# Overridable: EVENT, BATCH (posts per call), BATCHES (how many), EXTRACTION_PROMPT,
# EXTRACTION_MODEL, DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Capture
alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Pipelines.Extract

event_name = System.get_env("EVENT", "litoral-central-2026")
batch_size = System.get_env("BATCH", "25") |> String.to_integer()
budget = System.get_env("BATCHES", "6") |> String.to_integer()
prompt_file = System.get_env("EXTRACTION_PROMPT", "prompts/extraction.v9.txt")
model = System.get_env("EXTRACTION_MODEL", "deepseek-ai/DeepSeek-V4-Flash")
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

agent = Core.register_agent!(%{event_id: event.id, model: model, prompt: File.read!(prompt_file)})

unread = fn ->
  spoken =
    event.id
    |> Narrative.current_claims!()
    |> Enum.filter(& &1.theme_id)
    |> Enum.flat_map(&Narrative.list_claim_citations!(&1.id))
    |> MapSet.new(& &1.post_id)

  event.id
  |> Capture.list_posts!()
  |> Enum.reject(&MapSet.member?(spoken, &1.id))
  |> Enum.sort_by(& &1.posted_at, DateTime)
end

IO.puts("\n── sweeping the corpus ──────────────────────────────────────────\n")
say.("event  #{event.name}")
say.("prompt #{prompt_file}")
say.("plan   up to #{budget} batches of #{batch_size}")

pending = unread.()
say.("unread #{length(pending)} of #{length(Capture.list_posts!(event.id))} post(s)")

if dry? do
  IO.puts("\n  DRY=1 — nothing ran, nothing was spent.\n")
else
  IO.puts("\n  batch  posts  claims  filed  topics  routed  refused  residue  unread")

  {tallies, stopped} =
    Enum.reduce_while(1..budget, {[], :budget_spent}, fn n, {tallies, _} ->
      case Enum.take(unread.(), batch_size) do
        [] ->
          {:halt, {tallies, :nothing_left}}

        posts ->
          case Extract.run(event, agent, posts, place_scope: "Caraballeda") do
            {:ok, s} ->
              routed = s.routed_from_theme |> Map.values() |> Enum.sum()
              topics = s.topics |> Map.values() |> Enum.sum()

              IO.puts(
                "  #{String.pad_leading(to_string(n), 5)}  " <>
                  "#{String.pad_leading(to_string(s.posts), 5)}  " <>
                  "#{String.pad_leading(to_string(s.claims), 6)}  " <>
                  "#{String.pad_leading(to_string(s.drafted), 5)}  " <>
                  "#{String.pad_leading(to_string(topics), 6)}  " <>
                  "#{String.pad_leading(to_string(routed), 6)}  " <>
                  "#{String.pad_leading(to_string(s.skipped), 7)}  " <>
                  "#{String.pad_leading(to_string(length(s.unfitted)), 7)}  " <>
                  "#{String.pad_leading(to_string(s.unread), 6)}"
              )

              {:cont, {[s | tallies], :budget_spent}}

            {:error, error} ->
              IO.puts("  #{n}  FAILED — #{inspect(error)}")
              {:halt, {tallies, {:batch_failed, error}}}
          end
      end
    end)

  tallies = Enum.reverse(tallies)
  posts = Enum.sum(Enum.map(tallies, & &1.posts))
  residue = Enum.flat_map(tallies, & &1.unfitted)
  skipped = Enum.sum(Enum.map(tallies, & &1.skipped))

  IO.puts("")
  say.("stopped: #{inspect(stopped)}")

  topics =
    tallies
    |> Enum.flat_map(&Map.to_list(&1.topics))
    |> Enum.reduce(%{}, fn {k, v}, a ->
      Map.update(a, k, v, &(&1 + v))
    end)

  say.(
    "#{length(tallies)} batch(es), #{posts} post(s), " <>
      "#{Enum.sum(Enum.map(tallies, & &1.drafted))} claim(s) filed, " <>
      "#{topics |> Map.values() |> Enum.sum()} routed to a topic, #{skipped} refused"
  )

  # A batch that is nearly all topics is not a failure — it is the shape of this
  # corpus. The clustering spike measured 981 posts, 7.4%, sharing one missing-person
  # template. Without this line a sweep of them reads as the extractor doing nothing.
  if topics != %{} do
    IO.puts("")

    for {name, n} <- Enum.sort_by(topics, &(-elem(&1, 1))),
        do: say.("  #{String.pad_leading(to_string(n), 4)}  #{name}")
  end

  if posts > 0 do
    say.(
      "residue #{length(residue)} entries — #{Float.round(length(residue) * 100 / posts, 1)} per 100 posts"
    )
  end

  # The residue is the whole point of sweeping: it is the corpus asking for words the
  # vocabulary does not have. Written out so it can be clustered, never proposed one by
  # one (`docs/mechanisms.md`).
  if residue != [] do
    IO.puts("\n  ── what the vocabulary could not name ──\n")
    for entry <- residue, do: IO.puts("  - #{entry}")
  end

  IO.puts("")
end
