defmodule Wekui.Judgment.ThemeJudgment do
  @moduledoc """
  An Actor's answer to *what is this Post about* — that a Post carries a Theme.
  One kind of judgment: append-only and superseding, carrying its Actor and, for
  an agent, a confidence.

  The slot is `(post_id, theme_id)`: a Post may carry any number of current theme
  judgments at once, but at most one for each Theme — a partial unique index over
  the open rows enforces it. Re-judging the same Post-and-Theme closes the prior
  answer and opens a new one, atomically (`Changes.Supersede`). A theme answer and
  the Post's "no theme" are mutually exclusive: writing one retracts the other
  (`Changes.CloseCurrent`).

  `judge_set` replaces a Post's whole set of Themes in one step, so the current set
  always reads as one coherent answer from one Actor.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.ThemeNone
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Validations.Reference

  sqlite do
    table "theme_judgments"
    repo Wekui.Repo

    custom_indexes do
      index [:post_id]
      index [:theme_id]
      index [:actor_id]
      index [:event_id]

      # One current answer per (Post, Theme): the partial unique that makes
      # supersession safe — only the open rows are constrained, the history is
      # free. (ash_sqlite builds identity indexes from the resource base_filter,
      # not a per-identity `where`, so this guard is a custom index, not an
      # identity.)
      index [:post_id, :theme_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "theme_judgments_current_slot_index",
        message: "this Post already has a current answer for that Theme"
    end

    references do
      reference :event, on_delete: :restrict
      reference :post, on_delete: :restrict
      reference :theme, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :superseded_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :judge do
      primary? true
      transaction? true

      description """
      Records that a Post is about a Theme, superseding any prior answer for that
      Post-and-Theme and retracting the Post's "no theme".
      """

      accept [:event_id, :post_id, :theme_id, :actor_id, :confidence, :judged_at]

      # Post, Theme and Actor must all belong to the judgment's Event; the Theme
      # must be an :active classification target.
      validate {Reference, resource: Wekui.Capture.Post, attribute: :post_id}

      validate {Reference,
                resource: Wekui.Taxonomy.Theme, attribute: :theme_id, lifecycle: :active}

      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      change {Supersede, slot: [:post_id, :theme_id]}
      change {CloseCurrent, resource: ThemeNone, match: [:post_id]}
    end

    update :retract do
      description "Closes this theme judgment without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed judgment at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    action :judge_set, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]

      description """
      Replaces a Post's whole set of Themes in one step: judges every Theme in the
      set from one Actor, and retracts the Themes no longer present. Returns the
      Post's current theme judgments.
      """

      argument :event_id, :uuid, allow_nil?: false
      argument :post_id, :uuid, allow_nil?: false
      argument :actor_id, :uuid, allow_nil?: false
      argument :theme_ids, {:array, :uuid}, allow_nil?: false, constraints: [min_length: 1]
      argument :confidence, :float
      argument :judged_at, :utc_datetime_usec

      run &Wekui.Judgment.ThemeJudgment.run_judge_set/2
    end

    read :current_for_post do
      description "A Post's current theme judgments, oldest first."
      argument :post_id, :uuid, allow_nil?: false

      filter expr(post_id == ^arg(:post_id) and is_nil(superseded_at))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_event do
      description "Every theme judgment of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :confidence, :float do
      description "How sure an agent is, 0 to 1. Absent for a person's judgment."
      public? true
      constraints min: 0.0, max: 1.0
    end

    attribute :judged_at, :utc_datetime_usec do
      description "When the answer was made."
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    attribute :superseded_at, :utc_datetime_usec do
      description "When this answer was closed. Absent while it is the current answer."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :post, Wekui.Capture.Post do
      allow_nil? false
      public? true
    end

    belongs_to :theme, Wekui.Taxonomy.Theme do
      allow_nil? false
      public? true
    end

    belongs_to :actor, Wekui.Core.Actor do
      allow_nil? false
      public? true
    end

    belongs_to :superseded_by, __MODULE__ do
      description "The answer that replaced this one. Absent for a retraction and for the current answer."
      public? true
    end
  end

  @doc false
  def run_judge_set(input, _context) do
    a = input.arguments

    Wekui.Judgment.SetReplacement.run(__MODULE__,
      scope: {:post_id, a.post_id},
      target: {:theme_id, a.theme_ids},
      judge: %{event_id: a.event_id, actor_id: a.actor_id, confidence: Map.get(a, :confidence)}
    )
  end
end
