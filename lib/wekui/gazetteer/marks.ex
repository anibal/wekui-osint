defmodule Wekui.Gazetteer.Marks do
  @moduledoc """
  The tokens that exist to tell two places apart — and the one place they live.

  "Residencias Green 7" and "Residencias Green 8" read almost identically to any
  string measure, and they are two different buildings. The number is not noise in
  the name; **the number IS the name**, and so is a compass direction, and so is a
  Roman numeral. If two names' marks disagree, the names do not nearly match — they
  contradict, and no closeness score should be allowed to argue otherwise.

  This module exists because the rule was learned once and then only reached one
  consumer. The operator ruled on 2026-07-27 that *"the numeral names another
  building"* — `Residencias Caraballeda` is not `Residencia Caraballeda I`. That
  became a rule inside `Wekui.Gazetteer.Duplicates`, where it stopped duplicate
  candidates cold. It never reached `Wekui.Narrative.PlaceResolver`, which went on
  fuzzy-matching *"edificio Celta Mar II"* onto **Torre Celta Mar 1** and asking a
  person to confirm it.

  So a ruling that has to hold in two places is written in neither of them. Anything
  that compares two place names reads it here.
  """

  alias Wekui.Normalize

  # A direction is a mark: "El Palmar Este" is not "El Palmar Oeste".
  @directions ~w(norte sur este oeste nororiente noroccidente n s e o)

  # A Roman numeral does the same work as an Arabic one, anchored to a whole token so
  # it cannot catch a stray letter mid-name.
  @numeral ~r/^(i{1,3}|iv|vi{0,3}|ix|xi{0,3}|x)$/

  @romans %{
    "i" => "1",
    "ii" => "2",
    "iii" => "3",
    "iv" => "4",
    "v" => "5",
    "vi" => "6",
    "vii" => "7",
    "viii" => "8",
    "ix" => "9",
    "x" => "10",
    "xi" => "11",
    "xii" => "12",
    "xiii" => "13"
  }

  # A leading word that names the KIND of place rather than the place. Dropped before
  # comparing, so "Edificio Albatros" and "Residencias Albatros" are one name wearing
  # two labels — while "Albatros 2" stays a different building from "Albatros".
  @type_words ~w(
    edificio edif residencia residencias res resd conjunto torre torres bloque
    urbanizacion urb sector barrio parroquia municipio estado ciudad pais
    avenida av calle carrera zona quinta complejo residencial club hotel
  )

  @doc """
  The marks of a name, sorted: its numbers, its Roman numerals read as numbers, and
  its compass directions.

      iex> Wekui.Gazetteer.Marks.marks("Residencia Caraballeda I")
      ["1"]

      iex> Wekui.Gazetteer.Marks.marks("El Palmar Este")
      ["este"]

      iex> Wekui.Gazetteer.Marks.marks("Residencias Coral Bella")
      []
  """
  def marks(name) do
    name
    |> reduce()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.flat_map(fn token ->
      cond do
        token in @directions -> [token]
        Regex.match?(@numeral, token) -> [roman(token)]
        # A number anywhere in a token, "opp27" included — the digits are the mark.
        true -> Regex.scan(~r/\d+/, token) |> Enum.map(fn [digits] -> digits end)
      end
    end)
    |> Enum.sort()
  end

  @doc """
  Whether two names carry marks that **disagree** — the test that stops a closeness
  score from folding two different buildings together.

  Absent marks on one side do not contradict: "Albatros" against "Albatros 2" is a
  name and a finer name, not a contradiction, and that is a real reading the gazetteer
  has to allow. Only two names that BOTH carry marks, and carry different ones, are
  refused.

      iex> Wekui.Gazetteer.Marks.contradict?("Celta Mar II", "Celta Mar 1")
      true

      iex> Wekui.Gazetteer.Marks.contradict?("Albatros", "Albatros 2")
      false
  """
  def contradict?(one, other) do
    a = marks(one)
    b = marks(other)

    a != [] and b != [] and a != b
  end

  @doc """
  The name without its leading type word or its punctuation, with numerals read as
  numbers: "Avenida La Costanera" → "la costanera", "Torre II" → "2".

  `Wekui.Normalize` deliberately keeps punctuation, because "fuzzy tolerance belongs
  to the matching technique, never to the stored key". This IS the technique.
  """
  def reduce(name) do
    name
    |> Normalize.fold()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.split(" ", trim: true)
    |> case do
      [first | rest] when rest != [] -> if first in @type_words, do: rest, else: [first | rest]
      words -> words
    end
    |> Enum.map_join(" ", &roman/1)
  end

  @doc "A Roman numeral read as the number it is; anything else unchanged."
  def roman(token), do: Map.get(@romans, token, token)
end
