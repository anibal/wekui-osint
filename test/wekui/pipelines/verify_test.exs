defmodule Wekui.Pipelines.VerifyTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Narrative
  alias Wekui.Pipelines.Verify

  setup do
    event = event!()
    agent = agent!(event)
    post = post!(event, %{text: "rescataron con vida a un hombre en Caraballeda"})

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
    %{claim: claim}
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
end
