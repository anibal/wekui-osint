defmodule Wekui.Core.PlaceTest do
  use Wekui.DataCase, async: false

  alias Wekui.Core

  setup do
    {:ok, event} =
      Core.create_event(%{
        name: "event-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "Track the national blackout aftermath"
      })

    {:ok, other_event} =
      Core.create_event(%{
        name: "event-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "A different catastrophe entirely"
      })

    %{event: event, other_event: other_event}
  end

  defp place!(event, attrs \\ %{}) do
    {:ok, place} =
      Core.create_place(
        Map.merge(
          %{event_id: event.id, type: "parroquia", canonical_name: "Caraballeda"},
          attrs
        )
      )

    place
  end

  defp active!(event, attrs \\ %{}), do: place!(event, Map.put(attrs, :lifecycle, :active))

  describe "create" do
    test "is born proposed", %{event: event} do
      place = place!(event)

      assert place.lifecycle == :proposed
      assert place.event_id == event.id
      assert is_nil(place.parent_id)
    end

    test "can be born active for manual curation", %{event: event} do
      assert active!(event).lifecycle == :active
    end

    test "refuses to be born in a non-initial state", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.create_place(%{
                 event_id: event.id,
                 type: "parroquia",
                 canonical_name: "Caraballeda",
                 lifecycle: :deprecated
               })
    end

    test "folds the type label on write", %{event: event} do
      assert place!(event, %{type: "  PARROQUIA  "}).type == "parroquia"
      assert place!(event, %{type: "País"}).type == "pais"
    end

    for field <- [:event_id, :type, :canonical_name] do
      test "requires #{field}", %{event: event} do
        attrs =
          Map.delete(
            %{event_id: event.id, type: "parroquia", canonical_name: "Caraballeda"},
            unquote(field)
          )

        assert {:error, %Ash.Error.Invalid{}} = Core.create_place(attrs)
      end
    end

    test "accepts a parent from the same event", %{event: event} do
      parent = place!(event, %{type: "estado", canonical_name: "La Guaira"})
      child = place!(event, %{parent_id: parent.id})

      assert child.parent_id == parent.id
    end

    test "refuses a parent from another event", %{event: event, other_event: other} do
      foreign = place!(other, %{canonical_name: "Chacao"})

      assert {:error, error} =
               Core.create_place(%{
                 event_id: event.id,
                 type: "parroquia",
                 canonical_name: "Caraballeda",
                 parent_id: foreign.id
               })

      assert error_on(error, :parent_id) =~ "same event"
    end

    test "refuses a parent that does not exist", %{event: event} do
      assert {:error, error} =
               Core.create_place(%{
                 event_id: event.id,
                 type: "parroquia",
                 canonical_name: "Caraballeda",
                 parent_id: Ash.UUID.generate()
               })

      assert error_on(error, :parent_id) =~ "does not exist"
    end
  end

  describe "lifecycle" do
    test "promote moves proposed to active", %{event: event} do
      assert {:ok, promoted} = event |> place!() |> Core.promote_place()
      assert promoted.lifecycle == :active
    end

    test "promote refuses anything but proposed", %{event: event} do
      assert {:error, %Ash.Error.Invalid{}} = event |> active!() |> Core.promote_place()
    end

    test "deprecate redirects onto an active replacement", %{event: event} do
      place = active!(event)
      replacement = active!(event, %{canonical_name: "Caraballeda (Vargas)"})

      assert {:ok, deprecated} =
               Core.deprecate_place(place, %{replaced_by_id: replacement.id, note: "merged"})

      assert deprecated.lifecycle == :deprecated
      assert deprecated.replaced_by_id == replacement.id
      assert deprecated.status_note == "merged"
    end

    test "deprecate writes its own reason when none is given", %{event: event} do
      place = active!(event)
      replacement = active!(event, %{canonical_name: "Caraballeda (Vargas)"})

      {:ok, deprecated} = Core.deprecate_place(place, %{replaced_by_id: replacement.id})

      assert deprecated.status_note =~ "Caraballeda (Vargas)"
    end

    test "deprecate refuses a proposed place", %{event: event} do
      replacement = active!(event, %{canonical_name: "Macuto"})

      assert {:error, %Ash.Error.Invalid{}} =
               Core.deprecate_place(place!(event), %{replaced_by_id: replacement.id})
    end

    test "deprecate refuses the place itself as its replacement", %{event: event} do
      place = active!(event)

      assert {:error, error} = Core.deprecate_place(place, %{replaced_by_id: place.id})
      assert error_on(error, :replaced_by_id) =~ "itself"
    end

    test "deprecate refuses a replacement that is not active", %{event: event} do
      place = active!(event)
      proposed = place!(event, %{canonical_name: "Macuto"})

      assert {:error, error} = Core.deprecate_place(place, %{replaced_by_id: proposed.id})
      assert error_on(error, :replaced_by_id) =~ "must be active"
    end

    test "deprecate refuses a replacement from another event", %{event: event, other_event: other} do
      place = active!(event)
      foreign = active!(other, %{canonical_name: "Chacao"})

      assert {:error, error} = Core.deprecate_place(place, %{replaced_by_id: foreign.id})
      assert error_on(error, :replaced_by_id) =~ "same event"
    end

    test "discard retires proposed and active places, keeping the reason", %{event: event} do
      for place <- [place!(event), active!(event, %{canonical_name: "Macuto"})] do
        assert {:ok, discarded} = Core.discard_place(place, %{note: "not a real place"})
        assert discarded.lifecycle == :discarded
        assert discarded.status_note == "not a real place"
        assert is_nil(discarded.replaced_by_id)
      end
    end

    test "discard requires a reason", %{event: event} do
      place = place!(event)

      assert {:error, %Ash.Error.Invalid{}} = Core.discard_place(place, %{})
      assert {:error, %Ash.Error.Invalid{}} = Core.discard_place(place, %{note: ""})
      assert {:error, %Ash.Error.Invalid{}} = Core.discard_place(place, %{note: "   "})
    end

    test "discarded is terminal", %{event: event} do
      {:ok, discarded} = Core.discard_place(place!(event), %{note: "gone"})

      assert {:error, %Ash.Error.Invalid{}} = Core.promote_place(discarded)
      assert {:error, %Ash.Error.Invalid{}} = Core.discard_place(discarded, %{note: "again"})
    end
  end

  describe "curation" do
    test "set_type folds the new label", %{event: event} do
      {:ok, updated} = event |> place!() |> Core.set_place_type(%{type: "  Municipio "})

      assert updated.type == "municipio"
    end

    test "set_parent reparents within the event", %{event: event} do
      place = place!(event)
      new_parent = place!(event, %{type: "estado", canonical_name: "La Guaira"})

      assert {:ok, moved} = Core.set_place_parent(place, %{parent_id: new_parent.id})
      assert moved.parent_id == new_parent.id
    end

    test "set_parent to nil lifts the place to a root", %{event: event} do
      parent = place!(event, %{type: "estado", canonical_name: "La Guaira"})
      child = place!(event, %{parent_id: parent.id})

      assert {:ok, lifted} = Core.set_place_parent(child, %{parent_id: nil})
      assert is_nil(lifted.parent_id)
    end

    test "set_parent refuses to make a place its own parent", %{event: event} do
      place = place!(event)

      assert {:error, error} = Core.set_place_parent(place, %{parent_id: place.id})
      assert error_on(error, :parent_id) =~ "cycle"
    end

    test "set_parent refuses to make a place a child of its own descendant", %{event: event} do
      root = place!(event, %{type: "pais", canonical_name: "Venezuela"})
      state = place!(event, %{type: "estado", canonical_name: "La Guaira", parent_id: root.id})

      grandchild =
        place!(event, %{type: "parroquia", canonical_name: "Caraballeda", parent_id: state.id})

      assert {:error, error} = Core.set_place_parent(root, %{parent_id: grandchild.id})
      assert error_on(error, :parent_id) =~ "cycle"
    end

    test "set_parent refuses a parent from another event", %{event: event, other_event: other} do
      place = place!(event)
      foreign = place!(other, %{canonical_name: "Chacao"})

      assert {:error, error} = Core.set_place_parent(place, %{parent_id: foreign.id})
      assert error_on(error, :parent_id) =~ "same event"
    end
  end

  describe "reads" do
    setup %{event: event} do
      root = place!(event, %{type: "pais", canonical_name: "Venezuela"})
      state = place!(event, %{type: "estado", canonical_name: "La Guaira", parent_id: root.id})

      parish =
        place!(event, %{type: "parroquia", canonical_name: "Caraballeda", parent_id: state.id})

      %{root: root, state: state, parish: parish}
    end

    test "by_event returns only that event's places", %{
      event: event,
      other_event: other,
      root: root
    } do
      place!(other, %{canonical_name: "Chacao"})

      {:ok, places} = Core.list_places(event.id)
      ids = Enum.map(places, & &1.id)

      # The three built here, plus the Unplaced Place the Event was born with.
      assert length(places) == 4
      assert root.id in ids
      assert event.unplaced_place_id in ids
    end

    test "active returns only active places", %{event: event, root: root} do
      {:ok, promoted} = Core.promote_place(root)
      {:ok, places} = Core.list_active_places(event.id)
      ids = Enum.map(places, & &1.id)

      # The Unplaced Place is active from birth — it has to be able to hold
      # Posts — so it stands alongside anything an Actor has promoted.
      assert Enum.sort(ids) == Enum.sort([promoted.id, event.unplaced_place_id])
    end

    test "ancestors walks nearest-first, excluding the place itself", %{
      root: root,
      state: state,
      parish: parish
    } do
      {:ok, ancestors} = Core.place_ancestors(parish.id)

      assert Enum.map(ancestors, & &1.id) == [state.id, root.id]
    end

    test "ancestors of a root is empty", %{root: root} do
      assert {:ok, []} = Core.place_ancestors(root.id)
    end

    test "subtree includes the place and every descendant", %{
      root: root,
      state: state,
      parish: parish
    } do
      {:ok, subtree} = Core.place_subtree(root.id)

      assert Enum.sort(Enum.map(subtree, & &1.id)) == Enum.sort([root.id, state.id, parish.id])
    end

    test "subtree of a leaf is just the leaf", %{parish: parish} do
      {:ok, subtree} = Core.place_subtree(parish.id)

      assert Enum.map(subtree, & &1.id) == [parish.id]
    end

    test "a place loads its event, parent and children", %{
      event: event,
      root: root,
      state: state,
      parish: parish
    } do
      {:ok, loaded} = Core.get_place(state.id, load: [:event, :parent, :children])

      assert loaded.event.id == event.id
      assert loaded.parent.id == root.id
      assert Enum.map(loaded.children, & &1.id) == [parish.id]
    end

    test "a deprecated place loads its replacement", %{event: event} do
      {:ok, place} = event |> place!(%{canonical_name: "Macuto"}) |> Core.promote_place()
      replacement = active!(event, %{canonical_name: "Macuto (La Guaira)"})

      {:ok, deprecated} = Core.deprecate_place(place, %{replaced_by_id: replacement.id})
      {:ok, loaded} = Core.get_place(deprecated.id, load: [:replaced_by])

      assert loaded.replaced_by.id == replacement.id
    end
  end
end
