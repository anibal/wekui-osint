defmodule Wekui.Judgment.Placement do
  @moduledoc """
  An Actor's answer to *where is this Post about* — a Post points at a Place. One
  kind of judgment: append-only and superseding, carrying its Actor and, for an
  agent, a confidence.

  The slot is the Post: a Post is about one where at a time, so it has at most one
  current placement (`Changes.Supersede` over a partial unique index). A placement
  and the Post's "No place" are mutually exclusive: writing one retracts the other
  (`Changes.CloseCurrent`).

  A Post stores no place of its own — its where is always *read* from its current
  placement, resolved by `Wekui.Judgment.Where`: an active or proposed Place reads
  as itself, a deprecated Place as its replacement, a discarded Place (and no
  placement at all) as Unplaced. So settling a Place never rewrites a placement.
  A Post cannot be placed at the Unplaced Place — that is the default, not an
  answer (`Validations.NotUnplaced`).
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Judgment, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.{CloseCurrent, Retract, Supersede}
  alias Wekui.Judgment.NoPlace
  alias Wekui.Judgment.Validations.{NotUnplaced, Provenance}
  alias Wekui.Validations.Reference

  sqlite do
    table "placements"
    repo Wekui.Repo

    custom_indexes do
      index [:place_id]
      index [:actor_id]
      index [:event_id]

      # One current placement per Post.
      index [:post_id],
        unique: true,
        where: "superseded_at IS NULL",
        name: "placements_current_post_index",
        message: "this Post already has a current placement"
    end

    references do
      reference :event, on_delete: :restrict
      reference :post, on_delete: :restrict
      reference :place, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :superseded_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :place do
      primary? true
      transaction? true

      description """
      Records where a Post is about, superseding any prior placement for the Post
      and retracting the Post's "No place".
      """

      accept [:event_id, :post_id, :place_id, :actor_id, :confidence, :judged_at]

      # Post, Place and Actor must all belong to the judgment's Event. A Place of
      # any lifecycle may be a placement target — collecting on a proposed Place is
      # allowed, and how a settled Place reads back is resolved on read, not gated
      # here — except the Unplaced Place, which is the default, never an answer.
      validate {Reference, resource: Wekui.Capture.Post, attribute: :post_id}
      validate {Reference, resource: Wekui.Core.Place, attribute: :place_id}
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate NotUnplaced
      validate Provenance

      change {Supersede, slot: [:post_id]}
      change {CloseCurrent, resource: NoPlace, match: [:post_id]}
    end

    update :retract do
      description "Closes this placement without a successor."
      accept []
      require_atomic? false
      change Retract
    end

    update :link_successor do
      description "Internal: points a just-closed placement at the successor that replaced it."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    read :current_for_post do
      description "A Post's current placement, if it has one."
      argument :post_id, :uuid, allow_nil?: false

      filter expr(post_id == ^arg(:post_id) and is_nil(superseded_at))
    end

    read :by_event do
      description "Every placement of one Event, oldest first."
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

    belongs_to :place, Wekui.Core.Place do
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
