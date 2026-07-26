defmodule Wekui.Narrative.ClaimPlace do
  @moduledoc """
  A record that a [[claim]] is about a [[place]] — the gazetteer node the claim's
  `place_mention` resolved to (`docs/pages/claim.md`, `docs/place-mapping-scenarios.md`).
  A claim may be about several places at once — one happening spanning adjacent
  buildings or zones ("OPP 22, 24 y 25", "Caribe y Los Corales") — and a place carries
  many claims, so this is the many-to-many between them, alongside ClaimCitation (its
  posts) and ClaimPerson (its people).

  Unlike a citation, a place link is NOT immutable. The resolver re-runs as the
  gazetteer improves, or a web lookup upgrades an earlier guess, and the second pass
  must OVERWRITE `confidence` and `how_resolved` — so the upsert on `(claim, place)`
  writes those fields rather than no-oping the way ClaimCitation does. Re-linking the
  same place with a better resolution is the point, not a duplicate.

  `how_resolved` records the provenance of the link — how we know the claim is about
  this place — and `confidence` how sure the resolver is, so a reader and the review
  console can weight an exact gazetteer hit above a search-derived proposal. The Claim
  and the Place must belong to one Event.
  """

  use Ash.Resource, otp_app: :wekui, domain: Wekui.Narrative, data_layer: AshSqlite.DataLayer

  alias Wekui.Capture.Validations.SameEvent
  alias Wekui.Core.Place
  alias Wekui.Narrative.Claim

  # How a claim came to be tied to a place — its resolution provenance.
  @resolutions [
    # The mention matched a gazetteer name exactly (folded).
    :mention_exact,
    # The mention matched a gazetteer name approximately.
    :mention_fuzzy,
    # The finest named place was not in the tree; matched a coarser ancestor, and the
    # finer was proposed under it.
    :mention_ancestor,
    # No mention; defaulted to the query's swept place (weighted by the name's emission).
    :sweep,
    # Resolved by a web lookup (Tavily/Nominatim) and proposed with its sources.
    :search,
    # A human set it.
    :manual
  ]

  @doc "The resolution-provenance vocabulary for `how_resolved`."
  def resolutions, do: @resolutions

  sqlite do
    table "claim_places"
    repo Wekui.Repo

    custom_indexes do
      # (claim_id, place_id) is the unique identity; this index covers the place
      # direction — "which claims happened at this Place", the tree-rollup read.
      index [:place_id]
    end

    references do
      reference :claim, on_delete: :restrict
      reference :place, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :link do
      primary? true

      description "Records — or re-resolves — that a Claim is about a Place, with how it was resolved and how sure."

      accept [:claim_id, :place_id, :how_resolved, :confidence]

      upsert? true
      upsert_identity :unique_place_per_claim
      # A place link is mutable: re-resolution overwrites the provenance and
      # confidence. (ClaimCitation upserts `[]` because a citation never changes.)
      upsert_fields [:how_resolved, :confidence]

      validate {SameEvent, references: [{:claim_id, Claim}, {:place_id, Place}]}
    end

    read :by_claim do
      description "Every Place a Claim is about, in the order they were linked."
      argument :claim_id, :uuid, allow_nil?: false

      filter expr(claim_id == ^arg(:claim_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    read :by_place do
      description "Every Claim that happened at a Place, oldest first."
      argument :place_id, :uuid, allow_nil?: false

      filter expr(place_id == ^arg(:place_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :how_resolved, :atom do
      description "How the claim was tied to this place — an exact gazetteer hit, a fuzzy match, a coarser-ancestor fallback, a sweep default, a web search, or a human."
      allow_nil? false
      public? true
      constraints one_of: @resolutions
    end

    attribute :confidence, :float do
      description "How sure the resolver is this claim is about this place, 0 to 1. Absent when a human set it by hand."
      public? true
      constraints min: 0.0, max: 1.0
    end

    timestamps()
  end

  relationships do
    belongs_to :claim, Wekui.Narrative.Claim do
      allow_nil? false
      public? true
    end

    belongs_to :place, Wekui.Core.Place do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_place_per_claim, [:claim_id, :place_id] do
      message "this Claim is already linked to that Place"
    end
  end
end
