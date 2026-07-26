defmodule Wekui.Narrative do
  @moduledoc """
  The account of what happened, and its telling. A Claim is an Actor's synthesized
  assertion that something changed on the ground in an Event — one happening, drawn
  from many Posts and citing them (`docs/pages/claim.md`). A Beat is the derived
  prose a reader reads, written from the Claims that hold for a Place and a stretch
  of time (`docs/pages/beat.md`).

  Claim sits a layer above the Judgment cluster and reuses its spine — append-only,
  superseding, provenance, the agent's confidence — so it is not a new kind of
  judgment. This module holds the Claim record, its evidence (ClaimCitation), the
  people it is about (Person, ClaimPerson) and the gazetteer places it resolved to
  (ClaimPlace) — a claim may span several posts, people and places at once. Beat and
  the merge that keeps one claim per happening arrive as their own sub-concepts.
  """

  use Ash.Domain, otp_app: :wekui

  resources do
    resource Wekui.Narrative.Claim do
      define :draft_claim, action: :draft
      define :retract_claim, action: :retract
      define :record_claim_support, action: :record_support
      define :get_claim, action: :read, get_by: [:id]
      define :list_claims, action: :by_event, args: [:event_id]
      define :current_claims, action: :current_for_event, args: [:event_id]
    end

    resource Wekui.Narrative.ClaimCitation do
      define :cite_post, action: :cite
      define :list_claim_citations, action: :by_claim, args: [:claim_id]
    end

    resource Wekui.Narrative.Person do
      define :identify_person, action: :identify
      define :get_person, action: :read, get_by: [:id]
      define :list_persons, action: :by_event, args: [:event_id]
      define :set_person_handle, action: :set_handle
      define :set_person_kind, action: :set_kind
      define :approve_person, action: :approve
      define :withhold_person, action: :withhold
    end

    resource Wekui.Narrative.ClaimPerson do
      define :link_person, action: :link
      define :list_claim_persons, action: :by_claim, args: [:claim_id]
      define :person_arc, action: :by_person, args: [:person_id]
    end

    resource Wekui.Narrative.ClaimPlace do
      define :link_place, action: :link
      define :list_claim_places, action: :by_claim, args: [:claim_id]
      define :claims_at_place, action: :by_place, args: [:place_id]
    end
  end
end
