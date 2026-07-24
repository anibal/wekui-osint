defmodule Wekui.Judgment.Changes.CloseCurrent do
  @moduledoc """
  After a judgment is written, retracts every current answer to the *same
  question* held in a counterpart resource — the examined-empty ↔ real-answer
  mutual exclusion. A real theme answer retracts the Post's "no theme"; a
  "no theme" retracts every current theme answer for the Post.

      change {CloseCurrent, resource: Wekui.Judgment.ThemeNone, match: [:post_id]}

  The counterpart rows are matched on the `:match` fields read from the changeset
  and closed with the counterpart's own `:retract`, inside the action's
  transaction. It runs in an `after_action`, so the new answer is already written
  before its counterpart is withdrawn.
  """

  use Ash.Resource.Change

  require Ash.Query
  import Ash.Expr

  @impl true
  def init(opts) do
    cond do
      not (is_atom(opts[:resource]) and not is_nil(opts[:resource])) ->
        {:error, "CloseCurrent expects a :resource module"}

      not (is_list(opts[:match]) and opts[:match] != [] and Enum.all?(opts[:match], &is_atom/1)) ->
        {:error, "CloseCurrent expects a non-empty :match list of attribute atoms"}

      true ->
        {:ok, opts}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, result ->
      resource = opts[:resource]

      filter =
        Enum.reduce(opts[:match], expr(is_nil(superseded_at)), fn field, acc ->
          value = Ash.Changeset.get_attribute(changeset, field)
          expr(^acc and ^ref(field) == ^value)
        end)

      {:ok, rows} = Ash.read(Ash.Query.filter(resource, ^filter), authorize?: false)

      Enum.each(rows, fn row ->
        row |> Ash.Changeset.for_update(:retract) |> Ash.update!(authorize?: false)
      end)

      {:ok, result}
    end)
  end
end
