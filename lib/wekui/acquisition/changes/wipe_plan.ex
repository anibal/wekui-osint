defmodule Wekui.Acquisition.Changes.WipePlan do
  @moduledoc """
  Throws a draft Search's plan away before the action's own changes land.

  Editing a draft's Scope or Terms replaces the very rows the plan's bridges
  point at, so the plan has to go first. With `only_with_arguments:`, it goes
  only when one of those arguments was actually supplied — editing the intent
  alone leaves the plan standing.
  """

  use Ash.Resource.Change

  alias Wekui.Acquisition.Plan

  @impl true
  def init(opts) do
    case opts[:only_with_arguments] do
      [_ | _] -> {:ok, opts}
      _ -> {:error, "#{inspect(__MODULE__)} expects a non-empty :only_with_arguments option"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    if wipe?(changeset, opts[:only_with_arguments]) do
      Ash.Changeset.before_action(changeset, fn changeset ->
        case Plan.wipe(changeset.data.id) do
          :ok -> changeset
          {:error, error} -> Ash.Changeset.add_error(changeset, error)
        end
      end)
    else
      changeset
    end
  end

  defp wipe?(changeset, arguments) do
    Enum.any?(arguments, fn argument ->
      match?(
        {:ok, value} when not is_nil(value),
        Ash.Changeset.fetch_argument(changeset, argument)
      )
    end)
  end
end
