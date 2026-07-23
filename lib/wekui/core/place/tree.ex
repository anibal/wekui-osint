defmodule Wekui.Core.Place.Tree do
  @moduledoc """
  Recursive walks over the `places` adjacency list, as SQLite recursive CTEs —
  one round trip each, whatever the depth.

  These back `Wekui.Core.Place`'s `:ancestors` and `:subtree` read actions;
  they return ids only, and the read action turns them into records so that
  filters, sorts and loads keep working normally.
  """

  import Ecto.Query

  alias Wekui.Core.Place
  alias Wekui.Repo

  @doc """
  The place's ancestor ids, nearest-first (parent, …, root), excluding the
  place itself. This is the walk anchored emission composes qualifiers from.
  """
  @spec ancestor_ids(Ash.UUID.t()) :: [Ash.UUID.t()]
  def ancestor_ids(place_id) do
    ancestors =
      union_all(
        from(p in Place,
          where: p.id == ^place_id,
          select: %{id: p.id, parent_id: p.parent_id, depth: type(^0, :integer)}
        ),
        ^from(p in Place,
          join: t in "ancestors",
          on: p.id == t.parent_id,
          select: %{id: p.id, parent_id: p.parent_id, depth: fragment("? + 1", t.depth)}
        )
      )

    from(p in Place,
      join: t in "ancestors",
      on: p.id == t.id,
      where: p.id != ^place_id,
      order_by: [asc: t.depth],
      select: p.id
    )
    |> recursive_ctes(true)
    |> with_cte("ancestors", as: ^ancestors)
    |> Repo.all()
  end

  @doc """
  The place's id plus every descendant's. One check catches both the
  self-parent and the true-cycle case when reparenting.
  """
  @spec subtree_ids(Ash.UUID.t()) :: [Ash.UUID.t()]
  def subtree_ids(place_id) do
    subtree =
      union_all(
        from(p in Place, where: p.id == ^place_id, select: %{id: p.id}),
        ^from(c in Place,
          join: t in "subtree",
          on: c.parent_id == t.id,
          select: %{id: c.id}
        )
      )

    from(p in Place, join: t in "subtree", on: p.id == t.id, select: p.id)
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^subtree)
    |> Repo.all()
  end

  @doc """
  Reorders `places` to match `ids` — the CTE knows the order, the read that
  fetches the records does not.
  """
  @spec order_by_ids([Place.t()], [Ash.UUID.t()]) :: [Place.t()]
  def order_by_ids(places, ids) do
    by_id = Map.new(places, &{&1.id, &1})

    Enum.flat_map(ids, fn id -> by_id |> Map.get(id) |> List.wrap() end)
  end
end
