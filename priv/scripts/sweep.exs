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
# WHAT COUNTS AS READ. Either a claim ABLE TO SPEAK cites it — a claim with no theme
# is silent, so a post cited only by silent claims has not been read — or it carries a
# current theme judgment, meaning the extractor read it and correctly found no claim
# in it. Before topic routing was persisted, those posts looked unread and were paid
# for again on every sweep.
#
# WHAT IT DOES NOT DO. Only extract, per batch — which resolves each new claim as it is
# written. Verify and render are event-wide passes that re-walk every current claim, so
# running them per batch is quadratic for no gain; do one `read_path_batch.exs` after
# the sweep to verify, render and leave a receipt.
#
# It stops for two reasons and says which: nothing left to read, or the budget of
# batches is spent. A sweep that stops silently is not a sweep.
#
# A batch that FAILS does not stop it. The worker times out on a large answer often
# enough that halting wasted most of the budget twice; the batch's posts are set aside
# for this run, the failure is counted, and the sweep moves on. Those posts stay
# unread and are picked up by the next sweep — no retry inside the run, because
# repeating the same call is not more honest than reporting that it failed
# ([[decision-2026-07-26-reactor-not-sagents]]).
#
# Overridable: EVENT, BATCH (posts per call), BATCHES (how many), EXTRACTION_PROMPT,
# EXTRACTION_MODEL, DRY.

require Ash.Query

Logger.configure(level: :warning)

alias Wekui.Capture
alias Wekui.Core
alias Wekui.Judgment
alias Wekui.Narrative
alias Wekui.Pipelines.Extract
alias Wekui.Pipelines.ResidueAudit

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

  topical =
    event.id
    |> Judgment.list_theme_judgments!()
    |> Enum.filter(&is_nil(&1.superseded_at))
    |> MapSet.new(& &1.post_id)

  read = MapSet.union(spoken, topical)

  event.id
  |> Capture.list_posts!()
  |> Enum.reject(&MapSet.member?(read, &1.id))
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

  {tallies, failures, stopped} =
    Enum.reduce_while(1..budget, {[], [], :budget_spent}, fn n, {tallies, failures, _} ->
      set_aside = failures |> Enum.flat_map(& &1) |> MapSet.new()

      case unread.() |> Enum.reject(&MapSet.member?(set_aside, &1.id)) |> Enum.take(batch_size) do
        [] ->
          {:halt, {tallies, failures, :nothing_left}}

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

              # A refusal names something the vocabulary does not have in "theme".
              # One is noise; twenty-one in a batch is the model losing the list, and
              # the table alone cannot say which — so the names are printed when they
              # cluster. Not knowing WHAT was refused made a whole batch opaque.
              if s.skipped >= 3 do
                s.skips
                |> Enum.map(fn
                  {:no_theme, name} ->
                    "«#{name}» — not in the vocabulary"

                  {:rejected, %Ash.Error.Invalid{errors: [e | _]}} ->
                    "refused at the write path: #{e.message}"

                  {:rejected, _other} ->
                    "refused at the write path"

                  other ->
                    inspect(other)
                end)
                |> Enum.frequencies()
                |> Enum.sort_by(&(-elem(&1, 1)))
                |> Enum.each(fn {label, count} -> say.("        #{count}× #{label}") end)
              end

              # A batch that accounts for NONE of its posts will be handed exactly the
              # same posts next time, and the sweep spends its whole budget on two
              # posts it cannot place. Seen live: five batches, two posts, five calls.
              # Set them aside like a failure — they stay unread for the next sweep.
              if s.unread >= s.posts do
                say.("        accounted for nothing — set aside")
                {:cont, {[s | tallies], [Enum.map(posts, & &1.id) | failures], :budget_spent}}
              else
                {:cont, {[s | tallies], failures, :budget_spent}}
              end

            {:error, error} ->
              IO.puts(
                "  #{String.pad_leading(to_string(n), 5)}  FAILED — #{inspect(error)} (set aside, next sweep will take them)"
              )

              {:cont, {tallies, [Enum.map(posts, & &1.id) | failures], :budget_spent}}
          end
      end
    end)

  tallies = Enum.reverse(tallies)
  posts = Enum.sum(Enum.map(tallies, & &1.posts))
  residue = Enum.flat_map(tallies, & &1.unfitted)
  skipped = Enum.sum(Enum.map(tallies, & &1.skipped))

  IO.puts("")
  say.("stopped: #{inspect(stopped)}")
  if failures != [], do: say.("#{length(failures)} batch(es) failed and were set aside")

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
  # vocabulary does not have. APPENDED to a log as well as printed, because clustering
  # needs entries from several sweeps and a terminal scrollback is not a record —
  # a sweep whose findings survive only until the next command is not methodical.
  #
  # tmp/ is git-ignored: the residue quotes real posts, which name real people.
  if posts > 0 do
    say.(
      "residue #{length(residue)} raw entries — #{Float.round(length(residue) * 100 / posts, 1)} per 100 posts"
    )
  end

  # AUDIT BEFORE ANYONE READS IT (rung four, `docs/mechanisms.md`). Measured on 18
  # accumulated entries, 17 named a happening the vocabulary already held: at 44
  # themes the residue had stopped being the corpus asking for words and become the
  # extractor failing to find them. An unaudited residue is a queue.
  #
  # The audit is another fallible judge, so it may only REMOVE entries, never add or
  # rewrite one, and anything it does not rule on stays.
  audited =
    if residue == [] or System.get_env("AUDIT") == "0" do
      %{real: residue, covered: %{}, unaudited: []}
    else
      case ResidueAudit.run(event, Enum.uniq(residue)) do
        {:ok, r} ->
          say.("audit: #{map_size(r.covered)} of #{length(Enum.uniq(residue))} already covered")
          r

        {:error, e} ->
          say.("audit FAILED (#{inspect(e)}) — every entry kept")
          %{real: Enum.uniq(residue), covered: %{}, unaudited: []}
      end
    end

  residue = audited.real

  if residue != [] do
    IO.puts("\n  ── what the vocabulary could not name ──\n")
    for entry <- residue, do: IO.puts("  - #{entry}")

    File.mkdir_p!("tmp")

    File.write!(
      "tmp/residue.log",
      Enum.map_join(residue, "\n", &"#{DateTime.to_iso8601(DateTime.utc_now())}\t#{&1}") <> "\n",
      [:append]
    )

    say.("appended #{length(residue)} entries to tmp/residue.log")
  end

  IO.puts("")
end
