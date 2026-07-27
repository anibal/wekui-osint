defmodule Wekui.Curation.Validations.HumanActor do
  @moduledoc """
  A curation act is a *person's* act, so the Actor it names must be one.

  The machine's own acts already have a receipt of their own — a `Wekui.Pipelines.Run`
  carries the executing agent — and an Act naming an agent would be that receipt wearing
  the wrong name. The pairing is checked on the way in, gating the write rather than
  trusting a read: the same shape as `Wekui.Judgment.Validations.Provenance`, which
  refuses a confidence on a person's judgment.

  A missing or unreadable Actor is not this validation's error to raise — the Actor
  reference check reports it — so an absent Actor passes here.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    actor_id = Ash.Changeset.get_attribute(changeset, :actor_id)

    case actor_id && Ash.get(Wekui.Core.Actor, actor_id, authorize?: false) do
      {:ok, %{kind: :agent}} ->
        {:error,
         field: :actor_id,
         message: "must be a person — an agent's acts are receipted by a run, not curated"}

      _person_or_absent_actor ->
        :ok
    end
  end
end
