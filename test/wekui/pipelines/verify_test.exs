defmodule Wekui.Pipelines.VerifyTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Pipelines.Verify

  setup do
    event = event!()
    agent = agent!(event)
    post = post!(event, %{text: "rescataron con vida a un hombre en Caraballeda"})

    theme =
      theme!(event, %{
        name: "Persona rescatada con vida",
        applies_when:
          "The post asserts the extraction itself — that the person was brought out alive."
      })

    claim =
      Narrative.draft_claim!(%{
        event_id: event.id,
        kind: "rescate",
        subject: "un hombre",
        first_seen_at: ~U[2026-06-25 04:00:00.000000Z],
        actor_id: agent.id,
        confidence: 0.8
      })

    Narrative.cite_post!(%{claim_id: claim.id, post_id: post.id})

    # A claim's kind IS a ratified theme (`decision-2026-07-29-a-claim-carries-a-ratified-theme`),
    # so the fixture carries one. The themeless case is its own describe block below.
    %{
      event: event,
      theme: theme,
      untethered: claim,
      claim: Narrative.file_claim_under_theme!(claim, %{theme_id: theme.id})
    }
  end

  defp stub(verdict, note) do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{"message" => %{"content" => Jason.encode!(%{"verdict" => verdict, "note" => note})}}
        ]
      })
    end)
  end

  test "a claim starts unverified", %{claim: claim} do
    assert claim.support == :unverified
  end

  test "records a supported verdict with its note", %{claim: claim} do
    stub("supported", "el post reporta el rescate del hombre")
    assert {:ok, verified} = Verify.run(claim)
    assert verified.support == :supported
    assert verified.support_note =~ "rescate"
  end

  test "records an unsupported verdict", %{claim: claim} do
    stub("unsupported", "el post no menciona a esta persona")
    assert {:ok, verified} = Verify.run(claim)
    assert verified.support == :unsupported
  end

  test "tolerates a fenced verdict", %{claim: claim} do
    fenced =
      "```json\n" <>
        Jason.encode!(%{"verdict" => "overstated", "note" => "el estado no consta"}) <> "\n```"

    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => fenced}}]})
    end)

    assert {:ok, verified} = Verify.run(claim)
    assert verified.support == :overstated
  end

  # Until v2 the gate was handed `kind` — the extractor's own note, which the extraction
  # prompt calls "a note on how the post read" that "nothing is filed by" — while the
  # ratified rule that decides whether the happening applies sat unread. It reached the
  # right answer on a plea read as a search by reasoning from the word "búsqueda", which
  # is not in the vocabulary at all.
  describe "the rule the gate judges against" do
    defp asked(claim) do
      {:ok, sent} = Agent.start_link(fn -> nil end)

      Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Agent.update(sent, fn _none -> body end)

        Req.Test.json(conn, %{
          "choices" => [
            %{"message" => %{"content" => ~s({"verdict":"supported","note":""})}}
          ]
        })
      end)

      assert {:ok, _verified} = Verify.run(claim)
      Agent.get(sent, & &1)
    end

    test "is the theme's own applies_when, not the extractor's note", ctx do
      body = asked(ctx.claim)

      assert body =~ "Persona rescatada con vida"
      assert body =~ "the person was brought out alive"
      # And the extractor's note is passed, but stripped of authority.
      assert body =~ "carries NO authority"
    end

    test "leaves no placeholder unfilled", ctx do
      refute asked(ctx.claim) =~ "{{"
    end
  end

  # 76 claims predate the vocabulary. Told to "judge on the evidence alone", the model
  # INVENTED a standard — one note read "la regla exige…" where no rule exists — and two
  # of the four adjudicated v2 errors were on that path. A claim with no ratified rule
  # cannot be checked against one, so the question is deleted rather than paid for.
  describe "a claim with no ratified happening" do
    test "is refused without calling the model at all", ctx do
      Req.Test.stub(Wekui.Clients.Worker.Live, fn _conn ->
        flunk("the gate paid for a claim it has no rule to judge")
      end)

      assert {:error, {:no_ratified_rule, id}} = Verify.judge(ctx.untethered)
      assert id == ctx.untethered.id
    end

    test "records no verdict", ctx do
      assert {:error, {:no_ratified_rule, _id}} = Verify.run(ctx.untethered)
      assert {:ok, unchanged} = Narrative.get_claim(ctx.untethered.id)
      assert unchanged.support == :unverified
    end
  end
end
