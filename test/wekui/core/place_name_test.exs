defmodule Wekui.Core.PlaceNameTest do
  use Wekui.DataCase, async: false

  alias Wekui.Core
  alias Wekui.Core.PlaceName

  setup do
    {:ok, event} =
      Core.create_event(%{
        name: "event-#{System.unique_integer([:positive])}",
        t0: ~U[2026-03-07 20:00:00.000000Z],
        goal: "Track the national blackout aftermath"
      })

    {:ok, place} =
      Core.create_place(%{
        event_id: event.id,
        type: "parroquia",
        canonical_name: "Caraballeda"
      })

    %{event: event, place: place}
  end

  defp name!(place, attrs \\ %{}) do
    {:ok, place_name} =
      Core.create_place_name(
        Map.merge(
          %{place_id: place.id, name: "Caraballeda", kind: :official, emission: :raw},
          attrs
        )
      )

    place_name
  end

  describe "create" do
    test "attaches a string on both axes", %{place: place} do
      place_name = name!(place)

      assert place_name.place_id == place.id
      assert place_name.kind == :official
      assert place_name.emission == :raw
    end

    test "derives normalized from name", %{place: place} do
      assert name!(place, %{name: "Maiquetía"}).normalized == "maiquetia"
      assert name!(place, %{name: "  La   Guaira "}).normalized == "la guaira"
    end

    test "refuses a caller-supplied normalized outright", %{place: place} do
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.NoSuchInput{}]}} =
               Core.create_place_name(%{
                 place_id: place.id,
                 name: "Maiquetía",
                 kind: :official,
                 emission: :raw,
                 normalized: "whatever-i-want"
               })
    end

    for field <- [:place_id, :name, :kind, :emission] do
      test "requires #{field}", %{place: place} do
        attrs =
          Map.delete(
            %{place_id: place.id, name: "Caraballeda", kind: :official, emission: :raw},
            unquote(field)
          )

        assert {:error, %Ash.Error.Invalid{}} = Core.create_place_name(attrs)
      end
    end

    test "refuses a kind outside the axis", %{place: place} do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.create_place_name(%{
                 place_id: place.id,
                 name: "Caraballeda",
                 kind: :nickname,
                 emission: :raw
               })
    end

    test "refuses an emission outside the axis", %{place: place} do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.create_place_name(%{
                 place_id: place.id,
                 name: "Caraballeda",
                 kind: :official,
                 emission: :shouted
               })
    end

    test "the two axes are independent", %{place: place} do
      for kind <- PlaceName.kinds(), emission <- PlaceName.emissions() do
        assert %PlaceName{} = name!(place, %{kind: kind, emission: emission})
      end
    end

    test "one place may carry the same string under different kinds", %{place: place} do
      official = name!(place, %{name: "Caraballeda", kind: :official})
      colloquial = name!(place, %{name: "Caraballeda", kind: :colloquial})

      assert official.id != colloquial.id
      assert official.normalized == colloquial.normalized
    end
  end

  describe "curation" do
    test "set_kind moves the kind axis only", %{place: place} do
      {:ok, updated} = place |> name!() |> Core.set_place_name_kind(%{kind: :historical})

      assert updated.kind == :historical
      assert updated.emission == :raw
    end

    test "set_emission moves the emission axis only", %{place: place} do
      {:ok, updated} =
        place |> name!() |> Core.set_place_name_emission(%{emission: :recognition_only})

      assert updated.emission == :recognition_only
      assert updated.kind == :official
    end
  end

  describe "reads" do
    test "by_place returns only that place's names", %{event: event, place: place} do
      {:ok, other_place} =
        Core.create_place(%{event_id: event.id, type: "parroquia", canonical_name: "Macuto"})

      kept = name!(place)
      name!(other_place, %{name: "Macuto"})

      {:ok, names} = Core.list_place_names(place.id)

      assert Enum.map(names, & &1.id) == [kept.id]
    end

    test "a place loads its names", %{place: place} do
      name!(place, %{name: "Caraballeda"})
      name!(place, %{name: "Tanaguarena", kind: :colloquial})

      {:ok, loaded} = Core.get_place(place.id, load: [:place_names])

      assert length(loaded.place_names) == 2
    end

    test "a place name loads the place it belongs to", %{place: place} do
      place_name = name!(place)

      {:ok, loaded} = Core.get_place_name(place_name.id, load: [:place])

      assert loaded.place.id == place.id
    end
  end
end
