defmodule Wekui.Acquisition.Calculations.ResultMode do
  @moduledoc """
  Reads the mode a Query was asked in back out of its own text.

  The mode lives in the request and nowhere else, so there is no second place
  that could disagree about what was actually asked.
  """

  use Ash.Resource.Calculation

  alias Wekui.Acquisition.QueryText

  @impl true
  def load(_query, _opts, _context), do: [:query_text]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &QueryText.result_mode_of(&1.query_text))
  end
end
