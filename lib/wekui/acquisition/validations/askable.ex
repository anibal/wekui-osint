defmodule Wekui.Acquisition.Validations.Askable do
  @moduledoc """
  A Query that has completed or been discarded is settled.

  What a completed Query returned is what it returned, and a discarded one was
  given up on deliberately. Neither is reopened: a new question is a new Query.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    cond do
      changeset.data.discarded_at ->
        {:error, field: :discarded_at, message: "this Query was given up on"}

      changeset.data.completed_at ->
        {:error, field: :completed_at, message: "this Query already finished"}

      true ->
        :ok
    end
  end
end
