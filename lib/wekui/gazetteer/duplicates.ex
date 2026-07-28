defmodule Wekui.Gazetteer.Duplicates do
  @moduledoc """
  Finds Places the gazetteer holds twice, so a person rules on the pattern instead
  of stumbling over one row at a time.

  A gazetteer built from several sources records the same place more than once —
  under a popular name, under a typo, under a spelling nobody else uses. Each
  duplicate splits a story: two nodes carry half the claims each, and a reader meets
  the same place twice. The tie only becomes *visible* when a claim happens to name
  it, which is far too late.

  Two shapes, and the difference between them is the whole point:

    * **`:certain`** — a Place carrying **exactly** an ancestor's name. Nothing can be
      inside itself, so this is not a judgement call. It is the shape the operator
      ruled on: *"Caraballeda is the Parish. Sector Caraballeda, Urbanización
      Caraballeda, and any other combination are just alternatives from the popular
      speech."*
    * **`:candidate`** — two siblings whose names nearly match once their leading type
      word is dropped. `"Avenida La Costanera"` and `"La Costanera"` are one road;
      `"Cueva de Urie"` and `"Cueva de Uría"` are one cave and a typo. **A person
      decides**, because nothing in the strings can.

  ## Why the type word alone is not enough

  Dropping the leading type word turns `"Urbanización Caraballeda"` into
  `"Caraballeda"`, which is right — an urbanización is the same *kind* of thing as
  the parish that shares its name. But it also turns `"Residencias Caraballeda"` into
  `"Caraballeda"`, which is wrong: that is a real building named after the parish it
  stands in, and folding it away would destroy exactly the granularity the recursive
  model exists for. So the reduction is deliberately **not** used against ancestors —
  only the exact-name rule is, and only between a Place and its own ancestors.

  ## Why a road, an area and a structure never collapse

  Three kinds of thing share names constantly — an avenue runs along the strip it is
  named after, a building stands in the sector it borrows its name from — and none of
  those pairs is ever one node. So a pair whose types name different kinds of thing is
  never offered, however exactly the strings match. A type nobody has classified
  suppresses nothing: an unknown label is a reason to ask, never to stay quiet.

  ## Why a number or a direction ends the question

  `"El Palmar Este"` and `"El Palmar Oeste"` score 0.978 on Jaro. `"Residencias Green
  8 suites"` and `"Residencias Green 7 Suites"` score 0.952. They are as close as the
  real duplicates and they are not duplicates at all — the one token that differs is
  the one token that *distinguishes*. So a pair whose numbers or compass directions
  disagree is never offered: a near-miss on the distinguishing token is the opposite
  of a match ([[principle-a-wrong-answer-is-worse-than-none]]).

  Deterministic and read-only: it proposes nothing, writes nothing, and needs no
  model. What it finds becomes a question in the report, and a person's answer
  becomes a `Wekui.Curation.fold_place_into!/4`.
  """

  alias Wekui.Core
  alias Wekui.Gazetteer.Marks
  alias Wekui.Normalize

  # The leading words that name what KIND of place a name is. Shared in spirit with
  # `Wekui.Narrative.PlaceResolver` — that one strips them off a mention coming in,
  # this one strips them off the gazetteer's own names.
  # Two sibling names must be this close (Jaro) to be worth a person's attention.
  @jaro_threshold 0.92

  # Tokens that exist to tell two places apart. "Este" and "Oeste" differ by four
  # letters and by the entire point of the name.
  # What kind of thing a type names. A road is a line, an area is a region, a
  # structure is a thing standing in one — and no two of those are ever the same
  # node, however exactly their names match. "Avenida La Costanera" runs along "La
  # Costanera"; "Residencias Los Corales" stands in "Los Corales"; "Residencia
  # Caraballeda I" is not the sector "Caraballeda 1".
  #
  # This is the general form of a rule the operator gave twice on 2026-07-27, on the
  # two pairs that scored a perfect 1.0. A type absent here classifies as nothing and
  # suppresses nothing — an unknown label is a reason to ask, never to stay quiet.
  @kinds_of_thing %{
    "edificio" => :structure,
    "calle" => :road,
    "avenida" => :road,
    "carrera" => :road,
    "autopista" => :road,
    "vialidad" => :road,
    "vialidad y puentes" => :road,
    "pais" => :area,
    "estado" => :area,
    "municipio" => :area,
    "parroquia" => :area,
    "populated_place" => :area,
    "urbanizacion" => :area,
    "barrio" => :area,
    "sector" => :area,
    "zona" => :area,
    "plaza" => :area
  }

  @doc """
  Every pair of active Places in `event_id` that may be one place recorded twice,
  most certain first.

  Each entry is `%{certainty:, place:, other:, why:}` where `place` is the one to
  fold away and `other` the one to keep — the ancestor, or the elder sibling, since
  the older row is the one other records already point at.
  """
  def find(event_id) do
    places = event_id |> Core.list_places!() |> Enum.filter(&(&1.lifecycle == :active))
    by_id = Map.new(places, &{&1.id, &1})

    (inside_its_own_name(places, by_id) ++ near_names(places, by_id))
    |> Enum.sort_by(&{&1.certainty != :certain, -&1.score, &1.place.canonical_name})
  end

  # A Place carrying exactly an ancestor's name. A place cannot be inside itself, so
  # one of the two is a name for the other — and the ancestor is the one to keep,
  # because everything else in the tree already hangs beneath it.
  defp inside_its_own_name(places, by_id) do
    for place <- places,
        ancestor <- ancestors(place, by_id),
        fold(place.canonical_name) == fold(ancestor.canonical_name) do
      %{
        certainty: :certain,
        score: 1.0,
        place: place,
        other: ancestor,
        why:
          "“#{place.canonical_name}” (#{place.type}) sits inside “#{ancestor.canonical_name}” " <>
            "(#{ancestor.type}) and carries the same name. A place cannot be inside itself."
      }
    end
  end

  # Any two Places of one Event whose names nearly match once the type word is gone.
  # Deliberately NOT restricted to siblings: "Mc Donalds de Caraballeda" and
  # "McDonald's de Caraballeda" ended up under different parents precisely BECAUSE
  # the tree held Caraballeda twice, and a rule that only looked sideways would miss
  # every duplicate the older defect created.
  defp near_names(places, by_id) do
    ordered = Enum.sort_by(places, &{&1.inserted_at, &1.id})

    for {elder, i} <- Enum.with_index(ordered),
        younger <- Enum.drop(ordered, i + 1),
        # A building named after the area it stands in — "Residencias Los Corales"
        # inside "Los Corales" — reduces to its ancestor's name and is NOT a
        # duplicate. Between a Place and its own ancestor, only the exact-name rule
        # above applies.
        not related?(elder, younger, by_id),
        not different_kind?(elder, younger),
        Marks.marks(elder.canonical_name) == Marks.marks(younger.canonical_name),
        score = closeness(elder.canonical_name, younger.canonical_name),
        score >= @jaro_threshold do
      %{
        certainty: :candidate,
        score: score,
        place: younger,
        other: elder,
        why:
          "“#{younger.canonical_name}” (#{under(younger, by_id)}) and " <>
            "“#{elder.canonical_name}” (#{under(elder, by_id)}) read almost the same " <>
            "(#{Float.round(score, 2)}). One may be a second spelling of the other."
      }
    end
  end

  # A road, an area and a structure are three kinds of thing. Two of them are never
  # one node — the street named after the place is not the place.
  defp different_kind?(one, other) do
    with kind when not is_nil(kind) <- kind_of(one.type),
         other_kind when not is_nil(other_kind) <- kind_of(other.type) do
      kind != other_kind
    else
      _unclassified_type -> false
    end
  end

  defp kind_of(type), do: Map.get(@kinds_of_thing, Normalize.fold(type))

  defp related?(one, other, by_id) do
    one.id in Enum.map(ancestors(other, by_id), & &1.id) or
      other.id in Enum.map(ancestors(one, by_id), & &1.id)
  end

  defp under(place, by_id) do
    case place.parent_id && Map.get(by_id, place.parent_id) do
      nil -> "a root"
      parent -> "under #{parent.canonical_name}"
    end
  end

  # How close two names read, judged twice: as written, and with the spaces taken
  # out. "Mc Donalds de Caraballeda" and "McDonald's de Caraballeda" score only 0.91
  # word-for-word — one inserted space is enough to fall under the bar — and 1.0 once
  # the spaces go. Where a word is split is a matter of spelling, not of naming, so
  # the better of the two readings is the honest one. Loosening the threshold instead
  # would have admitted every distant pair as well.
  defp closeness(one, other) do
    spaced = String.jaro_distance(Marks.reduce(one), Marks.reduce(other))
    packed = String.jaro_distance(unspace(Marks.reduce(one)), unspace(Marks.reduce(other)))

    max(spaced, packed)
  end

  defp unspace(reduced), do: String.replace(reduced, " ", "")

  # Read as the number it is, so "Torre II" and "Torre 2" carry the same mark and a
  # building is not held twice for writing its number the other way.
  defp fold(name), do: Normalize.fold(name)

  defp ancestors(place, by_id) do
    Stream.unfold(place.parent_id, fn
      nil -> nil
      id -> with %{} = parent <- Map.get(by_id, id), do: {parent, parent.parent_id}
    end)
    |> Enum.to_list()
  end
end
