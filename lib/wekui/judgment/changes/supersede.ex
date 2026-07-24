defmodule Wekui.Judgment.Changes.Supersede do
  @moduledoc """
  The atomic close-old / open-new that makes a judgment's slot hold exactly one
  current answer.

      change {Supersede, slot: [:post_id, :theme_id]}

  The current answer in the slot is closed in a `before_action` — so the partial
  "one current per slot" index never sees two open rows at insert time — and the
  closed answer is pointed at its successor in an `after_action`, the first moment
  the successor's id exists. Both run inside the action's transaction, so any
  failure rolls the whole judgment back.

  Closing reuses the resource's own `:retract`; linking reuses its
  `:link_successor`. The `:slot` fields are read from the changeset, so one change
  serves every judgment whatever its slot — `[:post_id, :theme_id]` for a Theme,
  `[:post_id]` for a placement.
  """

  use Ash.Resource.Change

  alias Wekui.Judgment.Slot

  @impl true
  def init(opts) do
    if Slot.nonempty_atom_list?(opts[:slot]) do
      {:ok, opts}
    else
      {:error, "Supersede expects a non-empty :slot list of attribute atoms"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    slot = opts[:slot]

    changeset
    |> Ash.Changeset.before_action(&close_current(&1, slot))
    |> Ash.Changeset.after_action(&link_successor/2)
  end

  defp close_current(changeset, slot) do
    pairs = Enum.map(slot, &{&1, Ash.Changeset.get_attribute(changeset, &1)})

    case Ash.read_one(Slot.current(changeset.resource, pairs), authorize?: false) do
      {:ok, nil} ->
        changeset

      {:ok, current} ->
        closed = current |> Ash.Changeset.for_update(:retract) |> Ash.update!(authorize?: false)
        Ash.Changeset.put_context(changeset, :supersede, closed)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp link_successor(changeset, result) do
    case changeset.context do
      %{supersede: closed} ->
        closed
        |> Ash.Changeset.for_update(:link_successor, %{superseded_by_id: result.id})
        |> Ash.update!(authorize?: false)

        {:ok, result}

      _no_row_closed ->
        {:ok, result}
    end
  end
end
