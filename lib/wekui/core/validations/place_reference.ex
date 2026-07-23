defmodule Wekui.Core.Validations.PlaceReference do
  @moduledoc """
  Checks the Place or Places that an attribute or argument points at.

  Things point at Places from several directions — a Place's `parent_id` and
  `replaced_by_id`, a Search's Scope — and they all carry the same first rule,
  so they share one validation.

  The referenced Places must always belong to the same Event: an Event's
  context is never shared, so a pointer into another Event's gazetteer is not a
  smaller mistake than a missing Place — it is the same one.

  Options — `:attribute` or `:argument` names where the id or ids live, then:

    * `:lifecycle` — the referenced Place must be in this lifecycle.
    * `:not_self?` — the referenced Place must not be the Place itself.
    * `:outside_subtree?` — the referenced Place must be neither the Place
      itself nor one of its descendants. Reparenting onto your own descendant
      would make you your own ancestor and detach the subtree from the tree.

  A nil or empty reference passes: absence is the tree's root and the Scope
  that means "everything", and `allow_nil?` is the right place to forbid it
  where it must not be absent.
  """

  use Ash.Resource.Validation

  alias Wekui.Core.Place
  alias Wekui.Core.Place.Tree

  require Ash.Query

  @impl true
  def init(opts) do
    case {opts[:attribute], opts[:argument]} do
      {attribute, nil} when is_atom(attribute) and not is_nil(attribute) -> {:ok, opts}
      {nil, argument} when is_atom(argument) and not is_nil(argument) -> {:ok, opts}
      _both_or_neither -> {:error, "expects exactly one of :attribute or :argument"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    {field, ids} = reference(changeset, opts)

    case ids do
      [] -> :ok
      ids -> check(changeset, ids, field, opts)
    end
  end

  defp reference(changeset, opts) do
    case opts[:attribute] do
      nil -> {opts[:argument], wrap(Ash.Changeset.get_argument(changeset, opts[:argument]))}
      attribute -> {attribute, wrap(Ash.Changeset.get_attribute(changeset, attribute))}
    end
  end

  defp wrap(nil), do: []
  defp wrap(ids) when is_list(ids), do: ids
  defp wrap(id), do: [id]

  # One read however many ids there are, then every rule in memory.
  defp check(changeset, ids, field, opts) do
    with {:ok, places} <- Ash.read(Ash.Query.filter(Place, id in ^ids), authorize?: false) do
      event_id = Ash.Changeset.get_attribute(changeset, :event_id)

      cond do
        length(places) < length(Enum.uniq(ids)) ->
          error(field, "does not exist")

        Enum.any?(places, &(&1.event_id != event_id)) ->
          error(field, "must belong to the same event")

        opts[:not_self?] && Enum.any?(places, &(&1.id == changeset.data.id)) ->
          error(field, "cannot be the place itself")

        opts[:lifecycle] && Enum.any?(places, &(&1.lifecycle != opts[:lifecycle])) ->
          error(field, "must be #{opts[:lifecycle]}")

        opts[:outside_subtree?] && descends?(places, changeset.data.id) ->
          error(field, "would create a cycle: it is this place itself or one of its descendants")

        true ->
          :ok
      end
    end
  end

  defp descends?(places, place_id) do
    subtree = MapSet.new(Tree.subtree_ids(place_id))

    Enum.any?(places, &MapSet.member?(subtree, &1.id))
  end

  defp error(field, message), do: {:error, field: field, message: message}
end
