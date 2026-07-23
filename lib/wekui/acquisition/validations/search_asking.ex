defmodule Wekui.Acquisition.Validations.SearchAsking do
  @moduledoc """
  A Query is only asked while its Search is collecting.

  `start` permits an `:active` Search — asking begins only once the Search is
  collecting. `complete` and `discard` permit `:active` or `:paused`, so a Query
  that was already running when the Search was paused can still be settled. A
  draft's Queries are not yet real questions we mean to ask, and a closed Search
  is final; neither may be asked or settled.

  Option — `:allow`, the non-empty list of Search statuses this action permits.
  """

  use Ash.Resource.Validation

  alias Wekui.Acquisition.Search

  @impl true
  def init(opts) do
    case opts[:allow] do
      [_ | _] = allow ->
        if Enum.all?(allow, &is_atom/1),
          do: {:ok, opts},
          else: {:error, ":allow must be a list of status atoms"}

      _not_a_list ->
        {:error, "#{inspect(__MODULE__)} expects a non-empty :allow list"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    allow = opts[:allow]

    case Ash.get(Search, changeset.data.search_id, authorize?: false) do
      {:ok, search} ->
        if search.status in allow do
          :ok
        else
          {:error, message: "the Search must be #{Enum.join(allow, " or ")}"}
        end

      # A Query's Search cannot be missing (non-null FK); nothing to add if it is.
      {:error, _error} ->
        :ok
    end
  end
end
