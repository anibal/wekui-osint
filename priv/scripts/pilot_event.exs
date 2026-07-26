# Task 0a — the clean pilot event.
#
#     mix run priv/scripts/pilot_event.exs
#
# No inference, no key, no spend: it only sets up the world the read path runs on.
# The pilot's proven claims were extracted on a 6-place STUB gazetteer, while the
# real 296-node tree was seeded onto a different, claim-less event — so no single
# event held both, and the read path had no valid target. This builds that event
# from the deterministic half: a fresh Event under the canonical name, the real
# gazetteer, the extraction agent, and the pilot's Author + Posts ported with their
# original payloads. Re-extracting them onto the real tree is task 0b — the
# pipeline's first real run, which needs DEEPINFRA_API_KEY.
#
# Idempotent: every write is an upsert or a find-or-create, so running it twice
# changes nothing. The one-time step is stepping the old stub event aside: an event
# under the target name that carries Posts but no seeded gazetteer IS the stub, and
# gets renamed to the source name before the fresh one is created.
#
# Overridable: TARGET_EVENT, SOURCE_EVENT, EXTRACTION_PROMPT, EXTRACTION_MODEL.

require Ash.Query

# dev logs every query at :debug, which drowns a script's own output.
Logger.configure(level: :info)

alias Wekui.Capture
alias Wekui.Core
alias Wekui.Gazetteer

target_name = System.get_env("TARGET_EVENT", "litoral-central-2026")
source_name = System.get_env("SOURCE_EVENT", "litoral-central-2026-stub")
prompt_file = System.get_env("EXTRACTION_PROMPT", "prompts/extraction.v5.txt")
model = System.get_env("EXTRACTION_MODEL", "deepseek-ai/DeepSeek-V4-Flash")

# A seeded tree is hundreds of nodes; the stub was six. Nothing in between is a
# gazetteer, so this tells the two apart without hardcoding an id.
seeded_at_least = 50

say = fn message -> IO.puts("  " <> message) end

find_event = fn name ->
  Core.Event
  |> Ash.Query.filter(name == ^name)
  |> Ash.read_one!(authorize?: false)
end

active_places = fn event -> length(Core.list_active_places!(event.id)) end

IO.puts("\n── task 0a — the clean pilot event ──────────────────────────────\n")

source =
  case {find_event.(source_name), find_event.(target_name)} do
    {nil, nil} ->
      Mix.raise("""
      no event named #{inspect(source_name)} to port the pilot's posts from, and \
      nothing under #{inspect(target_name)} to step aside. Set SOURCE_EVENT to the \
      event that holds the 9 pilot posts.
      """)

    {nil, stub} ->
      posts = length(Capture.list_posts!(stub.id))

      if posts > 0 and active_places.(stub) < seeded_at_least do
        say.(
          "stepping the stub aside: #{target_name} → #{source_name} (#{posts} posts, no gazetteer)"
        )

        Core.update_event!(stub, %{name: source_name})
      else
        Mix.raise("""
        #{inspect(target_name)} already holds #{posts} posts and a seeded gazetteer — \
        it is not the stub. Set SOURCE_EVENT/TARGET_EVENT explicitly.
        """)
      end

    {source, _target} ->
      source
  end

say.("source event: #{source.name} (#{source.id})")

event =
  case find_event.(target_name) do
    nil ->
      created =
        Core.create_event!(%{
          name: target_name,
          t0: source.t0,
          goal: source.goal,
          timezone: source.timezone
        })

      say.("created event: #{created.name} (#{created.id})")
      created

    existing ->
      say.("reusing event: #{existing.name} (#{existing.id})")
      existing
  end

# ── the gazetteer: the real 296-node Caraballeda tree, born :active ───────────
seeded = Gazetteer.Seed.caraballeda(event.id)

say.(
  "gazetteer: #{seeded.created} places created, #{seeded.reused} reused, #{seeded.names} names added"
)

# ── the extraction agent: content-addressed on (model, prompt) ────────────────
agent = Core.register_agent!(%{event_id: event.id, model: model, prompt: File.read!(prompt_file)})
say.("agent: #{agent.id} (#{agent.model}, #{prompt_file})")

# ── the corpus: authors first — a Post requires a same-event Author ───────────
source_posts = source.id |> Capture.list_posts!() |> Enum.sort_by(& &1.posted_at, DateTime)

authors =
  source_posts
  |> Enum.map(& &1.author_id)
  |> Enum.uniq()
  |> Map.new(fn author_id ->
    from = Capture.get_author!(author_id)

    to =
      Capture.record_author!(%{
        event_id: event.id,
        x_id: from.x_id,
        handle: from.handle,
        display_name: from.display_name
      })

    {author_id, to}
  end)

# Post identity is (event_id, x_id), so the same x_id on a new event is a fresh
# row; the payload is carried over exactly as X sent it — we can never re-ask.
posts =
  Enum.map(source_posts, fn post ->
    Capture.collect_post!(%{
      event_id: event.id,
      author_id: authors[post.author_id].id,
      x_id: post.x_id,
      text: post.text,
      posted_at: post.posted_at,
      payload: post.payload
    })
  end)

say.("corpus: #{map_size(authors)} authors, #{length(posts)} posts ported")

stamps = Enum.map(posts, & &1.posted_at)

say.(
  "posts span: #{DateTime.to_iso8601(Enum.min(stamps, DateTime))} → " <>
    "#{DateTime.to_iso8601(Enum.max(stamps, DateTime))}"
)

caraballeda =
  event.id
  |> Core.list_active_places!()
  |> Enum.find(&(&1.canonical_name == "Caraballeda"))

IO.puts("""

  ── ready. Task 0b is the pipeline's first real run (needs a key, costs pennies):

      DEEPINFRA_API_KEY=… mix run priv/scripts/read_path.exs

     event      #{event.id}
     agent      #{agent.id}
     place      #{(caraballeda && caraballeda.id) || "(no place named Caraballeda — pass PLACE_ID)"}
""")
