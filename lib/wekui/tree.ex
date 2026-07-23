defmodule Wekui.Tree do
  @moduledoc """
  Recursive walks over an adjacency list (`parent_id`), as SQLite recursive
  CTEs — one round trip each, whatever the depth.

  The resource is any Ash resource whose rows form a tree through `parent_id`:
  `Wekui.Core.Place` and `Wekui.Taxonomy.Theme` both descend here. These back
  the `:ancestors` and `:subtree` read actions and the `:outside_subtree?`
  check in `Wekui.Validations.Reference`; they return ids only, and the read
  action turns them into records so that filters, sorts and loads keep working
  normally.
  """

  import Ecto.Query

  alias Wekui.Repo

  @doc """
  A node's ancestor ids, nearest-first (parent, …, root), excluding the node
  itself. This is the walk anchored emission composes qualifiers from.
  """
  @spec ancestor_ids(module(), Ash.UUID.t()) :: [Ash.UUID.t()]
  def ancestor_ids(resource, id) do
    initial =
      resource
      |> where([n], n.id == ^id)
      |> select([n], %{id: n.id, parent_id: n.parent_id, depth: type(^0, :integer)})

    recursion =
      resource
      |> join(:inner, [n], t in "ancestors", on: n.id == t.parent_id)
      |> select([n, t], %{id: n.id, parent_id: n.parent_id, depth: fragment("? + 1", t.depth)})

    ancestors = union_all(initial, ^recursion)

    resource
    |> join(:inner, [n], t in "ancestors", on: n.id == t.id)
    |> where([n], n.id != ^id)
    |> order_by([_n, t], asc: t.depth)
    |> select([n], n.id)
    |> recursive_ctes(true)
    |> with_cte("ancestors", as: ^ancestors)
    |> Repo.all()
  end

  @doc """
  A node's id plus every descendant's. One check catches both the self-parent
  and the true-cycle case when reparenting.
  """
  @spec subtree_ids(module(), Ash.UUID.t()) :: [Ash.UUID.t()]
  def subtree_ids(resource, id) do
    initial =
      resource
      |> where([n], n.id == ^id)
      |> select([n], %{id: n.id})

    recursion =
      resource
      |> join(:inner, [c], t in "subtree", on: c.parent_id == t.id)
      |> select([c], %{id: c.id})

    subtree = union_all(initial, ^recursion)

    resource
    |> join(:inner, [n], t in "subtree", on: n.id == t.id)
    |> select([n], n.id)
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^subtree)
    |> Repo.all()
  end

  @doc """
  Reorders `records` to match `ids` — the CTE knows the order, the read that
  fetches the records does not.
  """
  @spec order_by_ids([struct()], [Ash.UUID.t()]) :: [struct()]
  def order_by_ids(records, ids) do
    by_id = Map.new(records, &{&1.id, &1})

    Enum.flat_map(ids, fn id -> by_id |> Map.get(id) |> List.wrap() end)
  end
end
