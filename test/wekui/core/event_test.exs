defmodule Wekui.Core.EventTest do
  use Wekui.DataCase, async: false

  alias Wekui.Core

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "caracas-blackout-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "Track the national blackout aftermath"
      },
      overrides
    )
  end

  describe "create_event/1" do
    test "creates an event and defaults the timezone" do
      assert {:ok, event} = Core.create_event(valid_attrs())
      assert event.timezone == "America/Caracas"
      assert event.goal == "Track the national blackout aftermath"
      refute is_nil(event.id)
      refute is_nil(event.inserted_at)
    end

    test "accepts an explicit timezone" do
      assert {:ok, event} = Core.create_event(valid_attrs(%{timezone: "UTC"}))
      assert event.timezone == "UTC"
    end

    for field <- [:name, :t0, :goal] do
      test "requires #{field}" do
        attrs = Map.delete(valid_attrs(), unquote(field))
        assert {:error, %Ash.Error.Invalid{}} = Core.create_event(attrs)
      end
    end

    test "enforces the unique_name identity" do
      attrs = valid_attrs()
      assert {:ok, _} = Core.create_event(attrs)
      assert {:error, %Ash.Error.Invalid{}} = Core.create_event(attrs)
    end
  end

  describe "the Unplaced Place" do
    test "every Event is born pointing at one" do
      {:ok, event} = Core.create_event(valid_attrs())

      refute is_nil(event.unplaced_place_id)

      {:ok, unplaced} = Core.get_place(event.unplaced_place_id)
      assert unplaced.event_id == event.id
      # Active from birth: it has to be able to hold Posts straight away.
      assert unplaced.lifecycle == :active
    end

    test "it is the Event's only one, and each Event has its own" do
      {:ok, first} = Core.create_event(valid_attrs())
      {:ok, second} = Core.create_event(valid_attrs())

      refute first.unplaced_place_id == second.unplaced_place_id

      {:ok, places} = Core.list_places(first.id)
      assert Enum.map(places, & &1.id) == [first.unplaced_place_id]
    end

    test "an Event loads it like any other Place" do
      {:ok, event} = Core.create_event(valid_attrs())
      {:ok, loaded} = Core.get_event(event.id, load: [:unplaced_place])

      assert loaded.unplaced_place.id == event.unplaced_place_id
      assert loaded.unplaced_place.canonical_name == "Unplaced"
    end
  end

  describe "reads" do
    test "get_event_by_name/1 round-trips a created event" do
      {:ok, event} = Core.create_event(valid_attrs(%{name: "unique-lookup-name"}))
      assert {:ok, found} = Core.get_event_by_name("unique-lookup-name")
      assert found.id == event.id
    end

    test "list_events/0 returns created events" do
      {:ok, event} = Core.create_event(valid_attrs())
      assert {:ok, events} = Core.list_events()
      assert Enum.any?(events, &(&1.id == event.id))
    end
  end
end
