defmodule Wekui.Narrative.Changes.DeriveHandle do
  @moduledoc """
  Sets a [[person]]'s `display_handle` from their `full_name` via
  `Wekui.Narrative.Handle`. When the name cannot be read into a handle with
  confidence, the handle is left absent for a human to assign — the escape hatch.
  """

  use Ash.Resource.Change

  alias Wekui.Narrative.Handle

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :full_name) do
      name when is_binary(name) ->
        case Handle.derive(name) do
          {:ok, handle} ->
            Ash.Changeset.force_change_attribute(changeset, :display_handle, handle)

          {:review, _reason} ->
            changeset
        end

      _absent ->
        changeset
    end
  end
end
