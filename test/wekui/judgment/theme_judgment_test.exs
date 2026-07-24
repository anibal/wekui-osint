defmodule Wekui.Judgment.ThemeJudgmentTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Judgment

  setup do
    event = event!()
    %{event: event, post: post!(event), theme: theme!(event), agent: agent!(event)}
  end

  defp judge!(ctx, attrs \\ %{}) do
    Judgment.judge_theme!(
      Map.merge(
        %{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          theme_id: ctx.theme.id,
          actor_id: ctx.agent.id,
          confidence: 0.9
        },
        attrs
      )
    )
  end

  describe "judge — recording an answer" do
    test "records that a Post is about a Theme, by an Actor, with a confidence", ctx do
      j = judge!(ctx)

      assert j.event_id == ctx.event.id
      assert j.post_id == ctx.post.id
      assert j.theme_id == ctx.theme.id
      assert j.actor_id == ctx.agent.id
      assert j.confidence == 0.9
      assert %DateTime{} = j.judged_at
      # Born current: no closing timestamp, no successor.
      assert j.superseded_at == nil
      assert j.superseded_by_id == nil
    end

    test "judged_at defaults to now, and can be supplied", ctx do
      default = judge!(ctx)
      assert DateTime.diff(DateTime.utc_now(), default.judged_at, :second) < 5

      supplied = judge!(ctx, %{judged_at: ~U[2026-06-24 22:30:00.000000Z]})
      assert supplied.judged_at == ~U[2026-06-24 22:30:00.000000Z]
    end

    for field <- [:event_id, :post_id, :theme_id, :actor_id] do
      test "requires #{field}", ctx do
        attrs =
          Map.delete(
            %{
              event_id: ctx.event.id,
              post_id: ctx.post.id,
              theme_id: ctx.theme.id,
              actor_id: ctx.agent.id,
              confidence: 0.9
            },
            unquote(field)
          )

        assert {:error, %Ash.Error.Invalid{}} = Judgment.judge_theme(attrs)
      end
    end
  end

  describe "provenance — confidence belongs to agents" do
    test "an agent's judgment requires a confidence", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Judgment.judge_theme(%{
                 event_id: ctx.event.id,
                 post_id: ctx.post.id,
                 theme_id: ctx.theme.id,
                 actor_id: ctx.agent.id
               })
    end

    test "confidence must be between 0 and 1", ctx do
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{confidence: 1.5})
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{confidence: -0.1})
    end
  end

  describe "cross-event integrity — everything agrees on the Event" do
    setup do
      %{other: event!()}
    end

    test "rejects a Post from another Event", ctx do
      other_post = post!(ctx.other)
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{post_id: other_post.id})
    end

    test "rejects a Theme from another Event", ctx do
      other_theme = theme!(ctx.other)
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{theme_id: other_theme.id})
    end

    test "rejects an Actor from another Event", ctx do
      other_agent = agent!(ctx.other)
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{actor_id: other_agent.id})
    end
  end

  describe "only an active Theme can be judged against" do
    test "rejects a proposed Theme", ctx do
      proposed = theme!(ctx.event, %{lifecycle: :proposed})
      assert {:error, %Ash.Error.Invalid{}} = judge_result(ctx, %{theme_id: proposed.id})
    end
  end

  describe "supersession — re-judging closes the old and opens the new" do
    test "the new answer is current and the old is closed and linked to it", ctx do
      first = judge!(ctx, %{confidence: 0.6})
      second = judge!(ctx, %{confidence: 0.95})

      # The return is the new current answer.
      assert second.id != first.id
      assert second.confidence == 0.95
      assert second.superseded_at == nil
      assert second.superseded_by_id == nil

      # The old answer is closed, without editing its content, and points at its successor.
      reloaded = Judgment.get_theme_judgment!(first.id)
      assert reloaded.confidence == 0.6
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == second.id

      # Exactly one current answer remains for the slot.
      assert [current] = Judgment.current_theme_judgments!(ctx.post.id)
      assert current.id == second.id
    end

    test "a Post carries several current Themes at once, one per Theme", ctx do
      t2 = theme!(ctx.event)
      j1 = judge!(ctx)
      j2 = judge!(ctx, %{theme_id: t2.id})

      current = Judgment.current_theme_judgments!(ctx.post.id)
      assert MapSet.new(current, & &1.id) == MapSet.new([j1.id, j2.id])
    end
  end

  describe "retraction — closing an answer with no successor" do
    test "the answer is closed, no successor, and the slot goes back to unjudged", ctx do
      j = judge!(ctx)
      retracted = Judgment.retract_theme_judgment!(j)

      assert retracted.superseded_at != nil
      assert retracted.superseded_by_id == nil
      assert Judgment.current_theme_judgments!(ctx.post.id) == []
    end

    test "retracting one Theme leaves the Post's other Themes current", ctx do
      t2 = theme!(ctx.event)
      j1 = judge!(ctx)
      j2 = judge!(ctx, %{theme_id: t2.id})

      Judgment.retract_theme_judgment!(j1)

      assert [only] = Judgment.current_theme_judgments!(ctx.post.id)
      assert only.id == j2.id
    end

    test "retracting an already-closed answer is refused", ctx do
      j = judge!(ctx)
      Judgment.retract_theme_judgment!(j)

      assert {:error, %Ash.Error.Invalid{}} = Judgment.retract_theme_judgment(j)
    end
  end

  describe "examined-empty — no theme, mutually exclusive with real answers" do
    test "judging 'no theme' records it and retracts every current Theme for the Post", ctx do
      t2 = theme!(ctx.event)
      j1 = judge!(ctx)
      j2 = judge!(ctx, %{theme_id: t2.id})

      none =
        Judgment.judge_theme_none!(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          confidence: 0.8
        })

      assert none.superseded_at == nil
      assert Judgment.current_theme_judgments!(ctx.post.id) == []

      # The Themes are retracted (closed, no successor into the none-row).
      assert Judgment.get_theme_judgment!(j1.id).superseded_at != nil
      assert Judgment.get_theme_judgment!(j1.id).superseded_by_id == nil
      assert Judgment.get_theme_judgment!(j2.id).superseded_at != nil
    end

    test "judging a real Theme retracts the Post's current 'no theme'", ctx do
      none =
        Judgment.judge_theme_none!(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          confidence: 0.8
        })

      judge!(ctx)

      assert Judgment.current_theme_none!(ctx.post.id) == []
      assert reloaded = Judgment.get_theme_none(none.id) |> ok()
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == nil
    end

    test "a Post never has a real Theme and a 'no theme' current at the same time", ctx do
      judge!(ctx)

      Judgment.judge_theme_none!(%{
        event_id: ctx.event.id,
        post_id: ctx.post.id,
        actor_id: ctx.agent.id,
        confidence: 0.8
      })

      assert Judgment.current_theme_judgments!(ctx.post.id) == []
      assert [_one] = Judgment.current_theme_none!(ctx.post.id)
    end

    test "re-examining 'no theme' supersedes the prior one, chaining to it", ctx do
      first =
        Judgment.judge_theme_none!(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          confidence: 0.5
        })

      second =
        Judgment.judge_theme_none!(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          confidence: 0.9
        })

      reloaded = Judgment.get_theme_none(first.id) |> ok()
      assert reloaded.superseded_at != nil
      assert reloaded.superseded_by_id == second.id
      assert [current] = Judgment.current_theme_none!(ctx.post.id)
      assert current.id == second.id
    end
  end

  describe "set replacement — a Post's whole Theme set in one step" do
    test "judges every Theme in the set, from one Actor", ctx do
      [t1, t2, t3] = for _ <- 1..3, do: theme!(ctx.event)

      {:ok, current} =
        Judgment.judge_theme_set(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          theme_ids: [t1.id, t2.id, t3.id],
          confidence: 0.9
        })

      assert MapSet.new(current, & &1.theme_id) == MapSet.new([t1.id, t2.id, t3.id])
      assert Enum.all?(current, &(&1.actor_id == ctx.agent.id and &1.superseded_at == nil))
    end

    test "replacing a set retracts the departed Themes and re-attributes the whole set", ctx do
      [t1, t2, t3, t4] = for _ <- 1..4, do: theme!(ctx.event)

      set!(ctx, [t1, t2, t3], 0.7)

      {:ok, replaced} =
        Judgment.judge_theme_set(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          theme_ids: [t2.id, t3.id, t4.id],
          confidence: 0.95
        })

      # t1 is gone; t2, t3, t4 are the current set.
      assert MapSet.new(replaced, & &1.theme_id) == MapSet.new([t2.id, t3.id, t4.id])
      # The whole current set reads as one coherent answer: the new confidence.
      assert Enum.all?(replaced, &(&1.confidence == 0.95))
      # t1's judgment is closed without a successor.
      assert Enum.empty?(Enum.filter(replaced, &(&1.theme_id == t1.id)))
    end

    test "a set replacement retracts a current 'no theme'", ctx do
      t1 = theme!(ctx.event)

      Judgment.judge_theme_none!(%{
        event_id: ctx.event.id,
        post_id: ctx.post.id,
        actor_id: ctx.agent.id,
        confidence: 0.8
      })

      set!(ctx, [t1], 0.9)

      assert Judgment.current_theme_none!(ctx.post.id) == []
    end

    test "the set may not be empty", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Judgment.judge_theme_set(%{
                 event_id: ctx.event.id,
                 post_id: ctx.post.id,
                 actor_id: ctx.agent.id,
                 theme_ids: [],
                 confidence: 0.9
               })
    end
  end

  describe "set replacement is atomic" do
    test "a failure part-way through rolls the whole replacement back", ctx do
      t1 = theme!(ctx.event)
      t2 = theme!(ctx.event)
      bad = theme!(ctx.event, %{lifecycle: :proposed})

      # Establish a current set of [t1, t2].
      set!(ctx, [t1, t2], 0.7)
      before = Judgment.current_theme_judgments!(ctx.post.id)
      before_ids = MapSet.new(before, & &1.id)
      assert MapSet.new(before, & &1.theme_id) == MapSet.new([t1.id, t2.id])

      # Replace with [t2, bad]: `bad` is :proposed, so its inner judge fails —
      # but only after the run has retracted the departed t1 and re-judged t2.
      assert_raise Ash.Error.Invalid, fn ->
        Judgment.judge_theme_set!(%{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          actor_id: ctx.agent.id,
          theme_ids: [t2.id, bad.id],
          confidence: 0.95
        })
      end

      # The whole replacement rolled back: t1 and t2 are still the current
      # answers, with their original rows, and no row exists for the bad Theme.
      after_replacement = Judgment.current_theme_judgments!(ctx.post.id)
      assert MapSet.new(after_replacement, & &1.id) == before_ids
      refute Enum.any?(Judgment.list_theme_judgments!(ctx.event.id), &(&1.theme_id == bad.id))
    end
  end

  describe "reads" do
    test "current_for_post returns only current answers, oldest first", ctx do
      t2 = theme!(ctx.event)
      j1 = judge!(ctx)
      j2 = judge!(ctx, %{theme_id: t2.id})
      # Supersede j1 — its successor should be the one that reads as current.
      j1b = judge!(ctx)

      current = Judgment.current_theme_judgments!(ctx.post.id)
      assert Enum.map(current, & &1.id) == [j2.id, j1b.id]
      refute j1.id in Enum.map(current, & &1.id)
    end

    test "by_event scopes to one Event", ctx do
      other = event!()
      here = judge!(ctx)

      current = Judgment.list_theme_judgments!(ctx.event.id)
      assert Enum.map(current, & &1.id) == [here.id]
      assert Judgment.list_theme_judgments!(other.id) == []
    end
  end

  # Helpers.

  defp judge_result(ctx, attrs) do
    Judgment.judge_theme(
      Map.merge(
        %{
          event_id: ctx.event.id,
          post_id: ctx.post.id,
          theme_id: ctx.theme.id,
          actor_id: ctx.agent.id,
          confidence: 0.9
        },
        attrs
      )
    )
  end

  defp set!(ctx, themes, confidence) do
    {:ok, current} =
      Judgment.judge_theme_set(%{
        event_id: ctx.event.id,
        post_id: ctx.post.id,
        actor_id: ctx.agent.id,
        theme_ids: Enum.map(themes, & &1.id),
        confidence: confidence
      })

    current
  end

  defp ok({:ok, value}), do: value
end
