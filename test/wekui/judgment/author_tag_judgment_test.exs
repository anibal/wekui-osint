defmodule Wekui.Judgment.AuthorTagJudgmentTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Judgment

  setup do
    event = event!()
    %{event: event, author: author!(event), tag: author_tag!(event), agent: agent!(event)}
  end

  defp judge!(ctx, attrs \\ %{}), do: Judgment.judge_author_tag!(base(ctx, attrs))
  defp judge_result(ctx, attrs), do: Judgment.judge_author_tag(base(ctx, attrs))

  defp base(ctx, attrs) do
    Map.merge(
      %{
        event_id: ctx.event.id,
        author_id: ctx.author.id,
        tag_id: ctx.tag.id,
        actor_id: ctx.agent.id,
        confidence: 0.85
      },
      attrs
    )
  end

  defp none!(ctx) do
    Judgment.judge_author_tag_none!(%{
      event_id: ctx.event.id,
      author_id: ctx.author.id,
      actor_id: ctx.agent.id,
      confidence: 0.8
    })
  end

  defp ok({:ok, value}), do: value

  describe "judge — recording an answer" do
    test "records that an Author carries a Tag, by an Actor, with a confidence", ctx do
      j = judge!(ctx)

      assert j.event_id == ctx.event.id
      assert j.author_id == ctx.author.id
      assert j.tag_id == ctx.tag.id
      assert j.actor_id == ctx.agent.id
      assert j.confidence == 0.85
      assert j.superseded_at == nil
      assert j.superseded_by_id == nil
    end

    for field <- [:event_id, :author_id, :tag_id, :actor_id] do
      test "requires #{field}", ctx do
        assert {:error, %Ash.Error.Invalid{}} =
                 Judgment.judge_author_tag(Map.delete(base(ctx, %{}), unquote(field)))
      end
    end
  end

  describe "provenance — confidence belongs to agents" do
    test "an agent's judgment requires a confidence", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Judgment.judge_author_tag(Map.delete(base(ctx, %{}), :confidence))
    end

    test "confidence must be between 0 and 1", ctx do
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{confidence: 1.5})
    end
  end

  describe "cross-event integrity and active-Tag gate" do
    setup do
      %{other: event!()}
    end

    test "rejects an Author from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               judge_result(ctx, %{author_id: author!(ctx.other).id})
    end

    test "rejects a Tag from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               judge_result(ctx, %{tag_id: author_tag!(ctx.other).id})
    end

    test "rejects an Actor from another Event", ctx do
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{actor_id: agent!(ctx.other).id})
    end

    test "rejects a proposed Tag", ctx do
      proposed = author_tag!(ctx.event, %{lifecycle: :proposed})
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{tag_id: proposed.id})
    end
  end

  describe "supersession and multi-current" do
    test "re-judging closes the old, links it, and leaves one current per slot", ctx do
      first = judge!(ctx, %{confidence: 0.6})
      second = judge!(ctx, %{confidence: 0.95})

      assert second.id != first.id
      assert second.superseded_at == nil

      reloaded = Judgment.get_author_tag_judgment!(first.id)
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == second.id

      assert [current] = Judgment.current_author_tag_judgments!(ctx.author.id)
      assert current.id == second.id
    end

    test "an Author carries several current Tags at once, one per Tag", ctx do
      t2 = author_tag!(ctx.event)
      j1 = judge!(ctx)
      j2 = judge!(ctx, %{tag_id: t2.id})

      current = Judgment.current_author_tag_judgments!(ctx.author.id)
      assert MapSet.new(current, & &1.id) == MapSet.new([j1.id, j2.id])
    end
  end

  describe "retraction" do
    test "closes without a successor and returns the slot to untagged", ctx do
      j = judge!(ctx)
      retracted = Judgment.retract_author_tag_judgment!(j)

      assert retracted.superseded_at != nil
      assert retracted.superseded_by_id == nil
      assert Judgment.current_author_tag_judgments!(ctx.author.id) == []
    end

    test "refuses to retract an already-closed answer", ctx do
      j = judge!(ctx)
      Judgment.retract_author_tag_judgment!(j)
      assert {:error, %Ash.Error.Invalid{}} = Judgment.retract_author_tag_judgment(j)
    end
  end

  describe "examined-empty — no tag, mutually exclusive with real answers" do
    test "'no tag' retracts every current Tag for the Author", ctx do
      t2 = author_tag!(ctx.event)
      judge!(ctx)
      judge!(ctx, %{tag_id: t2.id})

      none = none!(ctx)

      assert none.superseded_at == nil
      assert Judgment.current_author_tag_judgments!(ctx.author.id) == []
    end

    test "judging a real Tag retracts the Author's current 'no tag'", ctx do
      none = none!(ctx)
      judge!(ctx)

      assert Judgment.current_author_tag_none!(ctx.author.id) == []
      reloaded = Judgment.get_author_tag_none(none.id) |> ok()
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == nil
    end

    test "an Author never has a real Tag and a 'no tag' current at once", ctx do
      judge!(ctx)
      none!(ctx)

      assert Judgment.current_author_tag_judgments!(ctx.author.id) == []
      assert [_one] = Judgment.current_author_tag_none!(ctx.author.id)
    end
  end

  describe "set replacement" do
    test "judges every Tag in the set and retracts the departed ones, from one Actor", ctx do
      [t1, t2, t3, t4] = for _ <- 1..4, do: author_tag!(ctx.event)

      {:ok, _} = set(ctx, [t1, t2, t3], 0.7)
      {:ok, replaced} = set(ctx, [t2, t3, t4], 0.95)

      assert MapSet.new(replaced, & &1.tag_id) == MapSet.new([t2.id, t3.id, t4.id])
      assert Enum.all?(replaced, &(&1.confidence == 0.95))
    end

    test "a failure part-way through rolls the whole replacement back", ctx do
      t1 = author_tag!(ctx.event)
      t2 = author_tag!(ctx.event)
      bad = author_tag!(ctx.event, %{lifecycle: :proposed})

      {:ok, _} = set(ctx, [t1, t2], 0.7)
      before_ids = MapSet.new(Judgment.current_author_tag_judgments!(ctx.author.id), & &1.id)

      assert_raise Ash.Error.Invalid, fn ->
        Judgment.judge_author_tag_set!(%{
          event_id: ctx.event.id,
          author_id: ctx.author.id,
          actor_id: ctx.agent.id,
          tag_ids: [t2.id, bad.id],
          confidence: 0.95
        })
      end

      after_ids = MapSet.new(Judgment.current_author_tag_judgments!(ctx.author.id), & &1.id)
      assert after_ids == before_ids
    end

    test "the set may not be empty", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Judgment.judge_author_tag_set(%{
                 event_id: ctx.event.id,
                 author_id: ctx.author.id,
                 actor_id: ctx.agent.id,
                 tag_ids: [],
                 confidence: 0.9
               })
    end
  end

  describe "reads" do
    test "by_event scopes to one Event", ctx do
      other = event!()
      here = judge!(ctx)

      assert Enum.map(Judgment.list_author_tag_judgments!(ctx.event.id), & &1.id) == [here.id]
      assert Judgment.list_author_tag_judgments!(other.id) == []
    end
  end

  defp set(ctx, tags, confidence) do
    Judgment.judge_author_tag_set(%{
      event_id: ctx.event.id,
      author_id: ctx.author.id,
      actor_id: ctx.agent.id,
      tag_ids: Enum.map(tags, & &1.id),
      confidence: confidence
    })
  end
end
