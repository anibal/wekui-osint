defmodule Wekui.Narrative.ThemeResolver do
  @moduledoc """
  Files the extractor's own words for a happening under a [[theme]] the Event's
  vocabulary actually holds — the same job `Wekui.Narrative.PlaceResolver` does for a
  `place_mention`, on the other axis.

  The extractor writes `kind` freely: *"colapso"*, *"colapso de edificio"*, *"colapso
  total"*. That freedom is exactly what let it invent — an open field makes *"this does
  not fit"* inexpressible, so the model names what it saw with the nearest word it has
  and nothing can refuse the result. The vocabulary is the refusal, and this is where a
  free string meets it.

  **A safety net, not a substitute for extraction.** The theme belongs in the
  extraction itself, chosen from the ratified list against each theme's rule. This
  files only the UNAMBIGUOUS — a kind that answers every content word of a theme's
  name — and refuses everything else.

  It refuses a great deal, on purpose. Measured on the record, an earlier and more
  eager version filed 29 claims of kind "búsqueda" under **Búsqueda sin señales de
  vida** (the search ended with no survivors found) and 5 rescued people under
  **Rescate de animal**. It asserted worse things than the claims it was filing. **A
  claim left unfiled is silent and honest; a claim filed wrongly says something nobody
  wrote**, so the bar is set where false negatives are the only failure it can have.

  A `kind` that reaches no active happening theme returns `:no_theme` and the claim is
  written without one — on the record, and reaching no reader. The LLM pass that would
  name a theme for a cluster of those, and the residue accounting that would surface
  them, are further rungs and are not this module (`docs/mechanisms.md`).
  """

  alias Wekui.Gazetteer.Marks
  alias Wekui.Normalize
  alias Wekui.Taxonomy

  # Every content word of the theme must be answered. Deliberately high: a false
  # negative is silence, a false positive is a sentence nobody wrote.
  @threshold 0.9

  # Only true function words. `persona`, `edificio` and the like were here once and
  # they are exactly what tells two themes apart — stripping them is what let a person
  # be filed under `Rescate de animal`.
  @noise ~w(de del la el los las un una unos unas y e o en a al por con sobre para su sus)

  @doc """
  The active happening theme that `kind` belongs under, or `:no_theme`.

  Returns `{:ok, theme}` / `:no_theme`. Only `:active` themes of nature `:happening`
  are considered — a topic is something a post is about, and no claim follows from it.
  """
  def resolve(event_id, kind) when is_binary(kind) do
    case candidates(event_id) do
      [] -> :no_theme
      themes -> best(themes, reduce(kind))
    end
  end

  def resolve(_event_id, _not_a_string), do: :no_theme

  defp candidates(event_id) do
    event_id
    |> Taxonomy.list_active_themes!()
    |> Enum.filter(&(&1.nature == :happening))
    |> Enum.map(&{&1, reduce(&1.name)})
  end

  defp best(themes, wanted) when wanted != [] do
    scored =
      themes
      |> Enum.map(fn {theme, words} -> {theme, score(words, wanted)} end)
      |> Enum.reject(fn {_theme, score} -> score < @threshold end)

    case scored do
      [] -> :no_theme
      found -> {:ok, found |> Enum.max_by(&elem(&1, 1)) |> elem(0)}
    end
  end

  defp best(_themes, _empty), do: :no_theme

  # WHAT THIS REFUSED TO DO, AND WHY.
  #
  # The first version scored on the LEADING WORD, transplanted from
  # `Wekui.Narrative.Duplicates` where it was measured and works. Run against the
  # record it filed 29 claims of kind "búsqueda" under **Búsqueda sin señales de
  # vida** — the search ended with no survivors found — and 5 people rescued under
  # **Rescate de animal**. It asserted worse things than the claims it was filing.
  #
  # The rule did not travel because the problems are not the same one. Comparing two
  # extractor outputs, a shared leading word means a shared happening. Comparing free
  # text to a CURATED name, the rest of the name is the whole point: `animal` is what
  # distinguishes that theme, and `sin señales de vida` is what makes that one grim.
  #
  # So the bar is RECALL over the theme's own words: every content word of the theme
  # must be answered by something in the kind. "rescate" does not answer `animal`, so
  # it is refused. "colapso" does not answer `estructural`, so that is refused too —
  # and that is the right trade. A claim left unfiled is silent and honest; a claim
  # filed wrongly says something nobody wrote.
  #
  # Which means most pre-vocabulary kinds file under nothing, and they should: the
  # theme belongs in the EXTRACTION, chosen from the ratified list against its rule.
  # This is a safety net for the unambiguous, not a substitute for that.
  defp score(theme_words, wanted) do
    theme_words
    |> Enum.map(fn word ->
      wanted |> Enum.map(&String.jaro_distance(&1, word)) |> Enum.max()
    end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  defp reduce(text) do
    text
    |> Normalize.fold()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.map(&Marks.roman/1)
    |> Enum.reject(&(&1 in @noise))
  end
end
