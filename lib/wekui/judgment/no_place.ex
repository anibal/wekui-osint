defmodule Wekui.Judgment.NoPlace do
  @moduledoc """
  The examined-empty answer for where: an Actor examined a Post and concluded it
  is about nowhere. A none-judgment, carrying its Actor and, for an agent, a
  confidence, superseding like any other.

  **No place** is never the same as **Unplaced**: Unplaced is *not yet worked
  out* (the default, absence of any placement), No place is *worked out, and the
  answer is nowhere*. The slot is the Post: at most one current "No place" per
  Post, and it is mutually exclusive with a real `Wekui.Judgment.Placement` —
  recording "No place" retracts the current placement, and placing retracts it.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.Placement
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Validations.Reference

  sqlite do
    table "no_place_judgments"
    repo Wekui.Repo

    custom_indexes do
      index [:actor_id]
      index [:event_id]

      # One current "No place" per Post.
      index [:post_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "no_place_judgments_current_post_index",
        message: "this Post already has a current 'No place'"
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
      Records that a Post is about nowhere, superseding a prior "No place" for the
      Post and retracting its current placement.
      """

      accept [:event_id, :post_id, :actor_id, :confidence, :judged_at]

      validate {Reference, resource: Wekui.Capture.Post, attribute: :post_id}
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      change {Supersede, slot: [:post_id]}
      change {CloseCurrent, resource: Placement, match: [:post_id]}
    end

    update :retract do
      description "Closes this 'No place' without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed 'No place' at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    read :current_for_post do
      description "A Post's current 'No place', if it has one."
      argument :post_id, :uuid, allow_nil?: false

      filter expr(post_id == ^arg(:post_id) and is_nil(superseded_at))
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
