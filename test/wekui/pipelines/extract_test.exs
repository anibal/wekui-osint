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

    # A TOPIC, so the pipeline can tell a routed plea from a mis-routed happening.
    theme!(event, %{
      name: "Solicitud de información",
      applies_when: "the post asks whether anyone has news and asserts nothing itself",
      nature: :topic
    })

    %{event: event, agent: agent, p1: p1, p2: p2, rescate: rescate}
  end

  # The prompt as the model actually receives it.
  defp capture_prompt(ctx, claims) do
    me = self()

    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        me,
        {:prompt, body |> Jason.decode!() |> get_in(["messages", Access.at(0), "content"])}
      )

      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(%{"claims" => claims})}}]
      })
    end)

    with_vocabulary =
      agent!(ctx.event, %{prompt: "Vocabulary:\n{{vocabulary}}\nMaterial:\n{{material}}"})

    _ = Extract.run(ctx.event, with_vocabulary, [ctx.p1], place_scope: "Caraballeda")
    receive do: ({:prompt, p} -> p), after: (1000 -> flunk("no prompt captured"))
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

    assert {:ok, %{drafted: 0, skipped: 1, skips: [{:no_valid_citations, _}]}} =
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

    test "a plea has a home, so the model is not tempted to make it a claim", ctx do
      # v8 listed the TOPICS in the same shape as the happenings and told the model a
      # topic post "needs no entry anywhere". It duly filed ten claims under
      # «Solicitud de información», which the write path refused. Models are bad at
      # doing nothing; give the plea somewhere to go.
      content =
        Jason.encode!(%{
          "claims" => [],
          "topics" => [
            %{"topic" => "Solicitud de información", "citations" => ["111"]},
            %{"topic" => "Solicitud de información", "citations" => ["222"]}
          ]
        })

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
      end)

      assert {:ok, summary} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1, ctx.p2], place_scope: "Caraballeda")

      assert summary.drafted == 0
      assert summary.topics == %{"Solicitud de información" => 2}
      assert summary.misrouted_topics == %{}

      # AND IT LEAVES A RECORD. Routing used to live only inside this summary, so the
      # record could not say what became of a post that was read and correctly
      # produced no claim. "Every post is accounted for" was true per run and lost
      # immediately after, which is not accounted for.
      assert summary.judged == 2

      for post <- [ctx.p1, ctx.p2] do
        assert [judgment] = Wekui.Judgment.current_theme_judgments!(post.id)
        assert judgment.theme_id
      end

      # Both posts are accounted for by the topics list — routed, not lost.
      assert summary.unread == 0
      assert Narrative.list_claims!(ctx.event.id) == []
    end

    test "a HAPPENING named in the topics list is a lost claim, and it is counted", ctx do
      # The model recognised something real and declined to claim it. That is not a
      # topic; it is a claim that got away, and it is invisible unless counted.
      content =
        Jason.encode!(%{
          "claims" => [],
          "topics" => [%{"topic" => "Persona rescatada con vida", "citations" => ["111"]}]
        })

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
      end)

      assert {:ok, summary} = Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "C")

      assert summary.topics == %{}
      assert summary.misrouted_topics == %{"Persona rescatada con vida" => 1}
    end

    test "the vocabulary reaches the model grouped by family, not as a flat list", ctx do
      # At 17 themes a flat list was fine. At 40 the model stopped finding words that
      # were plainly there — roughly ten of twenty-six residue entries named a
      # happening the vocabulary already had. A residue entry the vocabulary can
      # already answer is worse than a gap: it asks a person for a word that exists.
      family =
        theme!(ctx.event, %{
          name: "Personas afectadas",
          applies_when: "never classify against this node directly",
          nature: :topic
        })

      theme!(ctx.event, %{
        name: "Persona atrapada",
        applies_when: "the post asserts a person is trapped alive",
        nature: :happening,
        parent_id: family.id
      })

      prompt = capture_prompt(ctx, [])

      assert prompt =~ "PERSONAS AFECTADAS"
      # The child sits under its family heading, not loose among forty siblings.
      assert prompt =~ ~r/PERSONAS AFECTADAS\n- «Persona atrapada»/
    end

    test "an id copied with its label still finds its post", ctx do
      # The material renders `[id 2071059613336949047] …` and the model copies the
      # label with the number. Two whole batches — about fifty claims — were dropped
      # this way before the skip reason said what had actually been cited.
      stub_claims([
        %{
          "theme" => "Persona rescatada con vida",
          "kind" => "rescate",
          "citations" => ["id 111"],
          "confidence" => 0.9
        }
      ])

      assert {:ok, %{drafted: 1, skipped: 0}} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "Caraballeda")
    end

    test "a citation that matches nothing still refuses, and says what it cited", ctx do
      stub_claims([
        %{
          "theme" => "Persona rescatada con vida",
          "kind" => "rescate",
          "citations" => ["9999"],
          "confidence" => 0.9
        }
      ])

      assert {:ok, %{drafted: 0, skipped: 1, skips: [{:no_valid_citations, ["9999"]}]}} =
               Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "Caraballeda")
    end

    test "a topic put in the wrong field is routed, not lost", ctx do
      # Measured on 2026-06-28: a batch dominated by resource requests, and the model
      # put a topic name in "theme" eight times out of twenty-four. The rule holds on
      # a mixed batch and slips on a lopsided one. Refusing loses the post; the intent
      # was unambiguous, so route it — and count how often it arrived that way.
      content =
        Jason.encode!(%{
          "claims" => [
            %{"theme" => "Solicitud de información", "kind" => "pedido", "citations" => ["111"]}
          ]
        })

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
      end)

      assert {:ok, summary} = Extract.run(ctx.event, ctx.agent, [ctx.p1], place_scope: "C")

      assert summary.drafted == 0
      assert summary.skipped == 0
      assert summary.topics == %{"Solicitud de información" => 1}
      assert summary.routed_from_theme == %{"Solicitud de información" => 1}
      assert Narrative.list_claims!(ctx.event.id) == []

      # ITS POSTS COME WITH IT. An earlier version kept only the name and threw the
      # citations away, so the post left no judgment and no accounting — and every
      # sweep read it again, and the one after that.
      assert summary.unread == 0
      assert summary.judged == 1
      assert [_judgment] = Wekui.Judgment.current_theme_judgments!(ctx.p1.id)
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

      # A post that fit nothing used to vanish, and a silence is not auditable. All
      # three lists carry citations, so all three count as accounted for.
      assert summary.posts == 2
      assert summary.cited == 1
      assert summary.unfitted == ["un saqueo"]
      assert summary.unread == 0
    end
  end
end
