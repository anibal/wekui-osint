defmodule Wekui.Acquisition.Decomposition do
  @moduledoc """
  The calculation half of working a Search out into Queries: cutting the window
  into slices, and building the specs for one Place.

  Nothing here touches the database. Given the same Search it always produces
  the same specs, character for character, which is what makes a draft plan
  disposable — throw it away, work it out again, get the same plan back.

  A spec is one would-be Query plus the record of what it carried:

      %{place_id, query_text, slice_start, slice_end, place_name_ids, search_term_ids}
  """

  alias Wekui.Acquisition.QueryText

  @doc """
  Cuts `[window_start, window_end)` into whole slices of `slice_seconds`. The
  last one reaches past the window end when the window is not a whole number of
  slices long.

  Whole slices, rather than a short final one, are what make extending safe.
  The grid is anchored at `window_start` and never moves, so pushing the window
  end out only ever *appends* slices — a slice that was last never turns into a
  different, longer slice, and two Queries can never end up asking about
  overlapping stretches of time.

  An open window (no `window_end`) is cut up to `now`, truncated to the grid:
  only slices that have finished filling up, because asking about the one still
  in progress would freeze an incomplete answer.
  """
  @spec tile(DateTime.t(), DateTime.t() | nil, pos_integer(), DateTime.t()) ::
          [{DateTime.t(), DateTime.t()}]
  def tile(window_start, window_end, slice_seconds, now)

  def tile(%DateTime{} = start, nil, slice_seconds, %DateTime{} = now)
      when is_integer(slice_seconds) and slice_seconds > 0 do
    whole_slices(start, slice_seconds, div(DateTime.diff(now, start, :second), slice_seconds))
  end

  def tile(%DateTime{} = start, %DateTime{} = window_end, slice_seconds, _now)
      when is_integer(slice_seconds) and slice_seconds > 0 do
    span = DateTime.diff(window_end, start, :second)

    if span <= 0 do
      []
    else
      whole_slices(start, slice_seconds, ceil_div(span, slice_seconds))
    end
  end

  defp ceil_div(span, slice_seconds), do: div(span + slice_seconds - 1, slice_seconds)

  @doc """
  Every spec for one Place: its raw names batched into one group (split across
  several when the names plus the terms would not fit), plus one group per
  anchored name carrying its ancestors' names as qualifiers. Recognition-only
  names are never emitted. Each group is crossed with every slice.

  `place` must have `place_names` loaded, and so must each ancestor. `ancestors`
  come nearest-first. `terms` are the Search's Search Terms.
  """
  @spec place_specs(
          struct(),
          [struct()],
          [struct()],
          [{DateTime.t(), DateTime.t()}],
          atom(),
          pos_integer()
        ) ::
          [map()]
  def place_specs(place, ancestors, terms, slices, mode, cap) do
    term_groups = token_groups(terms, & &1.term)
    term_tokens = Enum.map(term_groups, &elem(&1, 0))
    term_ids = Enum.flat_map(term_groups, fn {_token, rows} -> Enum.map(rows, & &1.id) end)

    groups =
      raw_groups(place.place_names, term_tokens, cap) ++
        anchored_groups(place.place_names, ancestors)

    for {location, name_rows} <- groups, {slice_start, slice_end} <- slices do
      %{
        place_id: place.id,
        query_text:
          QueryText.render(%{
            location: location,
            terms: term_tokens,
            since: slice_start,
            until: slice_end,
            mode: mode
          }),
        slice_start: slice_start,
        slice_end: slice_end,
        place_name_ids: Enum.map(name_rows, & &1.id),
        search_term_ids: term_ids
      }
    end
  end

  @doc """
  Groups rows by the string they emit, sorted by that string, rows sorted by id
  within each group. Two rows carrying the same string would emit as one, so
  they share a group — but both are kept, because both need crediting for
  whatever the Query brings back.
  """
  @spec token_groups([struct()], (struct() -> String.t())) :: [{String.t(), [struct()]}]
  def token_groups(rows, string_fun) do
    rows
    |> Enum.group_by(string_fun)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {token, grouped} -> {token, Enum.sort_by(grouped, & &1.id)} end)
  end

  # Raw names batch into one group. When the names plus the term group would
  # exceed the cap, the names split across several groups — the terms ride
  # whole in every one, since dropping a term would change the question.
  # Cost: a group of n members spends 2n-1 (n words plus n-1 ORs); the two
  # slice bounds spend 2.
  defp raw_groups(names, term_tokens, cap) do
    case names |> Enum.filter(&(&1.emission == :raw)) |> token_groups(& &1.name) do
      [] ->
        []

      groups ->
        base = group_cost(term_tokens) + 2
        max_names = max(div(cap - base + 1, 2), 1)

        groups
        |> Enum.chunk_every(max_names)
        |> Enum.map(fn chunk ->
          {{:raw, Enum.map(chunk, &elem(&1, 0))},
           Enum.flat_map(chunk, fn {_token, rows} -> rows end)}
        end)
    end
  end

  # Each anchored name becomes its OWN group, sitting next to the group of its
  # ancestors' raw names. With no qualifiers there is nothing to anchor against,
  # so the name emits nothing at all rather than emitting bare.
  defp anchored_groups(names, ancestors) do
    case names |> Enum.filter(&(&1.emission == :anchored)) |> token_groups(& &1.name) do
      [] ->
        []

      anchored ->
        case chain_qualifiers(ancestors) do
          [] -> []
          qualifiers -> Enum.map(anchored, fn {t, rows} -> {{:anchored, t, qualifiers}, rows} end)
        end
    end
  end

  # Country names never qualify: "X (… OR Venezuela)" matches any post that
  # pairs a common name with the country, which is almost all of them. State,
  # municipality and parish anchors do work, and carry their names' precision.
  defp chain_qualifiers(ancestors) do
    ancestors
    |> Enum.reject(&(&1.type == "pais"))
    |> Enum.flat_map(fn ancestor ->
      ancestor.place_names
      |> Enum.filter(&(&1.emission == :raw))
      |> Enum.map(& &1.name)
      |> Enum.sort()
    end)
    |> Enum.uniq()
  end

  defp group_cost([]), do: 0
  defp group_cost(tokens), do: 2 * length(tokens) - 1

  defp whole_slices(_start, _slice_seconds, n) when n <= 0, do: []

  defp whole_slices(start, slice_seconds, n) do
    for i <- 0..(n - 1) do
      {DateTime.add(start, i * slice_seconds, :second),
       DateTime.add(start, (i + 1) * slice_seconds, :second)}
    end
  end
end
