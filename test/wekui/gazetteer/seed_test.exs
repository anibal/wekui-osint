defmodule Wekui.Gazetteer.SeedTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Gazetteer.Seed
  alias Wekui.Narrative
  alias Wekui.Narrative.PlaceResolver

  # A three-node slice shaped like the real data: a trusted spine and a building with
  # two surface names (a colloquial and a spelling variant).
  @nodes [
    %{
      "old_id" => 1,
      "parent_old_id" => nil,
      "canonical" => "La Guaira",
      "type" => "estado",
      "names" => [%{"name" => "La Guaira", "kind" => "official", "emission" => "raw"}],
      "cross_check" => %{"gz" => "trusted"}
    },
    %{
      "old_id" => 2,
      "parent_old_id" => 1,
      "canonical" => "Caraballeda",
      "type" => "parroquia",
      "names" => [%{"name" => "Caraballeda", "kind" => "official", "emission" => "raw"}],
      "cross_check" => %{"gz" => "trusted"}
    },
    %{
      "old_id" => 3,
      "parent_old_id" => 2,
      "canonical" => "Edificio OPP 25",
      "type" => "edificio",
      "names" => [
        %{"name" => "Edificio OPP 25", "kind" => "colloquial", "emission" => "anchored"},
        %{"name" => "opp 25", "kind" => "spelling_variant", "emission" => "recognition_only"}
      ],
      "cross_check" => %{"gz" => "not_found"}
    }
  ]

  defp places(event_id),
    do: event_id |> Core.list_places!() |> Enum.reject(&(&1.type == "unplaced"))

  test "seeds the tree top-down, parents before children, with its surface names" do
    event = event!()
    stats = Seed.caraballeda(event.id, nodes: @nodes)

    assert stats == %{created: 3, reused: 0, names: 4}

    by_name = Map.new(places(event.id), &{&1.canonical_name, &1})
    assert by_name["Caraballeda"].parent_id == by_name["La Guaira"].id
    assert by_name["Edificio OPP 25"].parent_id == by_name["Caraballeda"].id
    assert by_name["Edificio OPP 25"].type == "edificio"
    assert by_name["Edificio OPP 25"].lifecycle == :active

    opp_names =
      by_name["Edificio OPP 25"].id
      |> Core.list_place_names!()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert opp_names == ["Edificio OPP 25", "opp 25"]
  end

  test "is idempotent — re-seeding reuses places and names, never duplicates" do
    event = event!()
    Seed.caraballeda(event.id, nodes: @nodes)
    stats = Seed.caraballeda(event.id, nodes: @nodes)

    assert stats == %{created: 0, reused: 3, names: 0}
    assert length(places(event.id)) == 3
  end

  test "a seeded building resolves a real mention to its node" do
    event = event!()
    agent = agent!(event)
    Seed.caraballeda(event.id, nodes: @nodes)

    claim =
      Narrative.draft_claim!(%{
        event_id: event.id,
        kind: "colapso",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        place_mention: "edificio OPP 25, Caraballeda",
        actor_id: agent.id,
        confidence: 0.8
      })

    {:ok, _} = PlaceResolver.resolve(claim)

    assert [link] = Narrative.list_claim_places!(claim.id)
    assert Core.get_place!(link.place_id).canonical_name == "Edificio OPP 25"
    assert link.how_resolved == :mention_exact
  end
end
