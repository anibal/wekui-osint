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

# {one, other, note} — two places, not one. Each side is named with its type,
# because one of these pairs is two places of the SAME name once the typo below is
# corrected, and because a script that identified places only by name could not be
# run twice after its own rename. The note is his where he gave one.
aparts = [
  {{"El Palmar Este", "barrio"}, {"Av. El Palmar Este", "calle"},
   "a road named after a place is not the place"},
  {{"La Costanera", "sector"}, {"Avenida La Costanera", "calle"},
   "a road named after a place is not the place"},
  {{"Residencias Caraballeda", "edificio"}, {"Residencia Caraballeda I", "edificio"},
   "the numeral names another building"},
  {{"San Julián", "populated_place"}, {"San Julián", "sector"},
   "two places; he noted the sector's name was a typo, corrected below"},
  {{"Tanaguarena", "barrio"}, {"Tanaguarenita", "sector"}, nil},
  {{"Residencias Caraballeda Sol", "edificio"}, {"Residencias Caraballeda", "edificio"}, nil},
  {{"Edificio Caraballeda Suite", "edificio"}, {"Residencia Caraballeda I", "edificio"},
   "the numeral names another building"},
  {{"Residencias Coral Park", "edificio"}, {"Residencias RocaPark", "edificio"}, nil}
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

find_typed = fn {name, type} ->
  event.id
  |> Core.list_places!()
  |> Enum.find(&(&1.canonical_name == name and &1.type == type)) ||
    Mix.raise("no #{type} named #{inspect(name)} in #{event_name}")
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

# ── The typo he named while ruling San Juilán apart ──────────────────────────
#
# "apart (typo)" — two places, and the sector's name is a misspelling of the
# town's. Ruling them apart settles which places they are; it does not fix the
# spelling. This does, and keeps "San Juilán" as a name of kind :error so a Post
# that writes it still finds the sector.
#
# Looked up by BOTH names and by type: once the rename lands, the old name is no
# longer a canonical name to find it by — which is the point of the rename, and the
# reason a script that only knew the old one could not be run twice.
misspelt =
  event.id
  |> Core.list_places!()
  |> Enum.find(&(&1.type == "sector" and &1.canonical_name in ["San Juilán", "San Julián"])) ||
    Mix.raise("no sector San Juilán/San Julián in #{event_name}")

if misspelt.canonical_name == "San Juilán" do
  Curation.rename_place!(
    misspelt,
    "San Julián",
    curator,
    "The sector's name was a misspelling of the town's. Noted on the 2026-07-27 report."
  )

  say.("renamed “San Juilán” → “San Julián” (sector)")
else
  say.("already: the sector reads “#{misspelt.canonical_name}”")
end

# Ruling two places apart moves no status anywhere, so the act is the only record
# that the question was ever answered.
ruled = Curation.list_acts!(event.id) |> Enum.filter(&(&1.kind == :distinguish_places))
seen = MapSet.new(ruled, &MapSet.new([&1.place_id, &1.before["not_id"]]))

kept_apart =
  Enum.count(aparts, fn {one_named, other_named, note} ->
    one = find_typed.(one_named)
    other = find_typed.(other_named)

    if MapSet.member?(seen, MapSet.new([one.id, other.id])) do
      say.(
        "already: “#{one.canonical_name}” (#{one.type}) and “#{other.canonical_name}” (#{other.type}) are ruled apart"
      )

      false
    else
      reason =
        "Two places, not one. Ruled `apart` on the 2026-07-27 report" <>
          if note, do: " — #{note}.", else: "."

      Curation.distinguish_places!(other, one, curator, reason)

      say.(
        "apart: “#{other.canonical_name}” (#{other.type}) is not “#{one.canonical_name}” (#{one.type})"
      )

      true
    end
  end)

IO.puts("\n  #{folded} folded, #{kept_apart} ruled apart")
IO.puts("  #{length(Curation.list_acts!(event.id))} attributed act(s) on the record\n")
