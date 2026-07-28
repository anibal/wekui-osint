# The vocabulary of happenings, proposed for ratification.
#
#     mix run priv/scripts/seed_taxonomy.exs
#
# No inference, no key, no spend. It reads a committed data file and writes rows.
#
# Twenty-one themes, every one born :proposed. Nobody has signed them, and until
# somebody does they are not the vocabulary — they are a proposal about it. The
# operator promotes what he blesses, renames what reads wrong, and discards the rest,
# each as an attributed act (`Wekui.Curation.promote_theme!/3`).
#
# Where the data came from: three independent readers, an identical brief, an
# identical 302-post sample — a deterministic 1-in-23 slice of the 6,982 Caraballeda
# posts, exact duplicates removed, across all eight days. Themes were matched by WHICH
# POSTS EACH COVERS, not by the words each reader chose. Ten were reached by all three,
# seven by two of three, and four are structural nodes that group the rest. See
# `docs/pages/research-2026-07-27-three-readers-one-taxonomy.md`.
#
# Idempotent: a theme already held is left exactly as it is, whatever its lifecycle.
# Running it again never un-promotes what a person ratified, and never re-proposes what
# they discarded.
#
# Overridable: EVENT.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Taxonomy

event_name = System.get_env("EVENT", "litoral-central-2026")
say = fn message -> IO.puts("  " <> message) end

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

IO.puts("\n── the vocabulary of happenings ─────────────────────────────────\n")
say.("event  #{event.name} (#{event.id})")

counts = Taxonomy.Seed.litoral_central(event.id)
say.("seeded #{counts.created} theme(s) created, #{counts.reused} already held")

themes = Taxonomy.list_themes!(event.id)
by_id = Map.new(themes, &{&1.id, &1})
by_nature = Enum.frequencies_by(themes, & &1.nature)
by_life = Enum.frequencies_by(themes, & &1.lifecycle)

say.("nature #{by_nature[:happening] || 0} happening, #{by_nature[:topic] || 0} topic")
say.("state  #{Enum.map_join(by_life, ", ", fn {k, n} -> "#{n} #{k}" end)}")

IO.puts("")

themes
|> Enum.filter(&is_nil(&1.parent_id))
|> Enum.each(fn root ->
  IO.puts("  #{root.name}")

  themes
  |> Enum.filter(&(&1.parent_id == root.id))
  |> Enum.each(fn child ->
    IO.puts("      └ [#{child.nature}] #{child.name}")
  end)
end)

_ = by_id

IO.puts("""

  ── nothing is ratified. Read them on the report, then sign what you agree with:

      mix run priv/scripts/report.exs

     A theme nobody signed does not exist yet: no claim can carry it, and the
     extractor cannot see it.
""")
