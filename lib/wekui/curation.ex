defmodule Wekui.Curation do
  @moduledoc """
  A person settling the record, and the record remembering that they did
  (`docs/pages/curation.md`, `docs/curation-scenarios.md`).

  Every verb here wraps an Ash action that was already built and already green —
  promoting a Place, approving a Person, relinking a Claim. Curation adds no new
  ability; it adds the **who**, the **when** and the **why**. Each verb performs the
  change and writes a `Wekui.Curation.Act` **in one `Wekui.Repo.transaction`**, so the
  two cannot come apart. A change without its Act is exactly the unattributed act this
  module exists to abolish; an Act without its change is a lie. (The transaction is
  explicit because ash_sqlite cannot run Ash-managed ones — the `Narrative.Merge`
  pattern.)

  Curation lives in its own domain for the reason `Wekui.Pipelines` does: it spans Core
  (places) and Narrative (persons, claims) and belongs to neither.

  Every verb takes the target, then whatever it is changing to, then the **person** who
  decided and their **reason** — an ordinary sentence, required, because it is the half
  of the record a later reader cannot reconstruct from the data. An agent passed as the
  curator is refused: the machine's acts are receipted by a `Wekui.Pipelines.Run`.

      Wekui.Curation.promote_place!(place, curator, "confirmed on the ground")
      Wekui.Curation.relink_claim_place!(claim, parroquia, curator, "a bare Caraballeda is the parish")
      Wekui.Curation.approve_person!(person, curator, "handle checked against the post")
  """

  use Ash.Domain, otp_app: :wekui

  alias Wekui.Core
  alias Wekui.Narrative

  resources do
    resource Wekui.Curation.Act do
      define :record_act, action: :record
      define :get_act, action: :read, get_by: [:id]
      define :list_acts, action: :by_event, args: [:event_id]
    end
  end

  ## ─────────────────────────── places ───────────────────────────

  @doc "The human gate: a proposed Place becomes part of the Event's settled geography."
  def promote_place!(place, curator, reason) do
    attributed!(curator, :promote_place, reason, [place_id: place.id], fn ->
      {%{"lifecycle" => to_string(place.lifecycle)}, Core.promote_place!(place),
       &%{"lifecycle" => to_string(&1.lifecycle)}}
    end)
  end

  @doc "Moves a Place under the one that contains it — the act that makes a subtree roll up correctly."
  def reparent_place!(place, parent, curator, reason) do
    attributed!(curator, :reparent_place, reason, [place_id: place.id], fn ->
      {%{"parent" => place_name(place.parent_id)},
       Core.set_place_parent!(place, %{parent_id: parent.id}),
       &%{"parent" => place_name(&1.parent_id)}}
    end)
  end

  @doc "Curates a Place's free-form type label."
  def retype_place!(place, type, curator, reason) do
    attributed!(curator, :retype_place, reason, [place_id: place.id], fn ->
      {%{"type" => place.type}, Core.set_place_type!(place, %{type: type}), &%{"type" => &1.type}}
    end)
  end

  @doc "Retires a Place onto an active replacement. The reason is also kept as the Place's status note."
  def deprecate_place!(place, replacement, curator, reason) do
    attributed!(curator, :deprecate_place, reason, [place_id: place.id], fn ->
      {%{"lifecycle" => to_string(place.lifecycle)},
       Core.deprecate_place!(place, %{replaced_by_id: replacement.id, note: reason}),
       &%{"lifecycle" => to_string(&1.lifecycle), "replaced_by" => place_name(&1.replaced_by_id)}}
    end)
  end

  @doc "Retires a Place with no replacement, because it was a mistake."
  def discard_place!(place, curator, reason) do
    attributed!(curator, :discard_place, reason, [place_id: place.id], fn ->
      {%{"lifecycle" => to_string(place.lifecycle)}, Core.discard_place!(place, %{note: reason}),
       &%{"lifecycle" => to_string(&1.lifecycle)}}
    end)
  end

  ## ─────────────────────────── claims ───────────────────────────

  @doc """
  Adds a Place to what a Claim is about, by hand. `how_resolved` is `:manual` and the
  confidence is absent — a person decides, a person does not estimate.

  This ADDS: a happening that spans adjacent buildings points at each of them. To say
  the Claim is about this Place and *not* the ones it was about, use
  `relink_claim_place!/4`.
  """
  def link_claim_place!(claim, place, curator, reason) do
    attributed!(curator, :link_claim_place, reason, [claim_id: claim.id], fn ->
      {%{"places" => claim_places(claim)}, manual_link!(claim, place),
       fn _link -> %{"places" => claim_places(claim)} end}
    end)
  end

  @doc """
  Corrects where a Claim happened: it is about this Place, and not the ones it was
  linked to. The old links are dropped and this one is written `:manual`.

  Dropping a link is safe *because of this Act*. A ClaimPlace is the one deliberately
  mutable thing in the model — "re-resolution overwrites the provenance and confidence"
  — so a link is a current best reading, not a historical fact; and what it read before
  is preserved here, with who changed it and why. Removing a link without an Act would
  lose information; removing it with one moves that information into the audit trail.
  """
  def relink_claim_place!(claim, place, curator, reason) do
    attributed!(curator, :relink_claim_place, reason, [claim_id: claim.id], fn ->
      before = %{"places" => claim_places(claim)}

      claim.id
      |> Narrative.list_claim_places!()
      |> Enum.reject(&(&1.place_id == place.id))
      |> Enum.each(&Narrative.unlink_place!/1)

      {before, manual_link!(claim, place), fn _link -> %{"places" => claim_places(claim)} end}
    end)
  end

  @doc "Withdraws a Claim: it no longer holds, and nothing takes its place."
  def retract_claim!(claim, curator, reason) do
    attributed!(curator, :retract_claim, reason, [claim_id: claim.id], fn ->
      # No "became": the verb says what happened, and a retracted Claim drops out
      # of the current record entirely — `before` is the only way to still name it.
      {%{"kind" => claim.kind, "subject" => claim.subject}, Narrative.retract_claim!(claim), nil}
    end)
  end

  @doc """
  Records that a person read the support gate's verdict on a Claim and let the Claim
  stand as it is.

  It is the one act that changes **nothing** — which is exactly why it has to be
  written down. Every other answer moves a status the report reads, so its question
  stops being asked on its own; this one would be asked forever.
  """
  def accept_support!(claim, curator, reason) do
    attributed!(curator, :accept_support, reason, [claim_id: claim.id], fn ->
      {%{"support" => to_string(claim.support), "support_note" => claim.support_note}, claim, nil}
    end)
  end

  ## ─────────────────────────── persons ───────────────────────────

  @doc "Approves a Person for display: their handle stands, and their Claims may be told."
  def approve_person!(person, curator, reason) do
    attributed!(curator, :approve_person, reason, [person_id: person.id], fn ->
      {%{"status" => to_string(person.status)}, Narrative.approve_person!(person),
       &%{"status" => to_string(&1.status)}}
    end)
  end

  @doc "Withholds a Person from display: they read by role alone."
  def withhold_person!(person, curator, reason) do
    attributed!(curator, :withhold_person, reason, [person_id: person.id], fn ->
      {%{"status" => to_string(person.status)}, Narrative.withhold_person!(person),
       &%{"status" => to_string(&1.status)}}
    end)
  end

  @doc "Corrects the handle a reader meets — the escape hatch when the derived one is wrong."
  def set_person_handle!(person, handle, curator, reason) do
    attributed!(curator, :set_person_handle, reason, [person_id: person.id], fn ->
      {%{"display_handle" => person.display_handle},
       Narrative.set_person_handle!(person, %{display_handle: handle}),
       &%{"display_handle" => &1.display_handle}}
    end)
  end

  @doc "Marks a Person private (protected) or public (may be named)."
  def set_person_kind!(person, kind, curator, reason) do
    attributed!(curator, :set_person_kind, reason, [person_id: person.id], fn ->
      {%{"kind" => to_string(person.kind)}, Narrative.set_person_kind!(person, %{kind: kind}),
       &%{"kind" => to_string(&1.kind)}}
    end)
  end

  ## ─────────────────────────── the machinery ───────────────────────────

  # Performs the change and writes its Act as one indivisible thing. `change` is a
  # closure so that nothing in it runs before the transaction opens; it yields
  # `{before, changed, after_fun}` — what the target was, what the action returned, and
  # how to read what it became (nil when nothing changed). A raise anywhere inside
  # rolls both back, so the record never holds a change nobody owns.
  defp attributed!(curator, kind, reason, target, change) when is_function(change, 0) do
    {:ok, changed} =
      Wekui.Repo.transaction(fn ->
        {before, changed, after_fun} = change.()

        record_act!(
          Map.merge(
            %{
              event_id: curator.event_id,
              actor_id: curator.id,
              kind: kind,
              reason: reason,
              before: before,
              after: after_fun && after_fun.(changed)
            },
            Map.new(target)
          )
        )

        changed
      end)

    changed
  end

  defp manual_link!(claim, place) do
    Narrative.link_place!(%{
      claim_id: claim.id,
      place_id: place.id,
      how_resolved: :manual,
      confidence: nil
    })
  end

  # A Claim's places named the way a person reads them, read fresh from the database:
  # the caller's struct predates the change, and the whole value of `before`/`after`
  # is that each is read at its own moment.
  defp claim_places(claim) do
    claim.id
    |> Narrative.list_claim_places!()
    |> Enum.map_join(", ", &place_name(&1.place_id))
    |> case do
      "" -> nil
      places -> places
    end
  end

  defp place_name(nil), do: nil

  defp place_name(place_id) do
    case Core.get_place(place_id) do
      {:ok, place} -> "#{place.canonical_name} (#{place.type})"
      {:error, _gone} -> nil
    end
  end
end
