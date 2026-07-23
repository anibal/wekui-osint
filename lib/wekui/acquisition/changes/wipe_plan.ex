defmodule Wekui.Acquisition.Changes.WipePlan do
  @moduledoc """
  Throws a draft Search's plan away before the action's own changes land.

  A draft's plan is disposable, and an edit invalidates it two ways: by
  replacing the rows its bridges point at (a new Scope or new Terms), or by
  moving the time grid its slices are cut from (the window bounds or the slice
  length). Either way the existing Queries no longer match the Search, so they
  go first and a later decompose rebuilds them.

  Triggers — at least one is required:

    * `:only_with_arguments` — wipe when one of these arguments was supplied.
    * `:or_changing_attributes` — wipe when one of these attributes is changing.

  Editing the intent alone touches neither, so the plan stands.
  """

  use Ash.Resource.Change

  alias Wekui.Acquisition.Plan

  @impl true
  def init(opts) do
    arguments = opts[:only_with_arguments] || []
    attributes = opts[:or_changing_attributes] || []

    if arguments == [] and attributes == [] do
      {:error, "#{inspect(__MODULE__)} expects :only_with_arguments or :or_changing_attributes"}
    else
      {:ok, opts}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    if wipe?(changeset, opts) do
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

  defp wipe?(changeset, opts) do
    supplied_argument?(changeset, opts[:only_with_arguments] || []) or
      changing_attribute?(changeset, opts[:or_changing_attributes] || [])
  end

  defp supplied_argument?(changeset, arguments) do
    Enum.any?(arguments, fn argument ->
      match?(
        {:ok, value} when not is_nil(value),
        Ash.Changeset.fetch_argument(changeset, argument)
      )
    end)
  end

  defp changing_attribute?(changeset, attributes) do
    Enum.any?(attributes, &Ash.Changeset.changing_attribute?(changeset, &1))
  end
end
