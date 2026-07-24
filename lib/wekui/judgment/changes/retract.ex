defmodule Wekui.Judgment.Changes.Retract do
  @moduledoc """
  Closes a judgment without a successor — the Actor withdraws the answer and the
  question goes back to unanswered. Refuses to reclose one already closed, so a
  double retraction is an error, not a silent no-op.

  This is also how one answer is closed on the way to being superseded (by
  `Changes.Supersede`) and how the counterpart in the examined-empty ↔ real-answer
  pair is closed (by `Changes.CloseCurrent`): in both, the successor link is set
  separately, afterwards.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    # Guard on the DB's current state, not the record handed in, which may be a
    # stale copy read before an earlier close.
    Ash.Changeset.before_action(changeset, fn changeset ->
      current = Ash.get!(changeset.resource, changeset.data.id, authorize?: false)

      if current.superseded_at do
        Ash.Changeset.add_error(changeset,
          field: :superseded_at,
          message: "is already superseded or retracted"
        )
      else
        Ash.Changeset.force_change_attribute(changeset, :superseded_at, DateTime.utc_now())
      end
    end)
  end
end
