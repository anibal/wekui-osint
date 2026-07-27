# Porting Caraballeda's real posts out of the old app.
#
#     mix run priv/scripts/port_corpus.exs
#
# No inference, no key, no spend: it only moves Posts and their Authors. Extracting
# them is a separate, LIVE step.
#
# The record has been standing on nine posts. The old Ecto app collected 13,248 for
# this event, 6,982 of them judged to be somewhere in the Caraballeda subtree — the
# corpus the memorial is actually about. This brings a WINDOW of them across, exactly
# as X sent them.
#
# ── Why a window and not all 6,982 ────────────────────────────────────────────
#
# Porting is free; extracting is not, and more to the point `Extract.run/4` puts the
# WHOLE batch in a single prompt — there is no batching, and the read path's
# `posts_in_scope` is the event's entire corpus, not a time slice. Porting seven
# thousand posts would therefore build one prompt nobody can pay for or trust. So the
# port is bounded here, at the source, and the batching gap is named rather than
# tripped over. Widen with FROM/TO once the extractor batches.
#
# The default hour is the one the pilot's own claims sit in (2026-06-25 04:00–05:00,
# 100 posts, 81 authors): the same happenings told by a hundred other accounts, which
# is what `Wekui.Narrative.Duplicates` was built to read.
#
# ── The nine the record already holds ─────────────────────────────────────────
#
# The pilot's posts carry the old app's ROW ID as their `x_id` ("129"), not the X post
# id ("2070003831404908894"), and their text is editorially REWRITTEN — 1,732 characters
# against the 3,788 actually written, and not only noise: the rehearsal of post 3920
# drops the body lying between the rescuers and Aaron, and 4746 (123 against 871) keeps
# the toll and drops the volunteers still clearing rubble by hand.
#
# This script SKIPS a post the record already holds under its row id, so the nine are
# not doubled; a Post is never edited and never deleted, so the nine stand as they are.
# Set INCLUDE_HELD=1 to bring their real payloads across anyway, as new Posts.
#
# Idempotent: authors and posts are both upserts, and post identity is (event, x_id).
#
# Overridable: OLD_DB, EVENT, ROOT_PLACE, FROM, TO, LIMIT, INCLUDE_HELD.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Capture
alias Wekui.Core

old_db = System.get_env("OLD_DB", Path.expand("~/Sandboxes/Venezuela7275/wekui/wekui_dev.db"))
event_name = System.get_env("EVENT", "litoral-central-2026")
root_place = System.get_env("ROOT_PLACE", "5") |> String.to_integer()
from = System.get_env("FROM", "2026-06-25T04:00:00")
to = System.get_env("TO", "2026-06-25T05:00:00")
limit = System.get_env("LIMIT", "100000") |> String.to_integer()
include_held? = System.get_env("INCLUDE_HELD") == "1"

say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

File.exists?(old_db) || Mix.raise("no database at #{old_db} — set OLD_DB")

IO.puts("\n── porting Caraballeda's posts ──────────────────────────────────\n")
say.("from   #{old_db}")
say.("into   #{event.name} (#{event.id})")
say.("window #{from} → #{to}")

# ── the old app, read-only ────────────────────────────────────────────────────
#
# Opened directly rather than through Ecto: the old schema is not this app's, and a
# port is the one job that legitimately reads a foreign database. Read-only, because
# nothing here may touch the source of truth we are copying from.
{:ok, db} = Exqlite.Sqlite3.open(old_db, mode: :readonly)

# A post belongs to Caraballeda if its LIVE place judgment lands anywhere in the
# subtree — the parish itself, a sector, a building. The old app's judgments are used
# only to CHOOSE the posts; none of them is carried over. Placement in this record is
# a claim's property, resolved fresh from what the posts say.
sql = """
with recursive sub(id) as (
  select ?1 union all select p.id from places p join sub on p.parent_id = sub.id
)
select distinct
  po.id, po.x_post_id, po.posted_at, po.raw_payload,
  a.x_user_id, a.username, a.display_name
from place_judgments pj
join sub on pj.place_id = sub.id
join posts po on po.id = pj.post_id
join authors a on a.id = po.author_id
where pj.superseded_at is null
  and po.posted_at >= ?2
  and po.posted_at < ?3
order by po.posted_at asc, po.id asc
limit ?4
"""

{:ok, statement} = Exqlite.Sqlite3.prepare(db, sql)
:ok = Exqlite.Sqlite3.bind(statement, [root_place, from, to, limit])
{:ok, rows} = Exqlite.Sqlite3.fetch_all(db, statement)
:ok = Exqlite.Sqlite3.close(db)

say.("found  #{length(rows)} post(s) in the Caraballeda subtree")

# The nine cleaned pilot posts are identified by the old app's row id sitting in the
# new record's `x_id` — the only trace of how they were made.
held = event.id |> Capture.list_posts!() |> MapSet.new(& &1.x_id)

{skipped, portable} =
  Enum.split_with(rows, fn [id | _rest] ->
    not include_held? and MapSet.member?(held, to_string(id))
  end)

if skipped != [] do
  say.("skip   #{length(skipped)} already held as cleaned pilot post(s)")
end

# ── authors first: a Post requires a same-event Author ────────────────────────
authors =
  portable
  |> Enum.map(fn [_id, _x, _at, _payload, x_user_id, username, display_name] ->
    {x_user_id, username, display_name}
  end)
  |> Enum.uniq_by(&elem(&1, 0))
  |> Map.new(fn {x_user_id, username, display_name} ->
    author =
      Capture.record_author!(%{
        event_id: event.id,
        x_id: x_user_id,
        handle: username,
        display_name: display_name
      })

    {x_user_id, author}
  end)

say.("authors #{map_size(authors)} recorded")

# ── the posts, exactly as X sent them ─────────────────────────────────────────
#
# The payload is the record we can never ask for again, so it crosses whole. `text`
# is read out of it rather than out of the old app's `normalized_text`, which is
# lowercased and accent-folded for matching and is not what anybody wrote.
ported =
  Enum.map(portable, fn [_id, x_post_id, posted_at, raw_payload, x_user_id, _u, _d] ->
    payload = Jason.decode!(raw_payload)
    {:ok, at, _offset} = DateTime.from_iso8601(posted_at)

    Capture.collect_post!(%{
      event_id: event.id,
      author_id: authors[x_user_id].id,
      x_id: x_post_id,
      text: payload["text"],
      posted_at: at,
      payload: payload
    })
  end)

corpus = Capture.list_posts!(event.id)

IO.puts("""

  #{length(ported)} post(s) ported — the event now holds #{length(corpus)}

  ── nothing has read them yet. Extracting is LIVE and costs money:

      DEEPINFRA_API_KEY=… mix run priv/scripts/read_path.exs

     and it feeds the WHOLE corpus to the extractor in one prompt. Read the note at
     the head of this script before running it on more than a few hundred posts.
""")
