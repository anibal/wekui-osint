defmodule Wekui.Capture.Validations.SameEventTest do
  @moduledoc "The reference contract SameEvent enforces at configuration time."
  use ExUnit.Case, async: true

  alias Wekui.Capture.Validations.SameEvent

  test "accepts a reference whose Event is a direct attribute" do
    assert {:ok, _opts} = SameEvent.init(references: [{:author_id, Wekui.Capture.Author}])
  end

  test "accepts a reference whose Event is one relationship away" do
    assert {:ok, _opts} =
             SameEvent.init(
               references: [{:query_id, Wekui.Acquisition.Query, [:search, :event_id]}]
             )
  end

  test "rejects a path deeper than one relationship — the loader is one-level" do
    assert {:error, _} =
             SameEvent.init(
               references: [{:place_id, Wekui.Core.Place, [:parent, :parent, :event_id]}]
             )
  end

  test "rejects an empty references list" do
    assert {:error, _} = SameEvent.init(references: [])
  end
end
