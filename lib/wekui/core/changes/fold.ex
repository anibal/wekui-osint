defmodule Wekui.Core.Changes.Fold do
  @moduledoc """
  Writes `Wekui.Normalize.fold/1` of one attribute into another.

      change {Fold, from: :type, to: :type}          # folds in place
      change {Fold, from: :name, to: :normalized}    # derives a match key

  Only fires when `:from` is actually being changed, so the derived value can
  never drift from its source, and can never be supplied by the caller.
  """

  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if is_atom(opts[:from]) and is_atom(opts[:to]) do
      {:ok, opts}
    else
      {:error, "#{inspect(__MODULE__)} expects atom :from and :to options"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    case Ash.Changeset.fetch_change(changeset, opts[:from]) do
      {:ok, value} when is_binary(value) ->
        Ash.Changeset.force_change_attribute(changeset, opts[:to], Wekui.Normalize.fold(value))

      _other ->
        changeset
    end
  end
end
