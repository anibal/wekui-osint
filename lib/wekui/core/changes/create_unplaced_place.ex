defmodule Wekui.Core.Changes.CreateUnplacedPlace do
  @moduledoc """
  Gives a new Event its one Unplaced Place, and points the Event at it.

  The pointer is what makes a Place *the* Unplaced Place — not its name and not
  its Type, both of which anyone curating the gazetteer may change. Creating it
  with the Event rather than on first use means there is never a moment when an
  Event has nowhere to put a Post whose location is still an open question.
  """

  use Ash.Resource.Change

  alias Wekui.Core.Place

  @canonical_name "Unplaced"
  @type_label "unplaced"

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, event ->
      with {:ok, place} <- create_place(event),
           {:ok, event} <- point_at(event, place) do
        {:ok, event}
      end
    end)
  end

  defp create_place(event) do
    Ash.create(
      Place,
      %{
        event_id: event.id,
        type: @type_label,
        canonical_name: @canonical_name,
        lifecycle: :active
      },
      authorize?: false
    )
  end

  defp point_at(event, place) do
    Ash.update(event, %{unplaced_place_id: place.id},
      action: :set_unplaced_place,
      authorize?: false
    )
  end
end
