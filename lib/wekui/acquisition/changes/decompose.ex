defmodule Wekui.Acquisition.Changes.Decompose do
  @moduledoc """
  Works a Search out into its Queries, once the action's own changes have
  landed.

  `wipe_first?: true` throws the existing plan away first — that is `decompose`
  on a draft. `wipe_first?: false` leaves it alone and adds only what is
  missing — that is extending. Because `Wekui.Acquisition.Plan.build/2` never
  rewrites an existing Query, both are the same engine.

  Runs as an after-action hook, inside the action's transaction: if any Query
  or bridge fails to insert, the Search's own change goes back with it, and we
  are never left with half a plan.
  """

  use Ash.Resource.Change

  alias Wekui.Acquisition.Plan

  @impl true
  def init(opts) do
    if is_boolean(opts[:wipe_first?]) do
      {:ok, opts}
    else
      {:error, "#{inspect(__MODULE__)} expects a boolean :wipe_first? option"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    now = Ash.Changeset.get_argument(changeset, :now) || DateTime.utc_now()

    Ash.Changeset.after_action(changeset, fn _changeset, search ->
      with :ok <- maybe_wipe(search, opts[:wipe_first?]),
           {:ok, _added} <- Plan.build(search, now) do
        {:ok, search}
      end
    end)
  end

  defp maybe_wipe(search, true), do: Plan.wipe(search.id)
  defp maybe_wipe(_search, false), do: :ok
end
