defmodule Wekui.Narrative.Claim do
  @moduledoc """
  An Actor's account that something happened in an Event — one change on the
  ground: a building collapsed, a person was rescued, an official toll was
  announced (`docs/pages/claim.md`). Where a judgment answers a question about a
  single Post, a Claim is an account of the world, drawn from many Posts and citing
  them (`ClaimCitation`).

  A Claim is not a new kind of judgment; it is a layer above them on the same spine
  — it belongs to one Event, it is append-only and superseding, and it carries its
  Actor and, for an agent, a confidence (`Wekui.Judgment.Validations.Provenance`).
  Its identity is the happening itself, decided by a merge, NOT a column tuple — so
  unlike a judgment it has no partial-unique slot index. Two accounts of one
  happening become one Claim by an explicit merge (its own sub-concept, not yet
  built); until then `draft` records a fresh account, and its evidence is cited
  through `ClaimCitation`.

  A Claim is structured: `kind` (the state-change type — vocabulary still to
  settle, so a plain string for now), `subject` (whom it concerns, by role and
  attribute — never a private name), `place` (the most specific Place, or nil =
  event-wide), `first_seen_at` (when first evidenced), `magnitude`, `status`. The
  Spanish a reader sees is a Beat rendered from these, never stored here.

  The person red line is gated on the write path (F54): `draft` refuses a
  `subject` or `nuance` that names a private individual, checked mechanically by
  `Wekui.Narrative.Validations.NoPrivateName` against the event's gazetteer and
  the public-figure allowlist — never by a prompt. Only roles, places and public
  figures may appear.

  Folding two accounts of one happening into one claim — canonical = the earliest
  occurrence, absorbing the duplicate's citations, the duplicate closed and linked
  — is `Wekui.Narrative.Merge`. Still deferred, each its own sub-concept: status
  threading (a claim's status changing as the world moves), the support gate (an
  LLM-judge that verifies the evidence bears the assertion), and Beat rendering.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Judgment.Changes.Retract
  alias Wekui.Judgment.Validations.Provenance
  alias Wekui.Narrative.Validations.NoPrivateName
  alias Wekui.Validations.Reference

  sqlite do
    table "claims"
    repo Wekui.Repo

    custom_indexes do
      index [:place_id]
      index [:actor_id]

      # A Claim has NO partial-unique slot: its identity is the happening, decided
      # by a merge, not a column tuple. This index only speeds the "current claims
      # of an Event" read; it is deliberately not unique.
      index [:event_id, :superseded_at]
    end

    references do
      reference :event, on_delete: :restrict
      reference :place, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :superseded_by, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :draft do
      primary? true

      description """
      Records a fresh account of a happening; its evidence is cited separately
      through ClaimCitation. Does not merge — keeping one claim per happening is
      the merge sub-concept's job.
      """

      accept [
        :event_id,
        :kind,
        :subject,
        :magnitude,
        :place_mention,
        :status,
        :nuance,
        :first_seen_at,
        :place_id,
        :actor_id,
        :confidence
      ]

      # Place (when given) and Actor must belong to the Claim's Event; a nil Place
      # is event-wide and passes. Confidence is required for an agent, absent for a
      # person.
      validate {Reference, resource: Wekui.Core.Place, attribute: :place_id}
      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate Provenance

      # The persons red line, on the write path (F54). The subject is STRICT — no
      # person name at all, not even an allowlisted public figure (a public figure used
      # to point at a private relative is the leak). The nuance is lenient — a public
      # official acting publicly may be named there.
      validate {NoPrivateName, strict: [:subject], lenient: [:nuance]}
    end

    update :retract do
      description "Closes this claim without a successor — the Actor withdraws the account."
      accept []
      require_atomic? false
      change Retract
    end

    update :record_support do
      description "Records the support pass's verdict on whether the cited evidence bears the claim."
      accept [:support, :support_note]
    end

    update :link_successor do
      description "Internal: points a just-closed claim at the canonical it was folded into (merge)."
      accept []
      require_atomic? false
      argument :superseded_by_id, :uuid, allow_nil?: false
      change set_attribute(:superseded_by_id, arg(:superseded_by_id))
    end

    read :by_event do
      description "Every claim of one Event, oldest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :current_for_event do
      description "The current (not superseded) claims of one Event, earliest happening first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id) and is_nil(superseded_at))
      prepare build(sort: [first_seen_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :string do
      description "The state-change type — a rescue, a collapse, an official toll. Vocabulary still to settle, so a plain string for now."
      allow_nil? false
      public? true
    end

    attribute :subject, :string do
      description "Whom or what the claim concerns, by role and attribute — never a private name. Absent when no person is concerned."
      public? true
    end

    attribute :magnitude, :map do
      description "How much, when the evidence carries a number — hours trapped, a death toll. Absent otherwise."
      public? true
    end

    attribute :place_mention, :string do
      description "The place as a post named it, before it is matched to the gazetteer — a holding value until a Place is resolved and set on place_id."
      public? true
    end

    attribute :status, :string do
      description "The claim's current standing — rescatado, desaparecido, en curso. Threads through supersession when the world moves. Vocabulary still to settle."
      public? true
    end

    attribute :nuance, :string do
      description "An optional short note the structured fields cannot hold. Bound by the same person red line as the rest of the claim."
      public? true
    end

    attribute :first_seen_at, :utc_datetime_usec do
      description "When the happening was first evidenced — the effective time of its strongest citation."
      allow_nil? false
      public? true
    end

    attribute :confidence, :float do
      description "How sure an agent is, 0 to 1. Absent for a person's claim."
      public? true
      constraints min: 0.0, max: 1.0
    end

    attribute :support, :atom do
      description "Whether the cited evidence bears the claim: unverified until a support pass judges it, then supported, overstated, or unsupported. Citation presence is not support."
      allow_nil? false
      public? true
      default :unverified
      constraints one_of: [:unverified, :supported, :overstated, :unsupported]
    end

    attribute :support_note, :string do
      description "The support pass's one-line reason — what, if anything, the evidence does not bear."
      public? true
    end

    attribute :superseded_at, :utc_datetime_usec do
      description "When this account was closed. Absent while it is the current account."
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :event, Wekui.Core.Event do
      allow_nil? false
      public? true
    end

    belongs_to :place, Wekui.Core.Place do
      description "The most specific Place the evidence supports, or nil = event-wide. A coarser Place's claims are read by asking the Place tree."
      public? true
    end

    belongs_to :actor, Wekui.Core.Actor do
      allow_nil? false
      public? true
    end

    belongs_to :superseded_by, __MODULE__ do
      description "The account that replaced this one. Absent for a retraction and for the current account."
      public? true
    end

    has_many :citations, Wekui.Narrative.ClaimCitation do
      description "The Posts that evidence this claim."
      public? true
    end
  end
end
