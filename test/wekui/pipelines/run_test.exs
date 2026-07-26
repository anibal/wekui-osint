defmodule Wekui.Pipelines.RunTest do
  use Wekui.DataCase, async: false

  import Wekui.Fixtures

  alias Wekui.Pipelines

  setup do
    event = event!()
    %{event: event, agent: agent!(event)}
  end

  defp start!(ctx, options \\ %{}) do
    Pipelines.start_run!(%{
      event_id: ctx.event.id,
      actor_id: ctx.agent.id,
      kind: :read_path,
      options: options
    })
  end

  test "a run is born running, stamping the options it was asked with", ctx do
    run = start!(ctx, %{"place_id" => "abc", "from" => "2026-06-25T00:00:00Z"})

    assert run.status == :running
    assert run.kind == :read_path
    assert run.options["place_id"] == "abc"
    assert run.summary == nil
    assert run.finished_at == nil
    assert run.actor_id == ctx.agent.id
  end

  test "finalize closes it with a summary and a finish time", ctx do
    summary = %{"extract" => %{"claims" => 9}, "gates" => %{"persons_pending_review" => 5}}

    finalized = ctx |> start!() |> Pipelines.finalize_run!(%{summary: summary})

    assert finalized.status == :completed
    assert finalized.summary == summary
    assert finalized.finished_at
    assert DateTime.compare(finalized.finished_at, finalized.inserted_at) != :lt
  end

  test "a run that never finalized stays running — the crash artifact", ctx do
    run = start!(ctx)

    assert Pipelines.get_run!(run.id).status == :running
  end

  test "the executing agent must belong to the run's event", ctx do
    elsewhere = agent!(event!())

    assert {:error, error} =
             Pipelines.start_run(%{
               event_id: ctx.event.id,
               actor_id: elsewhere.id,
               kind: :read_path
             })

    assert error_on(error, :actor_id) =~ "same event"
  end

  test "kind is constrained to the pipelines that exist", ctx do
    assert {:error, error} =
             Pipelines.start_run(%{
               event_id: ctx.event.id,
               actor_id: ctx.agent.id,
               kind: :acquisition
             })

    assert error_on(error, :kind) =~ "must be one of"
  end

  test "an event's runs list newest first", ctx do
    first = start!(ctx, %{"n" => 1})
    second = start!(ctx, %{"n" => 2})

    assert [second.id, first.id] == Enum.map(Pipelines.list_runs!(ctx.event.id), & &1.id)
  end

  test "options and summary round-trip a DateTime as an ISO string", ctx do
    run = start!(ctx, %{"from" => ~U[2026-06-25 00:00:00.000000Z]})

    assert Pipelines.get_run!(run.id).options["from"] == "2026-06-25T00:00:00.000000Z"
  end
end
