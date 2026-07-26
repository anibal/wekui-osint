defmodule Wekui.Narrative.ClaimPlaceTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative

  setup do
    event = event!()
    agent = agent!(event)

    claim =
      Narrative.draft_claim!(%{
        event_id: event.id,
        kind: "rescate",
        subject: "un hombre de 21 años",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: agent.id,
        confidence: 0.9
      })

    %{event: event, agent: agent, claim: claim, place: place!(event)}
  end

  defp link!(ctx, attrs) do
    Narrative.link_place!(Map.merge(%{claim_id: ctx.claim.id, place_id: ctx.place.id}, attrs))
  end

  describe "link — a claim is about a place" do
    test "records the place, how it was resolved, and the confidence", ctx do
      link = link!(ctx, %{how_resolved: :mention_exact, confidence: 0.9})

      assert link.place_id == ctx.place.id
      assert link.how_resolved == :mention_exact
      assert link.confidence == 0.9
    end

    test "a claim can be about several places at once", ctx do
      other = place!(ctx.event, %{canonical_name: "Tanaguarena", type: "sector"})
      link!(ctx, %{how_resolved: :mention_exact, confidence: 0.9})
      link!(ctx, %{place_id: other.id, how_resolved: :mention_exact, confidence: 0.9})

      ids =
        ctx.claim.id |> Narrative.list_claim_places!() |> Enum.map(& &1.place_id) |> Enum.sort()

      assert ids == Enum.sort([ctx.place.id, other.id])
    end

    test "re-resolving the same place overwrites how_resolved and confidence — a link is mutable",
         ctx do
      first = link!(ctx, %{how_resolved: :mention_fuzzy, confidence: 0.4})
      again = link!(ctx, %{how_resolved: :mention_exact, confidence: 0.9})

      assert again.id == first.id
      assert again.how_resolved == :mention_exact
      assert again.confidence == 0.9
      assert length(Narrative.list_claim_places!(ctx.claim.id)) == 1
    end

    test "requires how_resolved", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Narrative.link_place(%{
                 claim_id: ctx.claim.id,
                 place_id: ctx.place.id,
                 confidence: 0.9
               })
    end

    test "rejects a Place from another Event", ctx do
      other_place = place!(event!())

      assert {:error, %Ash.Error.Invalid{}} =
               Narrative.link_place(%{
                 claim_id: ctx.claim.id,
                 place_id: other_place.id,
                 how_resolved: :mention_exact,
                 confidence: 0.9
               })
    end
  end

  describe "reads" do
    test "by_claim lists a claim's places in link order", ctx do
      other = place!(ctx.event, %{canonical_name: "Tanaguarena", type: "sector"})
      link!(ctx, %{how_resolved: :mention_exact, confidence: 0.9})
      link!(ctx, %{place_id: other.id, how_resolved: :mention_exact, confidence: 0.9})

      assert Enum.map(Narrative.list_claim_places!(ctx.claim.id), & &1.place_id) ==
               [ctx.place.id, other.id]
    end

    test "by_place lists the claims that happened at a place", ctx do
      link!(ctx, %{how_resolved: :mention_exact, confidence: 0.9})
      assert Enum.map(Narrative.claims_at_place!(ctx.place.id), & &1.claim_id) == [ctx.claim.id]
    end
  end
end
