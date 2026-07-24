defmodule Wekui.Judgment.AuthorTagNone do
  @moduledoc """
  The examined-empty answer for author tags: an Actor examined an Author and
  found no Tag applies — distinct from never having examined it. A none-judgment,
  carrying its Actor and, for an agent, a confidence, superseding like any other.

  The slot is the Author: at most one current "no tag" per Author. It is mutually
  exclusive with real tag answers — recording "no tag" retracts every current
  `Wekui.Judgment.AuthorTagJudgment` for the Author, and judging a real Tag
  retracts it.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.AuthorTagJudgment
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Validations.Reference

  sqlite do
    table "author_tag_none_judgments"
    repo Wekui.Repo

    custom_indexes do
      index [:actor_id]
      index [:event_id]

      # One current "no tag" per Author.
      index [:author_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "author_tag_none_judgments_current_author_index",
        message: "this Author already has a current 'no tag'"
    end

    references do
      reference :event, on_delete: :restrict
      reference :author, on_delete: :restrict
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
      Records that an Author carries no Tag, superseding a prior "no tag" for the
      Author and retracting every current tag answer for it.
      """

      accept [:event_id, :author_id, :actor_id, :confidence, :judged_at]

      validate {Reference, resource: Wekui.Capture.Author, attribute: :author_id}
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      change {Supersede, slot: [:author_id]}
      change {CloseCurrent, resource: AuthorTagJudgment, match: [:author_id]}
    end

    update :retract do
      description "Closes this 'no tag' without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed 'no tag' at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    read :current_for_author do
      description "An Author's current 'no tag', if it has one."
      argument :author_id, :uuid, allow_nil?: false

      filter expr(author_id == ^arg(:author_id) and is_nil(superseded_at))
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

    belongs_to :author, Wekui.Capture.Author do
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
