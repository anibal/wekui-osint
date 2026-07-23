defmodule Wekui.Acquisition.Validations.Extendable do
  @moduledoc """
  Extending is the path for a Search whose plan is already fixed.

  A draft does not need it — edit it and work the plan out again. A closed
  Search is finished, and growing it would reopen a question we said we had
  stopped asking.
  """

  use Ash.Resource.Validation

  @extendable [:ready, :active, :paused]

  @impl true
  def validate(changeset, _opts, _context) do
    case changeset.data.status do
      status when status in @extendable ->
        :ok

      :draft ->
        {:error, field: :status, message: "a draft is edited and worked out again, not extended"}

      :closed ->
        {:error, field: :status, message: "a closed Search is finished"}
    end
  end
end
