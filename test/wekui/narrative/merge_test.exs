defmodule Wekui.Narrative.MergeTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.Merge

  setup do
    event = event!()

    %{
      event: event,
      place: place!(event),
      agent: agent!(event),
      p1: post!(event),
      p2: post!(event)
    }
  end

  defp claim!(ctx, first_seen_at, attrs \\ %{}) do
    Narrative.draft_claim!(
      Map.merge(
        %{
          event_id: ctx.event.id,
          kind: "rescate",
          subject: "un hombre de 21 años",
          first_seen_at: first_seen_at,
          place_id: ctx.place.id,
          actor_id: ctx.agent.id,
          confidence: 0.9
        },
        attrs
      )
    )
  end

  describe "merge — one claim per happening" do
    test "folds the later account into the earlier; the earlier is canonical", ctx do
      early = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      late = claim!(ctx, ~U[2026-06-25 04:00:00.000000Z])

      {:ok, canonical} = Merge.merge(late, early)

      assert canonical.id == early.id
      assert canonical.superseded_at == nil

      folded = Narrative.get_claim!(late.id)
      assert folded.superseded_at != nil
      assert folded.superseded_by_id == early.id
    end

    test "picks the earlier occurrence regardless of argument order", ctx do
      early = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      late = claim!(ctx, ~U[2026-06-25 04:00:00.000000Z])

      {:ok, canonical} = Merge.merge(early, late)
      assert canonical.id == early.id
    end

    test "the canonical absorbs the duplicate's citations, deduped", ctx do
      early = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      late = claim!(ctx, ~U[2026-06-25 04:00:00.000000Z])
      Narrative.cite_post!(%{claim_id: early.id, post_id: ctx.p1.id})
      Narrative.cite_post!(%{claim_id: late.id, post_id: ctx.p1.id})
      Narrative.cite_post!(%{claim_id: late.id, post_id: ctx.p2.id})

      {:ok, canonical} = Merge.merge(early, late)

      post_ids =
        canonical.id
        |> Narrative.list_claim_citations!()
        |> Enum.map(& &1.post_id)
        |> Enum.sort()

      assert post_ids == Enum.sort([ctx.p1.id, ctx.p2.id])
    end
  end

  describe "merge refusals" do
    test "a claim cannot merge with itself", ctx do
      c = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      assert Merge.merge(c, c) == {:error, :same_claim}
    end

    test "claims of different Events cannot merge", ctx do
      here = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      other = event!()

      there =
        Narrative.draft_claim!(%{
          event_id: other.id,
          kind: "rescate",
          first_seen_at: ~U[2026-06-25 02:00:00.000000Z],
          actor_id: agent!(other).id,
          confidence: 0.9
        })

      assert Merge.merge(here, there) == {:error, :different_events}
    end

    test "an already-superseded claim cannot merge", ctx do
      a = claim!(ctx, ~U[2026-06-25 02:00:00.000000Z])
      b = claim!(ctx, ~U[2026-06-25 04:00:00.000000Z])
      Narrative.retract_claim!(b)

      assert Merge.merge(a, b) == {:error, :not_current}
    end
  end
end
