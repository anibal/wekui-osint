defmodule Wekui.Narrative.ClaimPerson do
  @moduledoc """
  A record that a [[claim]] is about a [[person]] (`docs/pages/claim.md`,
  `docs/pages/person.md`). A claim may be about several people (a reported pair),
  and a person runs through several claims (their arc) — so this is the many-to-many
  between them.

  Immutable upsert on `(claim, person)`: linking the same person to the same claim
  twice changes nothing. The Claim and the Person must belong to one Event.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Capture.Validations.SameEvent
  alias Wekui.Narrative.Claim
  alias Wekui.Narrative.Person

  sqlite do
    table "claim_persons"
    repo Wekui.Repo

    custom_indexes do
      # (claim_id, person_id) is the unique identity; this index covers person reads.
      index [:person_id]
    end

    references do
      reference :claim, on_delete: :restrict
      reference :person, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :link do
      primary? true

      description "Records that a Claim is about a Person, or returns the link we already hold."

      accept [:claim_id, :person_id]

      upsert? true
      upsert_identity :unique_person_per_claim
      upsert_fields []

      validate {SameEvent, references: [{:claim_id, Claim}, {:person_id, Person}]}
    end

    read :by_claim do
      description "Every Person a Claim is about, in the order they were linked."
      argument :claim_id, :uuid, allow_nil?: false

      filter expr(claim_id == ^arg(:claim_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_person do
      description "Every Claim a Person runs through — their arc, oldest first."
      argument :person_id, :uuid, allow_nil?: false

      filter expr(person_id == ^arg(:person_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :claim, Wekui.Narrative.Claim do
      allow_nil? false
      public? true
    end

    belongs_to :person, Wekui.Narrative.Person do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_person_per_claim, [:claim_id, :person_id] do
      message "this Claim is already linked to that Person"
    end
  end
end
