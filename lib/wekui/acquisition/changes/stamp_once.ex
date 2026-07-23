defmodule Wekui.Acquisition.Changes.StampOnce do
  @moduledoc """
  Stamps the current moment onto an attribute, but only the first time.

      change {StampOnce, attribute: :started_at}

  "When it first became active" and "when we began asking" are both facts about
  a beginning, so resuming a paused Search or re-starting an interrupted Query
  must not move them. Ash's `set_new_attribute` asks whether *this* changeset is
  setting the attribute, which is a different question — these attributes are
  never accepted as input, so it would overwrite every time.
  """

  use Ash.Resource.Change

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]) and not is_nil(opts[:attribute]) do
      {:ok, opts}
    else
      {:error, "#{inspect(__MODULE__)} expects an :attribute option"}
    end
  end

  @impl true
  def change(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Map.get(changeset.data, attribute) do
      nil -> Ash.Changeset.force_change_attribute(changeset, attribute, DateTime.utc_now())
      _already_stamped -> changeset
    end
  end
end
