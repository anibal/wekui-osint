defmodule Wekui.Validations.Reference do
  @moduledoc """
  Checks the record or records that an attribute or argument points at.

  Things point at a resource from several directions — a node's `parent_id`
  and `replaced_by_id`, a Search's Scope — and they all carry the same first
  rule, so they share one validation.

  The referenced records must always belong to the same Event: an Event's
  context is never shared, so a pointer into another Event's vocabulary is not
  a smaller mistake than a missing record — it is the same one.

  Options — `:resource` (the resource pointed at), then exactly one of
  `:attribute` or `:argument` (the field the id or ids live in), then:

    * `:lifecycle` — the referenced record must be in this lifecycle.
    * `:not_self?` — the referenced record must not be the record itself.
    * `:outside_subtree?` — the referenced record must be neither the record
      itself nor one of its descendants. Reparenting onto your own descendant
      would make you your own ancestor and detach the subtree from the tree.

  A nil or empty reference passes: absence is the tree's root and the Scope
  that means "everything", and `allow_nil?` is the right place to forbid it
  where it must not be absent.
  """

  use Ash.Resource.Validation

  alias Wekui.Tree

  require Ash.Query

  @impl true
  def init(opts) do
    cond do
      not (is_atom(opts[:resource]) and not is_nil(opts[:resource])) ->
        {:error, "expects a :resource module"}

      valid_reference?(opts) ->
        {:ok, opts}

      true ->
        {:error, "expects exactly one of :attribute or :argument"}
    end
  end

  defp valid_reference?(opts) do
    case {opts[:attribute], opts[:argument]} do
      {attribute, nil} when is_atom(attribute) and not is_nil(attribute) -> true
      {nil, argument} when is_atom(argument) and not is_nil(argument) -> true
      _both_or_neither -> false
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
    resource = opts[:resource]

    with {:ok, records} <- Ash.read(Ash.Query.filter(resource, id in ^ids), authorize?: false) do
      event_id = Ash.Changeset.get_attribute(changeset, :event_id)

      cond do
        length(records) < length(Enum.uniq(ids)) ->
          error(field, "does not exist")

        Enum.any?(records, &(&1.event_id != event_id)) ->
          error(field, "must belong to the same event")

        opts[:not_self?] && Enum.any?(records, &(&1.id == changeset.data.id)) ->
          error(field, "cannot be itself")

        opts[:lifecycle] && Enum.any?(records, &(&1.lifecycle != opts[:lifecycle])) ->
          error(field, "must be #{opts[:lifecycle]}")

        opts[:outside_subtree?] && descends?(resource, records, changeset.data.id) ->
          error(field, "would create a cycle: it is this record itself or one of its descendants")

        true ->
          :ok
      end
    end
  end

  defp descends?(resource, records, id) do
    subtree = MapSet.new(Tree.subtree_ids(resource, id))

    Enum.any?(records, &MapSet.member?(subtree, &1.id))
  end

  defp error(field, message), do: {:error, field: field, message: message}
end
