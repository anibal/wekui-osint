defmodule Wekui.Narrative.Correction do
  @moduledoc """
  Correcting a Claim that got the happening wrong (`docs/pages/claim.md`,
  `docs/pages/curation.md`) — the extractor read "31 años" where the post says 21,
  or called a search a rescue, or carried a status the evidence never gave.

  A Claim is append-only, so a correction is **not an edit**. The corrected account
  is DRAFTED as a new Claim and the wrong one is closed and pointed at it — exactly
  the shape a merge uses to close a duplicate. Both stay, in order, and the record
  can still be asked what it used to say
  (`docs/pages/principle-never-rewrite-the-record.md`).

  What the successor carries, and why:

    * `first_seen_at` — a happening lives at its first evidence, and correcting how
      it was described does not move when it happened;
    * its **citations** and the **people** it is about — the evidence did not change,
      only the reading of it;
    * its **places**, UNLESS `place_mention` is what was corrected. Correcting where
      it happened is itself the statement that the placement was wrong, so the
      successor starts unplaced and the next resolve reads the corrected text. A
      person who would rather place it themselves has
      `Wekui.Curation.relink_claim_place!/4`.

  What it deliberately does NOT carry is the **support verdict**: the gate judged the
  evidence against the words that were wrong. The successor starts `:unverified` and
  is judged again.

  A correction is a person's act — an agent that reads a post differently re-extracts,
  it does not correct — so an agent is refused here rather than left to fail on
  `Wekui.Judgment.Validations.Provenance` for want of a confidence.

  Wrapped in an explicit `Wekui.Repo.transaction` because ash_sqlite cannot run
  Ash-managed transactions: any failure rolls the partial correction back, leaving the
  claim exactly as it stood.
  """

  alias Wekui.Core.Actor
  alias Wekui.Narrative
  alias Wekui.Narrative.Claim

  # What a correction may touch. Everything else is either the claim's identity
  # (`event_id`, `first_seen_at`), its provenance (`actor_id`, `confidence`), or a
  # verdict that is not a person's to assert (`support`).
  @fields [:kind, :subject, :magnitude, :place_mention, :status, :nuance]

  @doc "The fields a correction may change."
  def fields, do: @fields

  @doc """
  The subset of `fields` that would actually change `claim` — a field given with the
  value it already holds is not a correction. Keys are atoms from `fields/0`.
  """
  def changes(%Claim{} = claim, fields) when is_map(fields) do
    Map.filter(fields, fn {field, value} -> Map.get(claim, field) != value end)
  end

  @doc """
  Corrects a current Claim: drafts the corrected account, carries what still holds,
  and closes the original onto it. Returns `{:ok, corrected}` with the successor
  reloaded.

  `{:error, {:not_correctable, fields}}` for a field outside `fields/0` — named rather
  than dropped, because silently ignoring half a correction is worse than refusing it.
  `{:error, :no_change}` when nothing given differs from what the claim already says
  (an act would then claim a person changed something they did not).
  `{:error, :not_current}` for an already-superseded claim, `{:error, :different_events}`
  across Events, `{:error, :not_a_person}` for an agent.
  """
  def correct(%Claim{} = claim, fields, %Actor{} = actor) when is_map(fields) do
    # Re-read for authoritative state: the caller may hold a struct that predates a
    # close, and the refusals below must not be fooled by it.
    claim = Narrative.get_claim!(claim.id)
    unknown = fields |> Map.keys() |> Enum.reject(&(&1 in @fields))

    cond do
      unknown != [] -> {:error, {:not_correctable, unknown}}
      actor.kind != :person -> {:error, :not_a_person}
      claim.event_id != actor.event_id -> {:error, :different_events}
      not is_nil(claim.superseded_at) -> {:error, :not_current}
      changes(claim, fields) == %{} -> {:error, :no_change}
      true -> do_correct(claim, changes(claim, fields), actor)
    end
  end

  defp do_correct(claim, changed, actor) do
    Wekui.Repo.transaction(fn ->
      corrected =
        %{
          event_id: claim.event_id,
          kind: claim.kind,
          subject: claim.subject,
          magnitude: claim.magnitude,
          place_mention: claim.place_mention,
          status: claim.status,
          nuance: claim.nuance,
          # The happening is the same happening; only its description was wrong.
          first_seen_at: claim.first_seen_at,
          actor_id: actor.id
        }
        |> Map.merge(changed)
        |> Narrative.draft_claim!()

      claim.id
      |> Narrative.list_claim_citations!()
      |> Enum.each(&Narrative.cite_post!(%{claim_id: corrected.id, post_id: &1.post_id}))

      claim.id
      |> Narrative.list_claim_persons!()
      |> Enum.each(&Narrative.link_person!(%{claim_id: corrected.id, person_id: &1.person_id}))

      unless Map.has_key?(changed, :place_mention), do: carry_places!(claim, corrected)

      # Close the wrong account and point it at the one that replaced it.
      claim
      |> Ash.Changeset.for_update(:retract)
      |> Ash.update!(authorize?: false)
      |> Ash.Changeset.for_update(:link_successor, %{superseded_by_id: corrected.id})
      |> Ash.update!(authorize?: false)

      Narrative.get_claim!(corrected.id)
    end)
  end

  # `how_resolved` and `confidence` carry verbatim: a link the resolver made is still
  # the resolver's reading, and a link a person made by hand is still theirs — and
  # stays `:manual`, so the next run leaves it alone.
  defp carry_places!(claim, corrected) do
    claim.id
    |> Narrative.list_claim_places!()
    |> Enum.each(fn link ->
      Narrative.link_place!(%{
        claim_id: corrected.id,
        place_id: link.place_id,
        how_resolved: link.how_resolved,
        confidence: link.confidence
      })
    end)
  end
end
