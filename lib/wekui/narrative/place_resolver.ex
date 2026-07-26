defmodule Wekui.Narrative.PlaceResolver do
  @moduledoc """
  Turns a [[claim]]'s `place_mention` — the place(s) as the posts named them — into
  `ClaimPlace` links against the event's ACTIVE gazetteer
  (`docs/place-mapping-scenarios.md`). Deterministic and gazetteer-first: it uses what
  the record already knows (the text) before spending on anything external.

  The steps, most-specific-first:

    * parse the mention into one or more named places, each with its coarser ancestors
      ("edificio OPP 25, Tanaguarena, Caraballeda" → `OPP 25` under `[Tanaguarena,
      Caraballeda]`; a sibling list "Caribe y Los Corales" → two places sharing their
      ancestors — a claim can be about several places at once);
    * match each named place to a gazetteer name, exact (folded) then fuzzy, using the
      ancestors to disambiguate a generic name that matches more than one place;
    * when the finest named place is NOT in the tree but a coarser ancestor IS, propose
      the finer under that ancestor — born `:proposed`, the human-promotes queue — and
      link the claim to it (scenario B);
    * a name that matches nothing at any level is left UNRESOLVED. The web lookup that
      would place it (Tavily/Nominatim) is a separate, not-yet-built step — this module
      never searches, and never guesses a tree position.

  Only `:active` places are matched or widen anything, so a proposal the resolver makes
  cannot, on its own, explain away a private name in the F54 gate — the same posture as
  `Wekui.Narrative.PrivateNames`.
  """

  alias Wekui.Core.Place
  alias Wekui.Core.PlaceName
  alias Wekui.Narrative
  alias Wekui.Normalize
  alias Wekui.Tree

  require Ash.Query

  # Leading words that name the KIND of a place, stripped from a mention segment so
  # "edificio OPP 25" matches the gazetteer name "OPP 25", and kept as the `type` when a
  # new place is proposed.
  @type_words ~w(
    edificio edif residencia residencias res resd conjunto torre torres bloque
    urbanizacion urb sector barrio parroquia municipio estado ciudad pais
    avenida av calle carrera zona quinta complejo residencial club hotel
  )

  # A fuzzy match must be this close (Jaro) to count, so "Residencias Caribe" reaches
  # "Residencia Caribe" but two different buildings never collide.
  @jaro_threshold 0.92

  @doc """
  Resolves `claim`'s `place_mention` into ClaimPlace links. `opts`: `:actor_id` and
  `:post_id`, the provenance stamped on any Place the resolver proposes. Returns
  `{:ok, summary}` where summary counts linked / proposed / unresolved.
  """
  def resolve(claim, opts \\ []) do
    index = gazetteer_index(claim.event_id)

    results =
      claim.place_mention
      |> parse()
      |> Enum.map(&resolve_one(&1, claim, index, opts))

    {:ok, summarize(results)}
  end

  ## ─────────────────────────── parsing ───────────────────────────

  @doc """
  Parses a `place_mention` into a list of `%{original, raw_name, type, forms, ancestors}`
  — the finest named place(s), each with its coarser ancestor names (folded,
  nearest-first). Comma-separates the hierarchy, splits a Spanish `y`/`e` list in the
  finest segment into siblings. `nil`/blank → `[]`.
  """
  def parse(nil), do: []

  def parse(mention) when is_binary(mention) do
    case mention |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] ->
        []

      [finest | ancestors_raw] ->
        ancestors =
          ancestors_raw
          |> Enum.map(&Normalize.fold(strip_type(&1)))
          |> Enum.reject(&(&1 == ""))

        finest
        |> split_siblings()
        |> Enum.map(&build_mention(&1, ancestors))
        |> Enum.reject(&(&1.forms == []))
    end
  end

  # A named-place segment matched two ways: the FULL text ("residencias caribe", when
  # the gazetteer keeps the type word as part of the name) and the type-STRIPPED text
  # ("opp 25", when it does not). `original` is kept verbatim for the report; `raw_name`
  # (stripped) is what names a place we may propose.
  defp build_mention(segment, ancestors) do
    {type, stripped} = strip_type_typed(segment)

    forms =
      [Normalize.fold(segment), Normalize.fold(stripped)]
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))

    %{original: segment, raw_name: stripped, type: type, forms: forms, ancestors: ancestors}
  end

  # A Spanish `y`/`e` in the finest segment joins sibling places ("Caribe y Los
  # Corales"). Compound-prefix lists that a comma also breaks ("OPP 22, 24 y 25") are
  # NOT handled here — that needs an LLM parse and is deferred with the search step.
  defp split_siblings(segment) do
    segment
    |> String.split(~r/\s+[ye]\s+/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp strip_type_typed(segment) do
    case String.split(segment) do
      [first | rest] when rest != [] ->
        if Normalize.fold(first) in @type_words,
          do: {Normalize.fold(first), Enum.join(rest, " ")},
          else: {nil, segment}

      _one_or_none ->
        {nil, segment}
    end
  end

  defp strip_type(segment), do: elem(strip_type_typed(segment), 1)

  ## ─────────────────────────── resolution ───────────────────────────

  defp resolve_one(mention, claim, index, opts) do
    case match(mention, index) do
      {:ok, place_id, how, confidence} ->
        link(claim, place_id, how, confidence)
        {:linked, how, mention.original}

      :no_match ->
        case match_ancestor(mention, index) do
          {:ok, ancestor_id} ->
            place_id = find_or_propose(mention, ancestor_id, claim, opts)
            link(claim, place_id, :mention_ancestor, 0.5)
            {:proposed, mention.original}

          :no_match ->
            {:unresolved, mention.original}
        end
    end
  end

  # Exact (folded) match first, then fuzzy; disambiguate a multi-place name by ancestors.
  # Each mention is tried as both its full and its type-stripped form.
  defp match(mention, index) do
    case exact(mention, index) do
      [] -> fuzzy(mention, index)
      candidates -> disambiguate(candidates, mention, index, :mention_exact)
    end
  end

  # Forms are tried most-specific-first (full text before type-stripped), so
  # "Residencias Caribe" reaches the building before the bare "Caribe" barrio.
  defp exact(mention, index) do
    Enum.find_value(mention.forms, [], &Map.get(index.by_name, &1))
  end

  defp fuzzy(mention, index) do
    Enum.find_value(mention.forms, :no_match, fn form ->
      case fuzzy_form(form, index) do
        [] -> nil
        candidates -> disambiguate(candidates, mention, index, :mention_fuzzy)
      end
    end)
  end

  defp fuzzy_form(form, index) do
    index.by_name
    |> Enum.filter(fn {folded, _pids} ->
      String.jaro_distance(folded, form) >= @jaro_threshold
    end)
    |> Enum.flat_map(fn {_folded, pids} -> pids end)
    |> Enum.uniq()
  end

  # One candidate wins outright; several are decided by how many of the mention's
  # ancestors appear in the candidate's ancestor chain. A tie the ancestors cannot
  # break keeps the first candidate at a low confidence — a review flag, not a guess.
  defp disambiguate([place_id], _mention, _index, how),
    do: {:ok, place_id, how, confidence(how, :sole)}

  defp disambiguate(candidates, mention, index, how) do
    scored = Enum.map(candidates, fn pid -> {pid, ancestor_overlap(pid, mention, index)} end)
    best = Enum.max_by(scored, &elem(&1, 1))

    case best do
      {pid, overlap} when overlap > 0 -> {:ok, pid, how, confidence(how, :anchored)}
      {pid, 0} -> {:ok, pid, how, confidence(how, :ambiguous)}
    end
  end

  defp ancestor_overlap(place_id, mention, index) do
    chain =
      Place
      |> Tree.ancestor_ids(place_id)
      |> Enum.map(&index.places[&1])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Normalize.fold(&1.canonical_name))
      |> MapSet.new()

    Enum.count(mention.ancestors, &MapSet.member?(chain, &1))
  end

  # The nearest named ancestor that exists in the tree, for the propose-the-finer path.
  defp match_ancestor(mention, index) do
    Enum.find_value(mention.ancestors, :no_match, fn ancestor ->
      case Map.get(index.by_name, ancestor) do
        nil -> nil
        [place_id | _] -> {:ok, place_id}
      end
    end)
  end

  defp confidence(:mention_exact, :sole), do: 0.9
  defp confidence(:mention_exact, :anchored), do: 0.85
  defp confidence(:mention_exact, :ambiguous), do: 0.5
  defp confidence(:mention_fuzzy, :sole), do: 0.65
  defp confidence(:mention_fuzzy, :anchored), do: 0.6
  defp confidence(:mention_fuzzy, :ambiguous), do: 0.4

  ## ─────────────────────────── writes ───────────────────────────

  defp link(claim, place_id, how, confidence) do
    Narrative.link_place!(%{
      claim_id: claim.id,
      place_id: place_id,
      how_resolved: how,
      confidence: confidence
    })
  end

  # Reuse a place (any lifecycle) already sitting under this parent with this name —
  # so two claims naming the same not-yet-in-tree building share one proposal instead
  # of minting a duplicate — otherwise propose it, born :proposed, with its provenance.
  defp find_or_propose(mention, parent_id, claim, opts) do
    target = Normalize.fold(mention.raw_name)

    existing =
      Place
      |> Ash.Query.filter(event_id == ^claim.event_id and parent_id == ^parent_id)
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(Normalize.fold(&1.canonical_name) == target))

    case existing do
      nil -> propose(mention, parent_id, claim, opts)
      place -> place.id
    end
  end

  defp propose(mention, parent_id, claim, opts) do
    place =
      Place
      |> Ash.Changeset.for_create(:create, %{
        type: mention.type || "lugar",
        canonical_name: mention.raw_name,
        event_id: claim.event_id,
        parent_id: parent_id,
        proposed_by_actor_id: Keyword.get(opts, :actor_id),
        proposed_from_post_id: Keyword.get(opts, :post_id)
      })
      |> Ash.create!(authorize?: false)

    place.id
  end

  ## ─────────────────────────── gazetteer ───────────────────────────

  # The event's active gazetteer as an input-side index: folded name → place_ids, plus
  # the places themselves for the ancestor walk. Only :active places — a :proposed one
  # is a candidate, not yet a place a mention may resolve to.
  defp gazetteer_index(event_id) do
    places =
      Place
      |> Ash.Query.filter(event_id == ^event_id and lifecycle == :active)
      |> Ash.read!(authorize?: false)

    names =
      PlaceName
      |> Ash.Query.filter(place.event_id == ^event_id and place.lifecycle == :active)
      |> Ash.read!(authorize?: false)

    by_name =
      (Enum.map(places, &{Normalize.fold(&1.canonical_name), &1.id}) ++
         Enum.map(names, &{&1.normalized, &1.place_id}))
      |> Enum.reduce(%{}, fn {folded, pid}, acc ->
        Map.update(acc, folded, [pid], &Enum.uniq([pid | &1]))
      end)

    %{places: Map.new(places, &{&1.id, &1}), by_name: by_name}
  end

  defp summarize(results) do
    %{
      mentions: length(results),
      linked: Enum.count(results, &match?({:linked, _how, _name}, &1)),
      proposed: Enum.count(results, &match?({:proposed, _name}, &1)),
      unresolved: for({:unresolved, name} <- results, do: name)
    }
  end
end
