defmodule Wekui.Pipelines do
  @moduledoc """
  How the system runs itself over an Event: the stages, the orchestration that ties
  them into one pass, and the receipt each pass leaves behind.

  The stages are plain infra modules — `Extract` (posts → claims, through the
  inference Worker) and `Verify` (the support gate) — alongside `Wekui.Narrative`'s
  deterministic `PlaceResolver` and `BeatRenderer`. `ReadPath` is the Reactor that
  puts them in order; `Run` is the only persisted thing here, the auditable receipt
  of one execution (`docs/pages/run.md`).

  The read path has no agentic decisions: extract, resolve, verify and render run in
  a fixed order over a fixed scope, and an LLM appears only *inside* two stages. So
  the orchestration is deterministic by construction — see
  `docs/pages/decision-2026-07-26-reactor-not-sagents.md`.
  """

  use Ash.Domain,
    otp_app: :wekui

  alias Wekui.Pipelines.ReadPath

  resources do
    resource Wekui.Pipelines.Run do
      define :start_run, action: :start
      define :finalize_run, action: :finalize
      define :get_run, action: :read, get_by: [:id]
      define :list_runs, action: :by_event, args: [:event_id]
    end
  end

  @doc """
  Runs the read path over `event` — extract, resolve, verify, render — for the
  Place and interval in `ask` (`%{place_id:, from:, to:}`), and returns the
  finalized `Run` receipt.

  `agent` is the extraction Actor, passed explicitly and recorded in the receipt's
  options: Actors are content-addressed and immutable, so a revised prompt mints a
  *second* agent on the Event and "the Event's agent" would be ambiguous.

  `opts`: `:posts` (override the scope), `:extract` (`:force` to re-extract over
  claims that already exist), `:verify` (`:skip_verdicted`), `:prior`.

  Returns `{:ok, run}`, or `{:error, {:preflight, reason}}` when preflight refuses —
  in which case no receipt was opened at all.
  """
  def run_read_path(event, agent, %{place_id: place_id, from: from, to: to}, opts \\ []) do
    inputs = %{
      event: event,
      agent: agent,
      place_id: place_id,
      from: from,
      to: to,
      opts: opts
    }

    # Serial by construction: the read path has no agentic decisions to parallelize,
    # and the async path would lack the DB sandbox under test.
    case Reactor.run(ReadPath, inputs, %{}, async?: false) do
      {:ok, run} -> {:ok, run}
      {:error, error} -> {:error, cause(error)}
    end
  end

  # Reactor wraps a step's `{:error, reason}` in its own error classes; the caller
  # asked us for a reason, not for Reactor's bookkeeping.
  defp cause(%{errors: [error | _rest]}), do: cause(error)
  defp cause(%Reactor.Error.Invalid.RunStepError{error: error}), do: cause(error)
  defp cause(error), do: error
end
