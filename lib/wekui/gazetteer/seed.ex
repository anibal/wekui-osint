defmodule Wekui.Gazetteer.Seed do
  @moduledoc """
  Seeds an [[event]]'s [[place]] tree from a committed, reconciled gazetteer data file
  (`priv/gazetteer/*.json`) — the reproducible half of the cross-checked seed.

  The data was reconciled ONCE from three sources (see the export step and
  `docs/place-mapping-scenarios.md`): the old app's operational Caraballeda subtree
  (the building-level tree, 202 edificios with their full parent chain), the
  purpose-built `gazetteer.db` admin skeleton (the trusted state→parish spine and the
  Vargas↔La Guaira rename), and a live Tavily check on the buildings. Each node carries
  its `cross_check` provenance (which sources agreed) so the reconciliation is auditable
  in git, not re-run at seed time.

  Seeding is top-down (a parent before its children) and idempotent: a node already in
  the event — matched on folded canonical name, type and parent — is reused, its surface
  names topped up rather than duplicated. Every node is born `:active`: these are curated
  places, already vetted in the source project, not machine guesses.
  """

  alias Wekui.Core
  alias Wekui.Normalize

  @kinds ~w(official colloquial alias acronym abbreviation spelling_variant historical error)a
  @emissions ~w(raw anchored recognition_only)a

  @doc """
  Seeds the Caraballeda gazetteer into `event_id`. `opts[:nodes]` overrides the data
  (for tests). Returns `%{created:, reused:, names:}`.
  """
  def caraballeda(event_id, opts \\ []) do
    nodes = opts[:nodes] || load("caraballeda.json")
    seed(event_id, nodes)
  end

  defp load(file) do
    :wekui
    |> :code.priv_dir()
    |> Path.join("gazetteer/#{file}")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("nodes")
  end

  defp seed(event_id, nodes) do
    by_old = Map.new(nodes, &{&1["old_id"], &1})
    ordered = Enum.sort_by(nodes, &depth(&1, by_old))

    # Existing places keyed for idempotent reuse — loaded once, grown as we create.
    lookup =
      event_id
      |> Core.list_places!()
      |> Map.new(&{{Normalize.fold(&1.canonical_name), &1.type, &1.parent_id}, &1})

    {_ids, _lookup, stats} =
      Enum.reduce(ordered, {%{}, lookup, %{created: 0, reused: 0, names: 0}}, fn node,
                                                                                 {ids, look, st} ->
        parent_id = parent_id(node, ids)
        key = {Normalize.fold(node["canonical"]), node["type"], parent_id}

        {place, look, st} =
          case Map.get(look, key) do
            nil ->
              p = create_place(event_id, node, parent_id)
              {p, Map.put(look, key, p), Map.update!(st, :created, &(&1 + 1))}

            p ->
              {p, look, Map.update!(st, :reused, &(&1 + 1))}
          end

        added = ensure_names(place, node["names"])
        {Map.put(ids, node["old_id"], place), look, Map.update!(st, :names, &(&1 + added))}
      end)

    stats
  end

  # Tree depth by walking parent_old_id inside the node set — so parents sort first.
  defp depth(node, by_old) do
    case node["parent_old_id"] && Map.get(by_old, node["parent_old_id"]) do
      nil -> 0
      parent -> 1 + depth(parent, by_old)
    end
  end

  defp parent_id(node, ids) do
    case node["parent_old_id"] && Map.get(ids, node["parent_old_id"]) do
      nil -> nil
      place -> place.id
    end
  end

  defp create_place(event_id, node, parent_id) do
    Core.create_place!(%{
      event_id: event_id,
      canonical_name: node["canonical"],
      type: node["type"],
      parent_id: parent_id,
      lifecycle: :active
    })
  end

  defp ensure_names(place, names) do
    held =
      place.id
      |> Core.list_place_names!()
      |> MapSet.new(&{&1.normalized, &1.kind, &1.emission})

    to_add =
      names
      |> Enum.map(fn n ->
        {n["name"], atom(@kinds, n["kind"], :alias),
         atom(@emissions, n["emission"], :recognition_only)}
      end)
      |> Enum.uniq_by(fn {name, kind, emission} -> {Normalize.fold(name), kind, emission} end)
      |> Enum.reject(fn {name, kind, emission} ->
        MapSet.member?(held, {Normalize.fold(name), kind, emission})
      end)

    Enum.each(to_add, fn {name, kind, emission} ->
      Core.create_place_name!(%{place_id: place.id, name: name, kind: kind, emission: emission})
    end)

    length(to_add)
  end

  defp atom(allowed, string, fallback) do
    Enum.find(allowed, fallback, &(Atom.to_string(&1) == string))
  end
end
