defmodule Wekui.Narrative.GazetteerNamesTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Narrative.PrivateNames
  alias Wekui.Normalize

  # A building whose colloquial name is a bare person-name — the exact hole the place
  # resolver could open by proposing places out of post text (advisor's live risk).
  defp building!(event, lifecycle) do
    place =
      Core.create_place!(%{
        event_id: event.id,
        type: "edificio",
        canonical_name: "Residencias Karina",
        lifecycle: lifecycle
      })

    Core.create_place_name!(%{
      place_id: place.id,
      name: "Marisela Guevara",
      kind: :colloquial,
      emission: :recognition_only
    })

    place
  end

  describe "gazetteer_names/1 — only :active places widen the F54 gate" do
    test "a :proposed place's names are excluded until it is promoted" do
      event = event!()
      place = building!(event, :proposed)

      names = PrivateNames.gazetteer_names(event.id)
      refute Normalize.fold("Residencias Karina") in names
      refute Normalize.fold("Marisela Guevara") in names

      Core.promote_place!(place)

      promoted = PrivateNames.gazetteer_names(event.id)
      assert Normalize.fold("Residencias Karina") in promoted
      assert Normalize.fold("Marisela Guevara") in promoted
    end

    test "a machine proposal cannot, on its own, explain away a private name" do
      event = event!()
      place = building!(event, :proposed)

      # Still flagged as a private individual while the place is only proposed.
      assert PrivateNames.unexplained(
               "rescataron a Marisela Guevara",
               PrivateNames.vocabulary(event.id)
             ) ==
               ["Marisela Guevara"]

      # Promote it (the human step) — now a known place alias, and the gate lets it through.
      Core.promote_place!(place)

      assert PrivateNames.unexplained(
               "colapsó Marisela Guevara",
               PrivateNames.vocabulary(event.id)
             ) ==
               []
    end
  end
end
