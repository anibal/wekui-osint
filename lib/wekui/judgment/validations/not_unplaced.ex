defmodule Wekui.Judgment.Validations.NotUnplaced do
  @moduledoc """
  A Post cannot be *placed* at its Event's Unplaced Place. Unplaced is where a
  Post waits when nothing has been worked out — it is the default a placement is
  read back as, never an answer an Actor asserts. Judging a Post *into* Unplaced
  would say "I have decided it is not worked out", which is a contradiction, so
  the write is refused.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    place_id = Ash.Changeset.get_attribute(changeset, :place_id)
    event_id = Ash.Changeset.get_attribute(changeset, :event_id)

    with true <- not is_nil(place_id) and not is_nil(event_id),
         {:ok, %{unplaced_place_id: unplaced_id}} <-
           Ash.get(Wekui.Core.Event, event_id, authorize?: false),
         true <- place_id == unplaced_id do
      {:error,
       field: :place_id,
       message: "cannot be the Unplaced Place — a Post is Unplaced by default, not by judgment"}
    else
      _ -> :ok
    end
  end
end
