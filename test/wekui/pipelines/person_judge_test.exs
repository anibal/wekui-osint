defmodule Wekui.Pipelines.PersonJudgeTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Narrative.PersonDuplicates
  alias Wekui.Pipelines.PersonJudge

  setup do
    event = event!()

    %{
      event: event,
      agent: agent!(event),
      caribe: place!(event, %{canonical_name: "Residencias Caribe", type: "edificio"})
    }
  end

  defp person!(ctx, full_name) do
    Narrative.identify_person!(%{event_id: ctx.event.id, full_name: full_name})
  end

  defp claim!(ctx, people) do
    claim =
      Narrative.draft_claim!(%{
        event_id: ctx.event.id,
        kind: "persona desaparecida",
        subject: "personas en Edif. Costa Brava",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: ctx.agent.id,
        confidence: 0.9
      })

    Narrative.link_place!(%{
      claim_id: claim.id,
      place_id: ctx.caribe.id,
      how_resolved: :mention_exact,
      confidence: 0.9
    })

    for one <- people, do: Narrative.link_person!(%{claim_id: claim.id, person_id: one.id})
    claim
  end

  defp stub(groups) do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(%{"groups" => groups})}}]
      })
    end)
  end

  defp names(ctx) do
    ctx.event.id |> Narrative.current_persons!() |> Enum.map(& &1.full_name) |> Enum.sort()
  end

  # Rung 1. This is in code and not in the prompt for a measured reason: told in its own
  # text that "Belkis and Belkys are one name", the model split them anyway in every run,
  # because the family rule beside it outranked the spelling rule.
  describe "what position settles without asking anything" do
    test "the everyday form folds into the disaster form, and no model is called", ctx do
      # No stub at all: a call would raise, so this proves nothing was asked.
      person!(ctx, "Belkys Barreto")
      person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)

      assert run.summary["position"] == 1
      assert run.summary["judged"] == 0
      assert run.summary["merged"] == 1
      assert names(ctx) == ["Belkys Josefina Barreto García"]
    end

    test "four rows of one woman collapse to one", ctx do
      for name <- [
            "Belkys Josefina Barreto García",
            "Belkis Josefina Barreto García",
            "Belkys Barreto",
            "Belkis Barreto"
          ] do
        person!(ctx, name)
      end

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["merged"] >= 3
      assert names(ctx) == ["Belkys Josefina Barreto García"]
    end
  end

  # Rung 5, and only for what position cannot settle.
  describe "what the model is asked" do
    test "a block position cannot settle goes to the model", ctx do
      person!(ctx, "Belkys Josefina Barreto García")
      beky = person!(ctx, "Beky Barreto")
      claim!(ctx, [beky])

      # The model is told they are one woman; position could not say so.
      stub([%{"same" => [1, 2], "why" => "Beky is short for Belkys"}])

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["judged"] >= 1
    end

    test "the model's refusal to group leaves both rows standing", ctx do
      person!(ctx, "Belkys Josefina Barreto García")
      beky = person!(ctx, "Beky Barreto")
      claim!(ctx, [beky])

      stub([])

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["merged"] == 0
      assert length(names(ctx)) == 2
    end

    test "an unreadable answer merges nothing and is counted as refused", ctx do
      person!(ctx, "Belkys Josefina Barreto García")
      beky = person!(ctx, "Beky Barreto")
      claim!(ctx, [beky])

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "no soy JSON"}}]})
      end)

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["refused"] == 1
      assert run.summary["merged"] == 0
      assert length(names(ctx)) == 2
    end

    test "a group naming one person alone merges nothing", ctx do
      person!(ctx, "Belkys Josefina Barreto García")
      beky = person!(ctx, "Beky Barreto")
      claim!(ctx, [beky])

      stub([%{"same" => [1], "why" => "only one"}])

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["merged"] == 0
    end
  end

  describe "the receipt it leaves" do
    test "is a run, not a curation act — a machine never curates", ctx do
      person!(ctx, "Belkys Barreto")
      person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)

      assert run.kind == :person_judge
      assert run.status == :completed
      assert run.actor_id == ctx.agent.id
      assert Wekui.Curation.list_acts!(ctx.event.id) == []
    end

    test "names both rows and why they were folded", ctx do
      person!(ctx, "Belkys Barreto")
      person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)

      assert [[kept, gone, why]] = run.summary["folds"]
      assert kept == "Belkys Josefina Barreto García"
      assert gone == "Belkys Barreto"
      assert why =~ "first name"
    end

    test "a dry run judges and folds nothing", ctx do
      person!(ctx, "Belkys Barreto")
      person!(ctx, "Belkys Josefina Barreto García")

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent, dry: true)

      assert run.summary["position"] == 1
      assert run.summary["merged"] == 0
      assert length(names(ctx)) == 2
    end
  end

  # Blocks overlap on purpose, so one fold can make another one moot. A fold that no
  # longer applies is skipped, never forced.
  describe "when the blocks overlap" do
    test "a row folded by an earlier block does not break a later one", ctx do
      for name <- ["Belkys Josefina Barreto García", "Belkys Barreto", "Belkis Barreto"] do
        person!(ctx, name)
      end

      assert {:ok, _run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert names(ctx) == ["Belkys Josefina Barreto García"]
    end
  end

  describe "what it does not do" do
    test "nothing at all when there is nobody to compare", ctx do
      person!(ctx, "Gladismaria Pineda Ramirez")
      person!(ctx, "Mirta Guedez")

      assert PersonDuplicates.find(ctx.event.id) == []
      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["merged"] == 0
      assert length(names(ctx)) == 2
    end

    # Two sisters carry BOTH surnames identically, and they are in one claim together —
    # which the prompt reads as evidence they are different, not the same.
    test "position never folds two sisters", ctx do
      one = person!(ctx, "Valentina Juliette Azocar Milano")
      other = person!(ctx, "Victoria Antonela Azocar Milano")
      claim!(ctx, [one, other])

      stub([])

      assert {:ok, run} = PersonJudge.sweep(ctx.event, ctx.agent)
      assert run.summary["position"] == 0
      assert length(names(ctx)) == 2
    end
  end
end
