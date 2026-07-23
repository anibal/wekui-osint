defmodule Wekui.Acquisition.Plan do
  @moduledoc """
  Writing a Search's plan to the database.

  `Wekui.Acquisition.Decomposition` works out *what* the Queries should be;
  this module puts them there. It is deliberately the only place that writes
  Queries, so that "what the plan is" has exactly one author.

  `build/2` never rewrites an existing Query — it inserts only the ones the
  Search does not already ask. That single property is what makes `decompose`
  (wipe, then build) and extending (build, no wipe) the same engine.

  It runs inside one SQLite write transaction, so it reads the Event's tree
  once and walks ancestry in memory rather than asking the database per Place,
  and writes in bulk rather than row by row.
  """

  alias Wekui.Acquisition
  alias Wekui.Acquisition.Decomposition
  alias Wekui.Acquisition.Query
  alias Wekui.Acquisition.QueryName
  alias Wekui.Acquisition.QueryTerm
  alias Wekui.Core

  # X limits how many pieces one request may carry. Names are split across
  # several Queries rather than dropped when they would not all fit.
  @operator_cap 22

  @doc """
  Throws away a Search's whole plan: its Queries and both kinds of bridge.
  Only ever called for a draft, where Queries have never been asked.
  """
  @spec wipe(Ash.UUID.t()) :: :ok | {:error, term()}
  def wipe(search_id) do
    with {:ok, queries} <- Acquisition.list_queries(search_id, load: [:query_names, :query_terms]) do
      # Bridges first: a Query outlives nothing, but its bridges point at it.
      with :ok <- destroy(Enum.flat_map(queries, & &1.query_terms)),
           :ok <- destroy(Enum.flat_map(queries, & &1.query_names)) do
        destroy(queries)
      end
    end
  end

  @doc """
  Works the Search out into Queries and inserts the ones it does not already
  ask. Returns how many were added.
  """
  @spec build(struct(), DateTime.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def build(search, now) do
    with {:ok, places} <- scope(search),
         {:ok, ancestry} <- ancestry(search.event_id),
         {:ok, terms} <- Acquisition.list_search_terms(search.id, authorize?: false),
         {:ok, existing} <- existing_texts(search.id) do
      search
      |> specs(places, ancestry, terms, now)
      |> reject_known(existing)
      |> insert(search)
    end
  end

  defp specs(search, places, ancestry, terms, now) do
    slices =
      Decomposition.tile(search.window_start, search.window_end, search.slice_seconds, now)

    Enum.flat_map(places, fn place ->
      Decomposition.place_specs(
        place,
        ancestors(place, ancestry),
        terms,
        slices,
        search.result_mode,
        @operator_cap
      )
    end)
  end

  # Two Places of one Event can carry the same name, and would then ask the
  # identical question. The Search asks it once.
  defp reject_known(specs, existing) do
    specs
    |> Enum.uniq_by(& &1.query_text)
    |> Enum.reject(&MapSet.member?(existing, &1.query_text))
  end

  defp insert([], _search), do: {:ok, 0}

  defp insert(specs, search) do
    rows =
      Enum.map(specs, fn spec ->
        %{
          search_id: search.id,
          place_id: spec.place_id,
          query_text: spec.query_text,
          slice_start: spec.slice_start,
          slice_end: spec.slice_end
        }
      end)

    # `sorted?: true` returns the Queries in the order they were given, so each
    # one lines up with the spec that asked for it and can claim its bridges.
    with {:ok, queries} <- create(Query, rows, return_records?: true, sorted?: true),
         :ok <- create_bridges(QueryName, :place_name_id, specs, queries, & &1.place_name_ids),
         :ok <- create_bridges(QueryTerm, :search_term_id, specs, queries, & &1.search_term_ids) do
      {:ok, length(queries)}
    end
  end

  defp create_bridges(resource, key, specs, queries, ids_fun) do
    rows =
      specs
      |> Enum.zip(queries)
      |> Enum.flat_map(fn {spec, query} ->
        Enum.map(ids_fun.(spec), &%{:query_id => query.id, key => &1})
      end)

    with {:ok, _created} <- create(resource, rows, []), do: :ok
  end

  defp create(_resource, [], _opts), do: {:ok, []}

  defp create(resource, rows, opts) do
    rows
    |> Ash.bulk_create(
      resource,
      :create,
      Keyword.merge([authorize?: false, return_errors?: true, stop_on_error?: true], opts)
    )
    |> bulk_result()
  end

  defp destroy([]), do: :ok

  defp destroy(records) do
    records
    |> Ash.bulk_destroy(:destroy, %{},
      authorize?: false,
      return_errors?: true,
      stop_on_error?: true,
      strategy: [:stream]
    )
    |> bulk_result()
    |> case do
      {:ok, _records} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp bulk_result(%Ash.BulkResult{status: status, records: records}) when status != :error,
    do: {:ok, records || []}

  defp bulk_result(%Ash.BulkResult{errors: errors}), do: {:error, Enum.at(errors, 0)}

  # Naming Places explicitly says "collect on exactly these", and a proposed
  # Place may be named — collecting is often how we find out whether it was
  # real. An empty Scope says "collect on the Event's settled geography", which
  # is its active Places and nothing merely proposed.
  defp scope(search) do
    with {:ok, loaded} <- Ash.load(search, [:event, places: [:place_names]], authorize?: false),
         {:ok, places} <- candidates(loaded) do
      {:ok, Enum.reject(places, &(&1.id == loaded.event.unplaced_place_id))}
    end
  end

  defp candidates(%{places: []} = search) do
    Core.list_active_places(search.event_id, load: [:place_names], authorize?: false)
  end

  defp candidates(%{places: places}) do
    {:ok, Enum.filter(places, &(&1.lifecycle in [:proposed, :active]))}
  end

  # Every Place of the Event, by id, so an ancestor chain is a walk through a
  # map rather than a recursive query per Place. Sibling Places share a chain,
  # and a Place's ancestors always belong to its own Event.
  defp ancestry(event_id) do
    with {:ok, places} <- Core.list_places(event_id, load: [:place_names], authorize?: false) do
      {:ok, Map.new(places, &{&1.id, &1})}
    end
  end

  defp ancestors(place, ancestry), do: ancestors(place.parent_id, ancestry, [])

  defp ancestors(nil, _ancestry, acc), do: Enum.reverse(acc)

  defp ancestors(parent_id, ancestry, acc) do
    case Map.fetch(ancestry, parent_id) do
      {:ok, parent} -> ancestors(parent.parent_id, ancestry, [parent | acc])
      :error -> Enum.reverse(acc)
    end
  end

  defp existing_texts(search_id) do
    with {:ok, queries} <- Acquisition.list_queries(search_id, authorize?: false) do
      {:ok, MapSet.new(queries, & &1.query_text)}
    end
  end
end
