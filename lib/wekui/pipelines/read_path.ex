defmodule Wekui.Pipelines.ReadPath do
  @moduledoc """
  The read path as one auditable pass: **extract → resolve → verify → render**, over
  a fixed scope, leaving a [[run]] receipt behind (`docs/orchestration-scenarios.md`).

  Reactor holds the order and nothing else. Each step names what it needs — an input
  or an earlier step's result — and the order falls out of that; the work itself is
  `Wekui.Pipelines.ReadPath.Steps`, plain functions over capabilities that were built
  and proven on their own. Run serial (`async?: false`, set by
  `Wekui.Pipelines.run_read_path/4`) it executes one step at a time, fully
  predictable — and under test the async path would lack the DB sandbox anyway.

  **No undo callbacks, deliberately.** The record is append-only by doctrine, so a
  failed run must never quietly unmake what earlier steps honestly wrote. Reactor
  rescues a raising step and unwinding therefore just stops: the caller gets the
  exception back and the receipt is left `:running` — that stranded row IS the
  crash signal (there is no `:failed` state). **And no retries:** a stage
  absorbs the errors it can catch into the summary instead, which is strictly more
  honest than repeating the call — the receipt says what went wrong. `max_retries 0`
  on every step says so in the code.

  The one stage that must never repeat is extract: `Claim.:draft` has no identity,
  so a second pass over the same posts would mint duplicate claims.
  """

  use Reactor

  alias Wekui.Pipelines.ReadPath.Steps

  input :event
  input :agent
  input :place_id
  input :from
  input :to
  input :opts

  # Fails before any receipt exists: a run that never ran is not a record of the
  # system acting. Everything below depends on it, directly or through the receipt.
  step :preflight do
    argument :event, input(:event)
    argument :place_id, input(:place_id)
    argument :opts, input(:opts)
    run &Steps.preflight/2
    max_retries 0
  end

  step :start_run do
    argument :event, input(:event)
    argument :agent, input(:agent)
    argument :place_id, input(:place_id)
    argument :from, input(:from)
    argument :to, input(:to)
    argument :opts, input(:opts)
    argument :preflight, result(:preflight)
    run &Steps.start_run/2
    max_retries 0
  end

  step :extract do
    argument :event, input(:event)
    argument :agent, input(:agent)
    argument :opts, input(:opts)
    argument :preflight, result(:preflight)
    wait_for :start_run
    run &Steps.extract/2
    max_retries 0
  end

  step :resolve do
    argument :event, input(:event)
    argument :agent, input(:agent)
    wait_for :extract
    run &Steps.resolve/2
    max_retries 0
  end

  step :verify do
    argument :event, input(:event)
    argument :opts, input(:opts)
    wait_for :resolve
    run &Steps.verify/2
    max_retries 0
  end

  step :render do
    argument :place_id, input(:place_id)
    argument :from, input(:from)
    argument :to, input(:to)
    wait_for :verify
    run &Steps.render/2
    max_retries 0
  end

  step :finalize do
    argument :run, result(:start_run)
    argument :event, input(:event)
    argument :extract, result(:extract)
    argument :resolve, result(:resolve)
    argument :verify, result(:verify)
    argument :render, result(:render)
    run &Steps.finalize/2
    max_retries 0
  end

  return :finalize
end
