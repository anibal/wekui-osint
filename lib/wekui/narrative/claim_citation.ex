defmodule Wekui.Narrative.ClaimCitation do
  @moduledoc """
  A record that one Post evidences one Claim — the lateral support a claim rests on
  (`docs/pages/claim.md`, `docs/pages/beat.md`). A claim ships only when its Posts
  genuinely bear what it asserts; this records which Posts those are.

  Like an Appearance, a citation is an immutable upsert on `(claim_id, post_id)`:
  citing the same Post for the same Claim twice changes nothing. The Claim and the
  Post must belong to one Event (`Wekui.Capture.Validations.SameEvent`).

  NOT YET GATED — support. This records THAT a Post was cited, not that it bears
  the claim's assertion; presence is not support. The support gate — an LLM-judge
  pass that verifies entailment, its own sub-concept — is not this record.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Capture.Post
  alias Wekui.Capture.Validations.SameEvent
  alias Wekui.Narrative.Claim

  sqlite do
    table "claim_citations"
    repo Wekui.Repo

    custom_indexes do
      # (claim_id, post_id) is the unique identity; this index covers post_id reads.
      index [:post_id]
    end

    references do
      reference :claim, on_delete: :restrict
      reference :post, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :cite do
      primary? true

      description "Records that a Post evidences a Claim, or returns the citation we already hold."

      accept [:claim_id, :post_id]

      upsert? true
      upsert_identity :unique_post_per_claim
      upsert_fields []

      validate {SameEvent, references: [{:claim_id, Claim}, {:post_id, Post}]}
    end

    read :by_claim do
      description "Every Post cited for one Claim, in the order they were recorded."
      argument :claim_id, :uuid, allow_nil?: false

      filter expr(claim_id == ^arg(:claim_id))
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

    belongs_to :post, Wekui.Capture.Post do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_post_per_claim, [:claim_id, :post_id] do
      message "this Claim already cites that Post"
    end
  end
end
