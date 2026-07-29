# The read path over a NAMED batch (LIVE: needs a key, costs money).
#
#     DRY=1 mix run priv/scripts/read_path_batch.exs        # what would be fed
#     DEEPINFRA_API_KEY=… mix run priv/scripts/read_path_batch.exs
#
# `read_path.exs` runs the path over the event's whole corpus and refuses to extract
# onto an event that already holds a claim ([[decision-2026-07-26-extract-once-per-event]]).
# Both rules are right for a re-run and wrong for a corpus that grew: the 98 posts
# `port_corpus.exs` brought have never been read, and forcing the whole corpus would
# re-feed the nine rehearsal posts and mint a duplicate of every claim already held.
#
# That decision left this door open — "the read path can still be aimed by hand:
# `posts:` overrides the scope and `extract: :force` overrides the skip, so a
# deliberate, named batch is expressible. Nothing automatic is." This is the hand.
#
# The batch is: posts in the window that NO CLAIM ABLE TO SPEAK cites. A claim with no
# theme is silent — the record cannot say what kind of happening it is — so a post
# cited only by silent claims has not been read by the vocabulary, whatever an earlier
# rule thought. That is not the citation-coverage rule that mis-fired: a post the
# extractor correctly DROPPED is uncited and belongs in no batch either, and here it
# is simply re-read once, which is the cost of aiming by hand.
#
# The receipt says `extract: force` and carries the batch size, so the run does not
# read as though the pipeline chose this by itself.
#
# Overridable: EVENT, PLACE_NAME/PLACE_ID, FROM, TO, VERIFY, EXTRACTION_PROMPT,
# EXTRACTION_MODEL, DRY.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Capture
alias Wekui.Core
alias Wekui.Narrative
alias Wekui.Pipelines

event_name = System.get_env("EVENT", "litoral-central-2026")
place_name = System.get_env("PLACE_NAME", "Caraballeda")
# v8: the only prompt that reads the ratified vocabulary, so the only one whose claims
# can reach a reader at all. The default must be the best reading we have, or the next
# person runs a worse one by accident.
prompt_file = System.get_env("EXTRACTION_PROMPT", "prompts/extraction.v8.txt")
model = System.get_env("EXTRACTION_MODEL", "deepseek-ai/DeepSeek-V4-Flash")
batch_from = System.get_env("FROM", "2026-06-25T04:00:00Z")
batch_to = System.get_env("TO", "2026-06-25T05:00:00Z")
dry? = System.get_env("DRY") == "1"

say = fn message -> IO.puts("  " <> message) end
at = fn iso -> iso |> DateTime.from_iso8601() |> elem(1) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

place =
  case System.get_env("PLACE_ID") do
    nil -> Enum.find(Core.list_active_places!(event.id), &(&1.canonical_name == place_name))
    id -> Enum.find(Core.list_active_places!(event.id), &(&1.id == id))
  end

place || Mix.raise("no active place #{inspect(System.get_env("PLACE_ID") || place_name)}")

agent = Core.register_agent!(%{event_id: event.id, model: model, prompt: File.read!(prompt_file)})

posts = Capture.list_posts!(event.id)

# A post is READ when a claim that can SPEAK cites it. A claim with no theme is
# silent — the record cannot say what kind of happening it is — so a post cited only
# by silent claims has not been read by the vocabulary, whatever the old rule thought.
already_read =
  event.id
  |> Narrative.current_claims!()
  |> Enum.filter(& &1.theme_id)
  |> Enum.flat_map(&Narrative.list_claim_citations!(&1.id))
  |> MapSet.new(& &1.post_id)

from = at.(batch_from)
to = at.(batch_to)

batch =
  posts
  |> Enum.filter(fn post ->
    DateTime.compare(post.posted_at, from) != :lt and
      DateTime.compare(post.posted_at, to) == :lt and
      not MapSet.member?(already_read, post.id)
  end)
  |> Enum.sort_by(& &1.posted_at, DateTime)

IO.puts("\n── the read path, over a named batch ────────────────────────────\n")
say.("event  #{event.name} (#{event.id})")
say.("place  #{place.canonical_name} (#{place.id})")
say.("window #{batch_from} → #{batch_to}")

say.(
  "corpus #{length(posts)} post(s); #{MapSet.size(already_read)} read into a claim that can speak"
)

say.(
  "batch  #{length(batch)} post(s) — #{batch |> Enum.map(&String.length(&1.text)) |> Enum.sum()} characters"
)

if batch == [], do: Mix.raise("nothing to read — every post in the window is already cited")

if dry? do
  IO.puts("\n  DRY=1 — nothing ran, nothing was spent.\n")
else
  # The beat covers the whole story, not just the batch: a claim must never be lost
  # for falling outside a render window.
  stamps = Enum.map(posts, & &1.posted_at)
  beat_from = Enum.min(stamps, DateTime, fn -> event.t0 end)
  beat_to = stamps |> Enum.max(DateTime, fn -> event.t0 end) |> DateTime.add(1, :second)

  opts = [
    posts: batch,
    extract: :force,
    verify: String.to_atom(System.get_env("VERIFY", "skip_verdicted"))
  ]

  args = %{place_id: place.id, from: beat_from, to: beat_to}

  case Pipelines.run_read_path(event, agent, args, opts) do
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
      """)
  end
end
