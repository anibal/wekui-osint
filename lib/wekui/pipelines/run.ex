defmodule Wekui.Pipelines.Run do
  @moduledoc """
  The receipt of one execution of the system's own pipeline over an [[event]]
  (`docs/pages/run.md`, `docs/orchestration-scenarios.md`): which stages ran, over what
  scope, what each produced, and which gates it left open. It records *that the system
  acted* — never a fact about the world. The facts live in the Claims and their
  evidence; a run is auditable provenance for how they got there.

  Two states, deliberately. A run is born `:running` with the exact `options` it was
  asked with, and `finalize` closes it `:completed` with a `summary`. There is no
  `:failed` state and no state machine: a raise unwinds the pipeline without unmaking
  what earlier steps honestly wrote, so a row still marked `:running` long after its
  start IS the crash signal. Errors a stage can catch are carried in the summary
  instead — a completed run with errors in its summary is an honest receipt.

  `options` and `summary` are opaque JSON-shaped maps: the receipt is a display record,
  not a query surface, and its shape widens as rungs land. DateTimes round-trip out of
  them as ISO strings, which is what a receipt wants.

  A run carries the [[actor]] that performed it — the executing agent, the same Actor
  whose prompt extraction uses. Actors are content-addressed and immutable, so a prompt
  revision mints a second agent on the event and "the event's agent" would be
  ambiguous; the ask names it, and the receipt records it.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Pipelines, data_layer: AshSqlite.DataLayer

  alias Wekui.Validations.Reference

  # What the system was asked to do. The vocabulary widens as the rungs land
  # (:polish, :acquisition…). `:pair_judge` is the second: the adversarial pass over
  # the duplicate finder's proposals, receipted here because a machine's act is a run,
  # never a `Wekui.Curation.Act`.
  @kinds [:read_path, :pair_judge]

  @doc "The pipeline vocabulary a run can record."
  def kinds, do: @kinds

  sqlite do
    table "runs"
    repo Wekui.Repo

    custom_indexes do
      # The receipt list of one Event, newest first — deliberately not unique: an
      # Event has as many runs as it was asked for.
      index [:event_id, :inserted_at]
      index [:actor_id]
    end

    references do
      reference :event, on_delete: :restrict
      reference :actor, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :start do
      primary? true

      description """
      Opens a receipt, born running, stamping the exact options the pipeline was
      asked with. A run that never opened is not a record of the system acting —
      preflight refuses before this point.
      """

      accept [:event_id, :actor_id, :kind, :options]

      # The executing agent belongs to the Event whose pipeline it ran.
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}

      change set_attribute(:status, :running)
    end

    update :finalize do
      description """
      Closes the receipt: the per-stage summary, the gate queues it surfaced, and
      when it finished. Called once, at the end of a run that reached its end.
      """

      accept [:summary]
      require_atomic? false

      change set_attribute(:status, :completed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :by_event do
      description "Every run of one Event, newest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :desc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      description "Which pipeline ran. Only the read path exists; the vocabulary widens as rungs land."
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :status, :atom do
      description "Running until finalized, then completed. A run still running long after its start is a crash artifact, not a live process."
      allow_nil? false
      public? true
      default :running
      constraints one_of: [:running, :completed]
    end

    attribute :options, :map do
      description "The exact ask — the place, the interval, the executing agent, the per-stage options. Stamped at birth and never revised."
      public? true
    end

    attribute :summary, :map do
      description "What happened, per stage: counts, verdicts, the unresolved leftovers, the gate queues, and the beat the render stage produced. Absent while running."
      public? true
    end

    attribute :finished_at, :utc_datetime_usec do
      description "When the run finalized. Absent while running; `inserted_at` is when it started."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :actor, Wekui.Core.Actor do
      description "The Actor that performed the run — the executing agent."
      allow_nil? false
      public? true
    end
  end
end
