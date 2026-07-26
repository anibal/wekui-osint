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

  resources do
    resource Wekui.Pipelines.Run do
      define :start_run, action: :start
      define :finalize_run, action: :finalize
      define :get_run, action: :read, get_by: [:id]
      define :list_runs, action: :by_event, args: [:event_id]
    end
  end
end
