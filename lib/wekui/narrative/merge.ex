defmodule Wekui.Narrative.Merge do
  @moduledoc """
  Folding two accounts of one happening into a single Claim (`docs/pages/claim.md`).
  When a merge finds that two claims describe the same state-change, this keeps
  ONE: the CANONICAL — the earliest occurrence, since a happening lives at its
  first evidence — survives and absorbs the other's citations and place links; the
  duplicate is closed and linked to it. "First occurrence owns the fact."

  WHICH two claims are the same happening is the merge judge's call — it turns on
  the specificity rule (a specific subject/magnitude carries identity across noisy
  places; a generic subject does not), and that judge is deferred with the agent
  runtime. This module only EXECUTES a decided fold.

  Wrapped in an explicit `Wekui.Repo.transaction` because ash_sqlite cannot run
  Ash-managed transactions: any failure rolls the partial fold back, leaving both
  claims as they were.
  """

  alias Wekui.Narrative
  alias Wekui.Narrative.Claim

  @doc """
  Folds two current claims of one Event into one (order-independent). The earlier
  by `first_seen_at` (tie: the earlier `inserted_at`) is the canonical; the later
  is closed and linked to it, and the canonical absorbs the duplicate's citations
  (the upsert dedups shared evidence). Returns `{:ok, canonical}` with the
  canonical reloaded.

  `{:error, :same_claim}` for a claim merged with itself, `{:error,
  :different_events}` across Events, `{:error, :not_current}` if either is already
  superseded.
  """
  def merge(%Claim{} = a, %Claim{} = b) do
    # Re-read both for authoritative state: a caller may hold a stale struct whose
    # superseded_at predates a close, and the refusals below must not be fooled.
    a = Narrative.get_claim!(a.id)
    b = Narrative.get_claim!(b.id)

    cond do
      a.id == b.id ->
        {:error, :same_claim}

      a.event_id != b.event_id ->
        {:error, :different_events}

      not (is_nil(a.superseded_at) and is_nil(b.superseded_at)) ->
        {:error, :not_current}

      true ->
        {canonical, duplicate} = order(a, b)
        do_merge(canonical, duplicate)
    end
  end

  # The canonical is the earlier happening; a tie falls to the earlier record.
  defp order(a, b) do
    case DateTime.compare(a.first_seen_at, b.first_seen_at) do
      :lt -> {a, b}
      :gt -> {b, a}
      :eq -> if DateTime.compare(a.inserted_at, b.inserted_at) != :gt, do: {a, b}, else: {b, a}
    end
  end

  defp do_merge(canonical, duplicate) do
    Wekui.Repo.transaction(fn ->
      # Close the duplicate and point it at the canonical it was folded into.
      duplicate
      |> Ash.Changeset.for_update(:retract)
      |> Ash.update!(authorize?: false)
      |> Ash.Changeset.for_update(:link_successor, %{superseded_by_id: canonical.id})
      |> Ash.update!(authorize?: false)

      # Absorb the duplicate's citations into the canonical; the citation upsert
      # dedups evidence the two claims shared.
      duplicate.id
      |> Narrative.list_claim_citations!()
      |> Enum.each(fn citation ->
        Narrative.cite_post!(%{claim_id: canonical.id, post_id: citation.post_id})
      end)

      # Absorb the duplicate's place links too — a merged happening keeps every place
      # either account placed it at. Keep the canonical's own resolution for a place
      # both named (a ClaimPlace upsert would otherwise overwrite it); add only the
      # places the canonical lacks. The union, canonical winning ties.
      held = canonical.id |> Narrative.list_claim_places!() |> MapSet.new(& &1.place_id)

      duplicate.id
      |> Narrative.list_claim_places!()
      |> Enum.reject(&MapSet.member?(held, &1.place_id))
      |> Enum.each(fn link ->
        Narrative.link_place!(%{
          claim_id: canonical.id,
          place_id: link.place_id,
          how_resolved: link.how_resolved,
          confidence: link.confidence
        })
      end)

      Narrative.get_claim!(canonical.id)
    end)
  end
end
