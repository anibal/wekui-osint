# The operator's answers to the duplicate-places question, applied.
#
#     mix run priv/scripts/curate_2026_07_27_duplicates.exs
#
# No inference, no key, no spend.
#
# He answered in the report itself, by adding an OPERATOR ANSWER column to the
# table: nine pairs `fold`, eight `apart`. The answers were transcribed here BY
# HAND and by name. Nothing parses the report — an answer is prose with a
# judgement in it ("apart (typo)"), and the judgement is the part worth keeping.
#
# Two of his `apart` answers turned out to be rules rather than rows, and are now
# in `Wekui.Gazetteer.Duplicates` — a road named after a place is not the place,
# and a Roman numeral distinguishes a building. Four more needed knowledge of the
# ground that no rule reaches. Those are why `distinguish_places` exists: he
# answers once, and the question never returns.
#
# Idempotent: a place already folded is skipped, and a pair already ruled apart is
# not ruled again.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Curation

event_name = System.get_env("EVENT", "litoral-central-2026")
curator_name = System.get_env("CURATOR", "Aníbal Rojas")

# {keep, fold_away} — the second becomes a name of the first, its children move up,
# and it is deprecated onto the first. Ruled `fold` on the 2026-07-27 report.
folds = [
  {"McDonald's de Caraballeda", "Mc Donalds de Caraballeda"},
  {"Residencias Coral Bella", "Residencias Coralbella"},
  {"Residencia Mariana Mar", "Residencias Marianamar"},
  {"Edificio Opp27", "opp 27"},
  {"Edificio Caraballeda Suite", "Edif. Caraballeda Suites"},
  # Three rows of the table name one building three ways. The chain resolves: by
  # the time this runs, "opp 27" is already folded, so this lands on its survivor.
  {"opp 27", "OPPE 27"},
  {"Cueva de Urie", "Cueva de Uría"},
  {"Residencia Las Villas", "Res. La Villa"}
]

# {one, other, note} — two places, not one. The note is his where he gave one.
aparts = [
  {"El Palmar Este", "Av. El Palmar Este", "a road named after a place is not the place"},
  {"La Costanera", "Avenida La Costanera", "a road named after a place is not the place"},
  {"Residencias Caraballeda", "Residencia Caraballeda I", "the numeral names another building"},
  {"San Julián", "San Juilán", "two places; he noted the second name is a typo"},
  {"Tanaguarena", "Tanaguarenita", nil},
  {"Residencias Caraballeda Sol", "Residencias Caraballeda", nil},
  {"Edificio Caraballeda Suite", "Residencia Caraballeda I",
   "the numeral names another building"},
  {"Residencias Coral Park", "Residencias RocaPark", nil}
]

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)
  |> case do
    nil -> Mix.raise("no event named #{inspect(event_name)}")
    found -> found
  end

curator = Core.register_person!(%{event_id: event.id, name: curator_name})
say = fn message -> IO.puts("  " <> message) end

IO.puts("\n── the duplicate places, ruled ──────────────────────────────────\n")
say.("curator: #{curator.name}")

find = fn name ->
  event.id
  |> Core.list_places!()
  |> Enum.find(&(&1.canonical_name == name)) ||
    Mix.raise("no place named #{inspect(name)} in #{event_name}")
end

# A deprecated place reads through its replacement, and onwards if that one was
# deprecated too — so a chain of three names for one building lands on the survivor.
resolve = fn place ->
  Stream.iterate(place, fn p -> p.replaced_by_id && Core.get_place!(p.replaced_by_id) end)
  |> Enum.find(&(&1 == nil or &1.lifecycle != :deprecated))
end

folded =
  Enum.count(folds, fn {keep_name, fold_name} ->
    fold_away = find.(fold_name)

    if fold_away.lifecycle == :active do
      keep = resolve.(find.(keep_name))

      Curation.fold_place_into!(
        fold_away,
        keep,
        curator,
        "One place written two ways. Ruled `fold` on the 2026-07-27 report."
      )

      say.("folded “#{fold_name}” into “#{keep.canonical_name}”")
      true
    else
      say.("already: “#{fold_name}” is #{fold_away.lifecycle}")
      false
    end
  end)

# Ruling two places apart moves no status anywhere, so the act is the only record
# that the question was ever answered.
ruled = Curation.list_acts!(event.id) |> Enum.filter(&(&1.kind == :distinguish_places))
seen = MapSet.new(ruled, &MapSet.new([&1.place_id, &1.before["not_id"]]))

kept_apart =
  Enum.count(aparts, fn {one_name, other_name, note} ->
    one = find.(one_name)
    other = find.(other_name)

    if MapSet.member?(seen, MapSet.new([one.id, other.id])) do
      say.("already: “#{one_name}” and “#{other_name}” are ruled apart")
      false
    else
      reason =
        "Two places, not one. Ruled `apart` on the 2026-07-27 report" <>
          if note, do: " — #{note}.", else: "."

      Curation.distinguish_places!(other, one, curator, reason)
      say.("apart: “#{other_name}” is not “#{one_name}”")
      true
    end
  end)

IO.puts("\n  #{folded} folded, #{kept_apart} ruled apart")
IO.puts("  #{length(Curation.list_acts!(event.id))} attributed act(s) on the record\n")
