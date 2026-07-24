defmodule Wekui.Judgment.PlacementTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Judgment
  alias Wekui.Judgment.Where

  setup do
    event = event!()
    %{event: event, post: post!(event), place: place!(event), agent: agent!(event)}
  end

  defp place_at!(ctx, place \\ nil, attrs \\ %{})

  defp place_at!(ctx, nil, attrs),
    do: Judgment.place_post!(placement_attrs(ctx, ctx.place, attrs))

  defp place_at!(ctx, place, attrs), do: Judgment.place_post!(placement_attrs(ctx, place, attrs))

  defp place_result(ctx, place, attrs),
    do: Judgment.place_post(placement_attrs(ctx, place, attrs))

  defp placement_attrs(ctx, place, attrs) do
    Map.merge(
      %{
        event_id: ctx.event.id,
        post_id: ctx.post.id,
        place_id: place.id,
        actor_id: ctx.agent.id,
        confidence: 0.9
      },
      attrs
    )
  end

  defp no_place!(ctx) do
    Judgment.judge_no_place!(%{
      event_id: ctx.event.id,
      post_id: ctx.post.id,
      actor_id: ctx.agent.id,
      confidence: 0.8
    })
  end

  describe "place — recording where a Post is about" do
    test "records the placement: Post, Place, Actor, confidence, current", ctx do
      p = place_at!(ctx)

      assert p.event_id == ctx.event.id
      assert p.post_id == ctx.post.id
      assert p.place_id == ctx.place.id
      assert p.actor_id == ctx.agent.id
      assert p.confidence == 0.9
      assert p.superseded_at == nil
    end

    for field <- [:event_id, :post_id, :place_id, :actor_id] do
      test "requires #{field}", ctx do
        assert {:error, %Ash.Error.Invalid{}} =
                 Judgment.place_post(
                   Map.delete(placement_attrs(ctx, ctx.place, %{}), unquote(field))
                 )
      end
    end

    test "an agent's placement requires a confidence", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Judgment.place_post(Map.delete(placement_attrs(ctx, ctx.place, %{}), :confidence))
    end
  end

  describe "a placement target must belong to the Event, and cannot be Unplaced" do
    setup do
      %{other: event!()}
    end

    test "rejects a Place from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} = place_result(ctx, place!(ctx.other), %{})
    end

    test "rejects an Actor from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               place_result(ctx, ctx.place, %{actor_id: agent!(ctx.other).id})
    end

    test "a proposed Place is a valid (provisional) target", ctx do
      proposed = place!(ctx.event, %{lifecycle: :proposed})
      assert %{} = place_at!(ctx, proposed)
    end

    test "the Unplaced Place is refused — Unplaced is the default, not an answer", ctx do
      unplaced_id = Core.get_event!(ctx.event.id).unplaced_place_id
      assert {:error, %Ash.Error.Invalid{}} = place_result(ctx, %{id: unplaced_id}, %{})
    end
  end

  describe "supersession and retraction" do
    test "re-placing supersedes: one current placement, old closed and linked", ctx do
      elsewhere = place!(ctx.event)
      first = place_at!(ctx)
      second = place_at!(ctx, elsewhere)

      assert second.place_id == elsewhere.id
      reloaded = Judgment.get_placement!(first.id)
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == second.id

      assert [%{id: id}] = Judgment.current_placement!(ctx.post.id)
      assert id == second.id
    end

    test "retraction closes without a successor, returning the Post to Unplaced", ctx do
      p = place_at!(ctx)
      Judgment.retract_placement!(p)

      assert Judgment.current_placement!(ctx.post.id) == []
      assert {:unplaced, _} = Where.of(ctx.post.id)
    end
  end

  describe "No place — mutually exclusive with a real placement" do
    test "placing retracts a current No place", ctx do
      none = no_place!(ctx)
      place_at!(ctx)

      assert Judgment.current_no_place!(ctx.post.id) == []
      assert Judgment.get_no_place!(none.id).superseded_at != nil
    end

    test "judging No place retracts the current placement", ctx do
      p = place_at!(ctx)
      no_place!(ctx)

      assert Judgment.current_placement!(ctx.post.id) == []
      assert Judgment.get_placement!(p.id).superseded_at != nil
    end
  end

  describe "Where.of — the derived read, following one chain" do
    test "nothing judged reads as Unplaced (the Event's Unplaced Place)", ctx do
      unplaced_id = Core.get_event!(ctx.event.id).unplaced_place_id
      assert {:unplaced, unplaced} = Where.of(ctx.post.id)
      assert unplaced.id == unplaced_id
    end

    test "an active Place reads as itself", ctx do
      place_at!(ctx)
      assert {:place, place} = Where.of(ctx.post.id)
      assert place.id == ctx.place.id
    end

    test "a proposed Place reads as itself", ctx do
      proposed = place!(ctx.event, %{lifecycle: :proposed})
      place_at!(ctx, proposed)
      assert {:place, place} = Where.of(ctx.post.id)
      assert place.id == proposed.id
    end

    test "a No place reads as :no_place", ctx do
      no_place!(ctx)
      assert Where.of(ctx.post.id) == :no_place
    end

    test "a placement at a deprecated Place reads as its replacement", ctx do
      replacement = place!(ctx.event)
      place_at!(ctx)
      Core.deprecate_place!(ctx.place, %{replaced_by_id: replacement.id})

      assert {:place, place} = Where.of(ctx.post.id)
      assert place.id == replacement.id
    end

    test "a deprecation chain is followed to the end", ctx do
      b = place!(ctx.event)
      c = place!(ctx.event)
      place_at!(ctx)
      Core.deprecate_place!(ctx.place, %{replaced_by_id: b.id})
      Core.deprecate_place!(b, %{replaced_by_id: c.id})

      assert {:place, place} = Where.of(ctx.post.id)
      assert place.id == c.id
    end

    test "a placement at a discarded Place reads as Unplaced", ctx do
      place_at!(ctx)
      Core.discard_place!(ctx.place, %{note: "not a real place"})

      assert {:unplaced, _} = Where.of(ctx.post.id)
    end
  end

  describe "reads" do
    test "by_event scopes placements to one Event", ctx do
      other = event!()
      here = place_at!(ctx)

      assert Enum.map(Judgment.list_placements!(ctx.event.id), & &1.id) == [here.id]
      assert Judgment.list_placements!(other.id) == []
    end
  end
end
