defmodule Wekui.Judgment.ThemeNone do
  @moduledoc """
  The examined-empty answer for themes: an Actor read a Post and found no Theme
  applies — "we looked, and it is about nothing in our What axis", which is not
  the same as never having read it. A none-judgment, so it carries its Actor and,
  for an agent, a confidence, and it supersedes and is superseded like any other.

  The slot is the Post: at most one current "no theme" per Post
  (`Changes.Supersede`). It is mutually exclusive with real theme answers —
  recording "no theme" retracts every current `Wekui.Judgment.ThemeJudgment` for
  the Post (`Changes.CloseCurrent`), and judging a real Theme retracts it.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.ThemeJudgment
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Validations.Reference

  sqlite do
    table "theme_none_judgments"
    repo Wekui.Repo

    custom_indexes do
      index [:actor_id]
      index [:event_id]

      # One current "no theme" per Post: the partial unique that makes
      # supersession safe — only the open rows are constrained. (A custom index,
      # not an identity: ash_sqlite builds identity indexes from the resource
      # base_filter, not a per-identity `where`.)
      index [:post_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "theme_none_judgments_current_post_index",
        message: "this Post already has a current 'no theme'"
    end

    references do
      reference :event, on_delete: :restrict
      reference :post, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :superseded_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :judge_none do
      primary? true
      transaction? true

      description """
      Records that a Post is about no Theme, superseding a prior "no theme" for the
      Post and retracting every current theme answer for it.
      """

      accept [:event_id, :post_id, :actor_id, :confidence, :judged_at]

      validate {Reference, resource: Wekui.Capture.Post, attribute: :post_id}
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      change {Supersede, slot: [:post_id]}
      change {CloseCurrent, resource: ThemeJudgment, match: [:post_id]}
    end

    update :retract do
      description "Closes this 'no theme' without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed 'no theme' at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    read :current_for_post do
      description "A Post's current 'no theme', if it has one."
      argument :post_id, :uuid, allow_nil?: false

      filter expr(post_id == ^arg(:post_id) and is_nil(superseded_at))
    end

    read :by_event do
      description "Every 'no theme' answer of one Event — what has been read and found empty."
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

    belongs_to :actor, Wekui.Core.Actor do
      allow_nil? false
      public? true
    end

    belongs_to :superseded_by, __MODULE__ do
      description "The answer that replaced this one. Absent for a retraction and for the current answer."
      public? true
    end
  end
end
