defmodule Wekui.Judgment.Validations.Provenance do
  @moduledoc """
  A judgment's confidence belongs to agents alone: an agent's judgment must carry
  a confidence, a person's must carry none. The Actor decides which — so we read
  it and check the pairing on the way in, gating the write rather than trusting a
  read.

  A missing or unreadable Actor is not this validation's error to raise — the
  Actor reference check reports it — so an absent Actor passes here.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    actor_id = Ash.Changeset.get_attribute(changeset, :actor_id)
    confidence = Ash.Changeset.get_attribute(changeset, :confidence)

    case actor_id && Ash.get(Wekui.Core.Actor, actor_id, authorize?: false) do
      {:ok, %{kind: :agent}} when is_nil(confidence) ->
        {:error, field: :confidence, message: "is required for an agent's judgment"}

      {:ok, %{kind: :person}} when not is_nil(confidence) ->
        {:error,
         field: :confidence, message: "belongs to an agent — a person's judgment carries none"}

      _agent_with_confidence_or_person_without_or_absent_actor ->
        :ok
    end
  end
end
