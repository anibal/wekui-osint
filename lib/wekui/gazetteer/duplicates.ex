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
  alias Wekui.Normalize

  # The leading words that name what KIND of place a name is. Shared in spirit with
  # `Wekui.Narrative.PlaceResolver` — that one strips them off a mention coming in,
  # this one strips them off the gazetteer's own names.
  @type_words ~w(
    edificio edif residencia residencias res resd conjunto torre torres bloque
    urbanizacion urb sector barrio parroquia municipio estado ciudad pais
    avenida av calle carrera zona quinta complejo residencial club hotel
  )

  # Two sibling names must be this close (Jaro) to be worth a person's attention.
  @jaro_threshold 0.92

  # Tokens that exist to tell two places apart. "Este" and "Oeste" differ by four
  # letters and by the entire point of the name.
  @directions ~w(norte sur este oeste nororiente noroccidente n s e o)

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
        marks(elder.canonical_name) == marks(younger.canonical_name),
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
    spaced = String.jaro_distance(reduce(one), reduce(other))
    packed = String.jaro_distance(unspace(reduce(one)), unspace(reduce(other)))

    max(spaced, packed)
  end

  defp unspace(reduced), do: String.replace(reduced, " ", "")

  # The tokens that exist to tell places apart: if they disagree, the names do not
  # nearly match — they contradict.
  defp marks(name) do
    name
    |> reduce()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.flat_map(fn token ->
      cond do
        token in @directions -> [token]
        # A number anywhere in a token, "opp27" included — the digits are the mark.
        true -> Regex.scan(~r/\d+/, token) |> Enum.map(fn [digits] -> digits end)
      end
    end)
    |> Enum.sort()
  end

  # The name without its leading type word or its punctuation: "Avenida La Costanera"
  # → "la costanera", "McDonald's de Caraballeda" → "mcdonalds de caraballeda".
  #
  # `Wekui.Normalize` deliberately keeps punctuation, because "fuzzy tolerance belongs
  # to the matching technique, never to the stored key". This IS the technique.
  defp reduce(name) do
    folded =
      name
      |> fold()
      |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    case String.split(folded, " ", trim: true) do
      [first | rest] when rest != [] ->
        if first in @type_words, do: Enum.join(rest, " "), else: folded

      _one_word_or_none ->
        folded
    end
  end

  defp fold(name), do: Normalize.fold(name)

  defp ancestors(place, by_id) do
    Stream.unfold(place.parent_id, fn
      nil -> nil
      id -> with %{} = parent <- Map.get(by_id, id), do: {parent, parent.parent_id}
    end)
    |> Enum.to_list()
  end
end
