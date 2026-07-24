defmodule Wekui.Judgment.Slot do
  @moduledoc """
  The "current row in a slot" query, shared by the judgment mechanism. A judgment
  is *current* while its `superseded_at` is nil; a slot is the set of fields that
  identify one answerable question — a Post, or a Post and a Theme. Every place
  that finds the current answer builds the same filter (superseding it, retracting
  its counterpart, reading it back, replacing a whole set), so it lives here once.
  """

  require Ash.Query
  import Ash.Expr

  @doc "A query for the current (open) rows of `resource` matching each `{field, value}` pair."
  def current(resource, pairs) do
    filter =
      Enum.reduce(pairs, expr(is_nil(superseded_at)), fn {field, value}, acc ->
        expr(^acc and ^ref(field) == ^value)
      end)

    Ash.Query.filter(resource, ^filter)
  end

  @doc "Whether `list` is a non-empty list of atoms — the shape of a slot or match spec."
  def nonempty_atom_list?(list), do: is_list(list) and list != [] and Enum.all?(list, &is_atom/1)
end
