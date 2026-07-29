defmodule Wekui.Pipelines.ExtractTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Pipelines.Extract

  setup do
    event = event!()
    agent = agent!(event, %{prompt: "Extract from:\n{{material}}"})
    p1 = post!(event, %{x_id: "111", text: "rescate en Caraballeda"})
    p2 = post!(event, %{x_id: "222", text: "chatter irrelevante"})

    # The ratified vocabulary. A claim the model cannot file under one of these is not
    # written at all — it belongs in `unfitted`, where a person decides whether the
    # vocabulary should grow.
    rescate =
      theme!(event, %{
        name: "Persona rescatada con vida",
        applies_when: "the post asserts a named person was pulled out alive",
        nature: :happening
      })

    %{event: event, agent: agent, p1: p1, p2: p2, rescate: rescate}
  end

  defp stub_claims(claims) do
    content = Jason.encode!(%{"claims" => claims})

    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
    end)
  end

  test "writes claims, evidence, and persons from the worker's output", ctx do
    stub_claims([
      %{
        "theme" => "Persona rescatada con vida",
        "kind" => "rescate",
        "subject_role" => "un hombre de 21 años",
        "names" => ["Aaron Levi Cantillo Vargas"],
        "place_mention" => "edificio OPP 25",
        "magnitude" => %{"horas" => 106},
        "status" => "atrapado",
        "citations" => ["111"],
        "confidence" => 0.9
      }
    ])

    assert {:ok, %{drafted: 1, skipped: 0}} =
             Extract.run(ctx.event, ctx.agent, [ctx.p1, ctx.p2], place_scope: "Caraballeda")

    assert [claim] = Narrative.list_claims!(ctx.event.id)
    assert claim.kind == "rescate"
    assert claim.subject == "un hombre de 21 años"
    assert claim.place_mention == "edificio OPP 25"
    assert claim.magnitude == %{"horas" => 106}
    assert claim.status == "atrapado"
    assert claim.first_seen_at == ctx.p1.posted_at
    assert claim.actor_id == ctx.agent.id

    assert [citation] = Narrative.list_claim_citations!(claim.id)
    assert citation.post_id == ctx.p1.id

    assert [person] = Narrative.list_persons!(ctx.event.id)
    assert person.full_name == "Aaron Levi Cantillo Vargas"
    assert person.display_handle == "Aaron C."
    assert [link] = Narrative.list_claim_persons!(claim.id)
    assert link.person_id == person.id
  end

  test "a claim whose subject slips a private name is refused by the gate", ctx do
    stub_claims([
      %{
        "kind" => "rescate",
        "subject_role" => "Belkys Josefina Barreto García",
        "names" => [],
        "citations" => ["111"],
        "confidence" => 0.8
      }
    ])

    assert {:ok, %{drafted: 0, skipped: 1}} = Extract.run(ctx.event, ctx.agent, [ctx.p1])
    assert Narrative.list_claims!(ctx.event.id) == []
  end

  test "a claim citing nothing in the batch is skipped", ctx do
    stub_claims([
      %{
        "kind" => "colapso",
        "subject_role" => nil,
        "names" => [],
        "citations" => ["999"],
        "confidence" => 0.7
      }
    ])

    assert {:ok, %{drafted: 0, skipped: 1, skips: [:no_valid_citations]}} =
             Extract.run(ctx.event, ctx.agent, [ctx.p1])
  end

  test "tolerates a fenced JSON response", ctx do
    content = "```json\n" <> Jason.encode!(%{"claims" => []}) <> "\n```"

    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
    end)

    assert {:ok, %{claims: 0, drafted: 0}} = Extract.run(ctx.event, ctx.agent, [ctx.p1])
  end

  # Both of these were shipped and caught on the record within one turn. They are
  # tested by name because the failure mode is silent.
  describe "the vocabulary is the refusal" do
    test "a happening the vocabulary cannot name is not written as a claim", ctx do
      stub_claims([
        %{
          "theme" => "Saqueo de un comercio",
          "kind" => "saqueo",
          "citations" => ["111"],
          "confidence" => 0.8
        }
      ])

      assert {:ok, %{drafted: 0, skipped: 1, skips: [{:no_theme, "Saqueo de un comercio"}]}} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "Caraballeda")

      assert Narrative.list_claims!(ctx.event.id) == []
    end

    test "a private name in `kind` is refused — a gate protects the fields it knows", ctx do
      # The prompt invited a short phrase instead of a type word and the model wrote
      # "Sonia Carolina Muñoz Martínez desaparecida en Edificio Coral Suites" into
      # `kind`, twenty times. `kind` was outside the red line while it held one word.
      stub_claims([
        %{
          "theme" => "Persona rescatada con vida",
          "kind" => "Aaron Levi Cantillo Vargas rescatado en OPP 25",
          "citations" => ["111"],
          "confidence" => 0.9
        }
      ])

      assert {:ok, %{drafted: 0, skipped: 1}} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "Caraballeda")

      assert Narrative.list_claims!(ctx.event.id) == []
    end

    test "every post is accounted for: cited, unfitted, or read and dropped", ctx do
      content =
        Jason.encode!(%{
          "claims" => [
            %{
              "theme" => "Persona rescatada con vida",
              "kind" => "rescate",
              "citations" => ["111"],
              "confidence" => 0.9
            }
          ],
          "unfitted" => [%{"what_happened" => "un saqueo", "citations" => ["222"]}]
        })

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
      end)

      assert {:ok, summary} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1, ctx.p2], place_scope: "Caraballeda")

      # A post that fit nothing used to vanish, and a silence is not auditable.
      assert summary.posts == 2
      assert summary.cited == 1
      assert summary.unread == 1
      assert summary.unfitted == ["un saqueo"]
    end
  end
end
