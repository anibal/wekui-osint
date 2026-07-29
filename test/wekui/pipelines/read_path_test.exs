defmodule Wekui.Pipelines.ReadPathTest.FallingOverWorker do
  @moduledoc """
  A worker that answers the extraction call and then falls over on the support
  call — the mid-run crash of scenario C, after earlier stages wrote honestly.
  """

  @behaviour Wekui.Clients.Worker

  @impl true
  def ready?, do: true

  @impl true
  def complete(prompt, opts) do
    if String.contains?(prompt, "EXTRACT-CLAIMS"),
      do: Wekui.Clients.Worker.Live.complete(prompt, opts),
      else: raise("the worker fell over mid-run")
  end
end

defmodule Wekui.Pipelines.ReadPathTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Core
  alias Wekui.Narrative
  alias Wekui.Pipelines

  # The extractor's prompt is the fixture agent's; the support prompt comes from
  # prompts/support.v1.txt. One worker stub serves both calls, told apart by this.
  @extract_marker "EXTRACT-CLAIMS"

  @from ~U[2026-06-25 00:00:00.000000Z]
  @to ~U[2026-07-02 00:00:00.000000Z]

  setup do
    event = event!()
    agent = agent!(event, %{prompt: "#{@extract_marker}\n{{place_scope}}\n{{material}}"})

    caraballeda = place!(event, %{canonical_name: "Caraballeda", type: "parroquia"})

    tanaguarena =
      place!(event, %{
        canonical_name: "Tanaguarena",
        type: "barrio",
        parent_id: caraballeda.id
      })

    opp =
      place!(event, %{canonical_name: "OPP 25", type: "edificio", parent_id: tanaguarena.id})

    # The vocabulary the extractor's free-text `kind` gets filed under. Without an
    # active happening theme a claim reaches no reader, so the pipeline's own tests
    # must run against a ratified vocabulary — as the real event does.
    for name <- ["rescate", "cifra oficial"] do
      theme!(event, %{
        name: name,
        applies_when: "the post states that a #{name} occurred",
        nature: :happening
      })
    end

    rescue_post =
      post!(event, %{
        x_id: "3923",
        text:
          "Nuestros equipos trabajan para sacar con vida a Aaron Levi Cantillo Vargas, " <>
            "de 21 años, atrapado en el edificio OPP 25, Tanaguarena, Caraballeda.",
        posted_at: ~U[2026-06-29 07:27:00.000000Z]
      })

    toll_post =
      post!(event, %{
        x_id: "4746",
        text: "El reporte oficial registra 1.943 fallecidos en el estado La Guaira.",
        posted_at: ~U[2026-07-01 10:00:00.000000Z],
        author: author!(event)
      })

    %{
      event: event,
      agent: agent,
      caraballeda: caraballeda,
      opp: opp,
      rescue_post: rescue_post,
      toll_post: toll_post
    }
  end

  ## ─────────────────────────── the worker stub ───────────────────────────

  @rescue_claim %{
    "kind" => "rescate en curso",
    "subject_role" => "un hombre de 21 años",
    "names" => ["Aaron Levi Cantillo Vargas"],
    "place_mention" => "edificio OPP 25, Tanaguarena, Caraballeda",
    "magnitude" => %{"horas" => 106},
    "status" => "atrapado",
    "citations" => ["3923"],
    "confidence" => 0.9
  }

  @toll_claim %{
    "kind" => "cifra oficial",
    "subject_role" => nil,
    "names" => [],
    "place_mention" => "Caraballeda",
    "magnitude" => %{"fallecidos" => 1943},
    "status" => "reportado",
    "citations" => ["4746"],
    "confidence" => 0.8
  }

  defp stub(claims, verdict \\ fn _prompt -> {"supported", "el post lo dice"} end) do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      prompt = body |> Jason.decode!() |> get_in(["messages", Access.at(0), "content"])

      content =
        if String.contains?(prompt, @extract_marker) do
          Jason.encode!(%{"claims" => claims})
        else
          {verdict, note} = verdict.(prompt)
          Jason.encode!(%{"verdict" => verdict, "note" => note})
        end

      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
    end)
  end

  defp run(ctx, opts \\ []) do
    Pipelines.run_read_path(
      ctx.event,
      ctx.agent,
      %{place_id: ctx.caraballeda.id, from: @from, to: @to},
      opts
    )
  end

  ## ─────────────────────────── A. a clean run ───────────────────────────

  test "a clean run finalizes with per-stage counts, the gates, and the beat", ctx do
    stub([@rescue_claim, @toll_claim])

    assert {:ok, run} = run(ctx)

    assert run.status == :completed
    assert run.finished_at
    assert run.kind == :read_path
    assert run.event_id == ctx.event.id
    assert run.actor_id == ctx.agent.id

    # The ask, exactly as it was made.
    assert run.options["place_id"] == ctx.caraballeda.id
    assert run.options["place_name"] == "Caraballeda"
    assert run.options["agent_id"] == ctx.agent.id
    assert run.options["posts_in_scope"] == 2

    assert %{"ran" => true, "posts" => 2, "drafted" => 2, "skipped" => 0} = run.summary["extract"]
    assert %{"claims" => 2, "linked" => 2, "proposed" => 0} = run.summary["resolve"]

    assert %{"claims" => 2, "judged" => 2, "supported" => 2, "errors" => 0} =
             run.summary["verify"]

    assert run.summary["render"]["place_name"] == "Caraballeda"
    assert run.summary["render"]["clauses"] == 2

    # The gates are surfaced, never blocked on: the person extraction named is
    # born pending_review and rides out in the queue.
    assert run.summary["gates"]["persons_pending_review"]["count"] == 1
    assert run.summary["gates"]["places_proposed"]["count"] == 0
    assert run.summary["gates"]["claims_not_supported"]["count"] == 0

    # The beat is a receipt of output — the claims stay the substance.
    assert run.summary["beat"]["prose"] =~ "Aaron C."
    assert run.summary["beat"]["prose"] =~ "OPP 25"
    assert [%{"n" => 1, "x_id" => "3923"} | _rest] = run.summary["beat"]["sources"]
  end

  test "the summary reads back from the database exactly as it was written", ctx do
    stub([@rescue_claim])

    assert {:ok, run} = run(ctx)
    assert Pipelines.get_run!(run.id).summary == run.summary
  end

  test "the beat stays re-derivable — the receipt's copy is provenance, not the story", ctx do
    stub([@rescue_claim])

    assert {:ok, run} = run(ctx)

    rerendered = Wekui.Narrative.BeatRenderer.render(ctx.caraballeda.id, @from, @to)
    assert rerendered.prose == run.summary["beat"]["prose"]
  end

  ## ─────────────────────────── B. preflight ───────────────────────────

  test "preflight refuses when the worker cannot answer, and opens no receipt", ctx do
    stub([@rescue_claim])
    put_deepinfra(api_key: nil)

    assert {:error, {:preflight, :worker_not_ready}} = run(ctx)
    assert Pipelines.list_runs!(ctx.event.id) == []
    assert Narrative.list_claims!(ctx.event.id) == []
  end

  test "preflight refuses an event with no active gazetteer", _ctx do
    # An Event is born with its Unplaced Place, active — which is not a gazetteer.
    unseeded = event!()
    post!(unseeded)

    assert [_unplaced] = Core.list_active_places!(unseeded.id)

    assert {:error, {:preflight, :no_active_gazetteer}} =
             Pipelines.run_read_path(
               unseeded,
               agent!(unseeded),
               %{place_id: unseeded.unplaced_place_id, from: @from, to: @to}
             )

    assert Pipelines.list_runs!(unseeded.id) == []
  end

  test "preflight refuses a place belonging to another event", ctx do
    stub([@rescue_claim])
    elsewhere = place!(event!())

    assert {:error, {:preflight, :place_not_in_event}} =
             Pipelines.run_read_path(
               ctx.event,
               ctx.agent,
               %{place_id: elsewhere.id, from: @from, to: @to}
             )

    assert Pipelines.list_runs!(ctx.event.id) == []
  end

  test "preflight refuses when nothing is in scope", ctx do
    stub([@rescue_claim])

    assert {:error, {:preflight, :no_posts_in_scope}} = run(ctx, posts: [])
  end

  ## ─────────────────────────── C. a crash mid-run ───────────────────────────

  test "a crash mid-run leaves the receipt running and unmakes nothing", ctx do
    stub([@rescue_claim, @toll_claim])
    put_worker(Wekui.Pipelines.ReadPathTest.FallingOverWorker)

    # Reactor rescues a raising step, so the caller gets the exception back rather
    # than having it propagate — and unwinding unmakes nothing, since no step
    # defines undo.
    assert {:error, %RuntimeError{message: message}} = run(ctx)
    assert message =~ "fell over"

    # The receipt is the crash signal: still running, never finalized.
    assert [receipt] = Pipelines.list_runs!(ctx.event.id)
    assert receipt.status == :running
    assert receipt.summary == nil
    assert receipt.finished_at == nil

    # And nothing earlier was unmade — there are no undo callbacks by doctrine.
    assert length(Narrative.list_claims!(ctx.event.id)) == 2
  end

  ## ─────────────────────────── D. re-running ───────────────────────────

  test "a second run skips extract rather than minting duplicate claims", ctx do
    stub([@rescue_claim, @toll_claim])

    assert {:ok, _first} = run(ctx)
    assert {:ok, second} = run(ctx)

    assert %{"ran" => false, "reason" => "claims_exist", "current_claims" => 2} =
             second.summary["extract"]

    # The rest of the path re-passed: resolve and verify still ran, event-wide.
    assert second.summary["resolve"]["claims"] == 2
    assert second.summary["verify"]["judged"] == 2
    assert length(Narrative.list_claims!(ctx.event.id)) == 2
  end

  test "extract: :force re-extracts over claims that already exist", ctx do
    stub([@rescue_claim])

    assert {:ok, _first} = run(ctx)
    assert {:ok, forced} = run(ctx, extract: :force)

    assert %{"ran" => true, "drafted" => 1} = forced.summary["extract"]
    assert length(Narrative.list_claims!(ctx.event.id)) == 2
  end

  ## ─────────────────────────── E. errors and gates ───────────────────────────

  test "an error a stage can catch is recorded, and the run still completes", ctx do
    Req.Test.stub(Wekui.Clients.Worker.Live, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "not json at all"}}]})
    end)

    assert {:ok, run} = run(ctx)

    assert run.status == :completed
    assert run.summary["extract"]["error"] =~ "invalid_json"
    assert run.summary["resolve"]["claims"] == 0
    assert run.summary["render"]["clauses"] == 0
  end

  test "an unsupported verdict is flagged in the gates and attributed in the beat", ctx do
    stub([@rescue_claim], fn prompt ->
      if String.contains?(prompt, "21 años"),
        do: {"unsupported", "el post no sostiene las 106 horas"},
        else: {"supported", "el post lo dice"}
    end)

    assert {:ok, run} = run(ctx)

    assert run.summary["verify"]["unsupported"] == 1
    assert run.summary["gates"]["claims_not_supported"]["count"] == 1
    assert run.summary["beat"]["prose"] =~ "según un reporte sin confirmar"
  end

  test "verify: :skip_verdicted spares the already-judged claims", ctx do
    stub([@rescue_claim])

    assert {:ok, _first} = run(ctx)
    assert {:ok, second} = run(ctx, verify: :skip_verdicted)

    assert %{"judged" => 0, "skipped" => 1, "supported" => 1} = second.summary["verify"]
    assert second.options["verify"] == "skip_verdicted"
  end

  test "an unresolved mention is carried out honestly rather than guessed", ctx do
    mention = Map.put(@rescue_claim, "place_mention", "cerca de un sitio que no existe")
    stub([mention])

    assert {:ok, run} = run(ctx)

    assert run.summary["resolve"]["linked"] == 0
    assert run.summary["resolve"]["unresolved"] == ["cerca de un sitio que no existe"]
  end

  ## ─────────────────────────── helpers ───────────────────────────

  defp put_deepinfra(overrides) do
    previous = Application.get_env(:wekui, :deepinfra, [])
    Application.put_env(:wekui, :deepinfra, Keyword.merge(previous, overrides))
    on_exit(fn -> Application.put_env(:wekui, :deepinfra, previous) end)
  end

  defp put_worker(impl) do
    previous = Application.get_env(:wekui, :worker_client)
    Application.put_env(:wekui, :worker_client, impl)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:wekui, :worker_client, previous),
        else: Application.delete_env(:wekui, :worker_client)
    end)
  end
end
