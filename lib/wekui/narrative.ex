defmodule Wekui.Narrative do
  @moduledoc """
  The account of what happened, and its telling. A Claim is an Actor's synthesized
  assertion that something changed on the ground in an Event — one happening, drawn
  from many Posts and citing them (`docs/pages/claim.md`). A Beat is the derived
  prose a reader reads, written from the Claims that hold for a Place and a stretch
  of time (`docs/pages/beat.md`).

  Claim sits a layer above the Judgment cluster and reuses its spine — append-only,
  superseding, provenance, the agent's confidence — so it is not a new kind of
  judgment. This module holds the Claim record and its evidence (ClaimCitation).
  Beat, the merge that keeps one claim per happening, the person gate, and the
  support gate arrive as their own sub-concepts.
  """

  use Ash.Domain, otp_app: :wekui

  resources do
    resource Wekui.Narrative.Claim do
      define :draft_claim, action: :draft
      define :retract_claim, action: :retract
      define :get_claim, action: :read, get_by: [:id]
      define :list_claims, action: :by_event, args: [:event_id]
      define :current_claims, action: :current_for_event, args: [:event_id]
    end

    resource Wekui.Narrative.ClaimCitation do
      define :cite_post, action: :cite
      define :list_claim_citations, action: :by_claim, args: [:claim_id]
    end
  end
end
