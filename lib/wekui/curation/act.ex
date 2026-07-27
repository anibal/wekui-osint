defmodule Wekui.Curation.Act do
  @moduledoc """
  The receipt of one deliberate act by a person on the record (`docs/pages/curation.md`,
  `docs/curation-scenarios.md`): who decided, when, what changed, and why.

  It is the human twin of a [[run]]. A run records *that the system acted*; an Act
  records *that a person did* — and for the same reason, so that the record can be
  audited rather than trusted. Wherever this vocabulary says something was approved,
  promoted, relinked or retired, an [[actor]] did it; for an agent the run says which
  one, and for a person this does.

  **Append-only.** There is a create action and nothing else: no update, no destroy. A
  correction of a correction is a second Act, not an edit of the first — which is the
  whole argument against stamping `decided_by` onto the curated thing, where the second
  correction would overwrite the first and "what did he change that day" would have no
  answer ([[principle-never-rewrite-the-record]]).

  **An Act never travels alone.** It is written in the same transaction as the change it
  attributes — see `Wekui.Curation` — because an Act without its change, or a change
  without its Act, is precisely the unattributed act this record exists to abolish.

  An Act points at **exactly one target**: the thing whose state changed. A relink
  targets the *claim*, not the link — the claim's set of places is what moved — and
  names the place in `after`. `before` and `after` are opaque JSON-shaped maps: string
  keys and scalars only, a display record and not a query surface.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Curation, data_layer: AshSqlite.DataLayer

  alias Wekui.Curation.Validations.HumanActor
  alias Wekui.Curation.Validations.OneTarget
  alias Wekui.Validations.Reference

  # The verbs a person can perform on the record. Every one is an existing Ash
  # action that was already built and already green — curation adds the who, not
  # the ability. The vocabulary widens as verbs are added, never silently: a kind
  # missing here is a verb nobody thought about attributing.
  @kinds [
    # Places
    :promote_place,
    :reparent_place,
    :retype_place,
    :deprecate_place,
    :discard_place,
    # One decision, however many rows it moves: this node was never a distinct
    # place, only another name for one.
    :fold_place,
    # The answer "no, those two are different places". Like accepting a support
    # verdict it changes nothing — and so, like it, the record is the only place
    # the answer can live.
    :distinguish_places,
    # Claims. A relink says "and not the places it was about", so it drops the
    # others; a link only adds, because one happening can span adjacent buildings.
    :link_claim_place,
    :relink_claim_place,
    :retract_claim,
    # The support gate: seen, weighed, and left standing. Unlike every other act
    # this one changes NO state — which is exactly why it must be recorded, or the
    # report re-asks about the same flagged claim forever.
    :accept_support,
    # Persons
    :approve_person,
    :withhold_person,
    :set_person_handle,
    :set_person_kind
  ]

  @doc "The vocabulary of deliberate acts a person can perform on the record."
  def kinds, do: @kinds

  # How each verb reads to a person. It lives beside the vocabulary rather than in
  # the reader that renders it, so the two cannot drift: a kind added without a
  # phrase is caught by this module's own test, not by a report that dies on a
  # perfectly valid record.
  @phrases %{
    promote_place: "promoted",
    reparent_place: "reparented",
    retype_place: "retyped",
    deprecate_place: "deprecated",
    discard_place: "discarded",
    fold_place: "folded",
    distinguish_places: "kept apart",
    link_claim_place: "placed",
    relink_claim_place: "re-placed",
    retract_claim: "retracted",
    accept_support: "accepted the support verdict on",
    approve_person: "approved",
    withhold_person: "withheld",
    set_person_handle: "renamed the handle of",
    set_person_kind: "set the privacy of"
  }

  @doc """
  How an act reads to a person: `:fold_place` → "folded". Falls back to the kind
  itself, because a record is never worth crashing over.
  """
  def phrase(kind), do: Map.get(@phrases, kind, kind |> to_string() |> String.replace("_", " "))

  sqlite do
    table "curation_acts"
    repo Wekui.Repo

    custom_indexes do
      # The audit trail of one Event, newest first — deliberately not unique: the
      # record is corrected as often as it needs to be.
      index [:event_id, :inserted_at]
      # "What has this curator decided" — the question Actor exists to make askable.
      index [:actor_id]
    end

    # Nothing here is ever deleted, and whatever an Act points at must stay
    # reachable, or the trail leads nowhere.
    references do
      reference :event, on_delete: :restrict
      reference :actor, on_delete: :restrict
      reference :place, on_delete: :restrict
      reference :person, on_delete: :restrict
      reference :claim, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :record do
      primary? true

      description """
      Writes down that a person decided something: the verb, the target, what it was,
      what it became, and why. Called by `Wekui.Curation`'s verbs inside the same
      transaction as the change itself — never on its own.
      """

      accept [
        :event_id,
        :actor_id,
        :kind,
        :reason,
        :before,
        :after,
        :place_id,
        :person_id,
        :claim_id
      ]

      # Attribution is the point: an agent's acts are receipted by a run, and an Act
      # naming one would be a run wearing the wrong name.
      validate HumanActor
      # The target is the thing whose state changed, and there is exactly one of it.
      validate OneTarget

      validate {Reference, resource: Wekui.Core.Actor, attribute: :actor_id}
      validate {Reference, resource: Wekui.Core.Place, attribute: :place_id}
      validate {Reference, resource: Wekui.Narrative.Person, attribute: :person_id}
      validate {Reference, resource: Wekui.Narrative.Claim, attribute: :claim_id}
    end

    read :by_event do
      description "Every act a person performed on one Event's record, newest first."
      argument :event_id, :uuid, allow_nil?: false

      filter expr(event_id == ^arg(:event_id))
      prepare build(sort: [inserted_at: :desc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      description "Which deliberate act this was — promoting a place, relinking a claim, approving a person, accepting a support verdict."
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :reason, :string do
      description "Why the person decided this. Required on every act: the reason is the half of the record a later reader cannot reconstruct."
      allow_nil? false
      public? true
      constraints min_length: 1
    end

    attribute :before, :map do
      description "What the target was, as far as this act is concerned. Opaque and JSON-shaped — string keys, scalar values."
      public? true
    end

    attribute :after, :map do
      description "What the target became. Absent when nothing changed — an accepted support verdict leaves the claim exactly as it stood."
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
      description "The person who decided. Never an agent."
      allow_nil? false
      public? true
    end

    belongs_to :place, Wekui.Core.Place do
      description "The Place this act was about, when it was about one."
      public? true
    end

    belongs_to :person, Wekui.Narrative.Person do
      description "The Person this act was about, when it was about one."
      public? true
    end

    belongs_to :claim, Wekui.Narrative.Claim do
      description "The Claim this act was about — including a relink, where the claim's set of places is what moved."
      public? true
    end
  end
end
