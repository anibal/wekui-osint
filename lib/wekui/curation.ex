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
  alias Wekui.Narrative.Correction
  alias Wekui.Narrative.Merge
  alias Wekui.Normalize

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

  @doc """
  Corrects the name we ourselves use for a Place — the gazetteer held a misspelling,
  or the wrong name outright.

  **The old name is kept**, as a PlaceName of kind `:error` and emission
  `:recognition_only`: understood when a Post writes it, never emitted into a query
  of our own. A correction that made the record forget what it used to say would cost
  us every Post that still spells it the old way, and forgetting is not what a
  correction is for.
  """
  def rename_place!(place, name, curator, reason) do
    attributed!(curator, :rename_place, reason, [place_id: place.id], fn ->
      was = place.canonical_name
      renamed = Core.rename_place!(place, %{canonical_name: name})
      remember!(renamed, was)

      {%{"canonical_name" => was}, renamed, &%{"canonical_name" => &1.canonical_name}}
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

  @doc """
  Folds a Place into another: it was never a distinct place, only another name for
  one. Its children move up, its names move up, whatever Claims it held move up, and
  it is deprecated onto the Place it turned out to be.

  **One act, however many rows it moves.** The decision is a single sentence — "this
  is that" — and recording fifty-nine reparentings would bury it. The act's `before`
  counts what moved, so the scale of the change is on the record without the noise.

  This is `docs/pages/decision-2026-07-24-merge-is-deprecation.md` in one verb: there
  is no merge concept, because a lifecycle already says *this turned out to be that*.
  A Claim it held is carried over `:manual` rather than left to read through the
  replacement — a `ClaimPlace` is a link the reader follows directly, not a judgment
  that resolves on read.
  """
  def fold_place_into!(place, into, curator, reason) do
    attributed!(curator, :fold_place, reason, [place_id: place.id], fn ->
      children = children_of(place)
      links = Narrative.claims_at_place!(place.id)

      before = %{
        "lifecycle" => to_string(place.lifecycle),
        "parent" => place_name(place.parent_id),
        "children" => length(children),
        "claims" => length(links)
      }

      Enum.each(children, &Core.set_place_parent!(&1, %{parent_id: into.id}))
      carry_names!(place, into)
      Enum.each(links, &carry_link!(&1, into))

      {before, Core.deprecate_place!(place, %{replaced_by_id: into.id, note: reason}),
       &%{
         "lifecycle" => to_string(&1.lifecycle),
         "replaced_by" => place_name(&1.replaced_by_id)
       }}
    end)
  end

  @doc """
  Records that two Places which read almost alike are **not** the same place. "El
  Palmar Este" and "El Palmar Oeste"; "Residencias Green 7" and "Green 8".

  Like accepting a support verdict it changes nothing, and for the same reason it has
  to be written down: a "no" moves no status, so without an act the question comes
  back on every report, forever. The act is about `place` — the one something
  proposed to fold away — and names the other in `before`.
  """
  def distinguish_places!(place, from, curator, reason) do
    attributed!(curator, :distinguish_places, reason, [place_id: place.id], fn ->
      {%{"not" => "#{from.canonical_name} (#{from.type})", "not_id" => from.id}, place, nil}
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

  @doc """
  Corrects what a Claim says — the number, the kind of happening, the status, the
  mention, the note. `fields` is a map keyed by `Wekui.Narrative.Correction.fields/0`.

  The report has asked for this since the support gate landed ("Correct the claim,
  retract it, or accept the attribution") and until now the record could only do two
  of the three: an overstated claim had to be withdrawn whole, even when one word of
  it was wrong.

  A Claim is append-only, so this is **not** an edit. The corrected account is drafted
  as a new Claim carrying the original's first evidence, citations and people; the
  wrong one is closed and pointed at it. The successor's support verdict starts over —
  the gate judged the words that were wrong — and its places carry unless the mention
  is what was corrected. See `Wekui.Narrative.Correction`.

  The act is about the claim that was **corrected**, not its successor: that is the
  one whose state changed, and `after` names the account that replaced it.
  """
  def correct_claim!(claim, fields, curator, reason) do
    attributed!(curator, :correct_claim, reason, [claim_id: claim.id], fn ->
      # Read fresh, and from the same authority the correction itself uses: a caller
      # holding a stale struct must not put a stale `before` on the record.
      was = Narrative.get_claim!(claim.id)
      changed = Correction.changes(was, fields)
      before = Map.new(changed, fn {field, _to} -> {to_string(field), show(was, field)} end)

      corrected =
        case Correction.correct(was, fields, curator) do
          {:ok, corrected} ->
            corrected

          {:error, refusal} ->
            raise ArgumentError, "the correction was refused: #{inspect(refusal)}"
        end

      after_fun = fn successor ->
        changed
        |> Map.new(fn {field, _to} -> {to_string(field), show(successor, field)} end)
        |> Map.put("claim_id", successor.id)
      end

      {before, corrected, after_fun}
    end)
  end

  @doc """
  Folds two accounts of one happening into one Claim. The earlier account survives —
  a happening lives at its first evidence — and absorbs the other's citations and
  places; the later is closed and linked to it.

  The order of the arguments does not matter: `Wekui.Narrative.Merge` picks the
  canonical by first evidence, so a person says *these two are one* and does not have
  to work out which one wins. The act is about the account that was folded away.
  """
  def merge_claims!(one, other, curator, reason) do
    {canonical, duplicate} = ordered(one, other)

    attributed!(curator, :merge_claims, reason, [claim_id: duplicate.id], fn ->
      before = %{
        "kind" => duplicate.kind,
        "subject" => duplicate.subject,
        "places" => claim_places(duplicate)
      }

      {:ok, merged} = Merge.merge(canonical, duplicate)

      {before, merged, &%{"merged_into" => "#{&1.kind} — #{&1.subject}", "claim_id" => &1.id}}
    end)
  end

  @doc """
  Records that two accounts which read alike are **not** one happening. A woman
  missing in one building and a woman missing in another are two claims, and no
  reading of the strings can tell them apart.

  Like `distinguish_places!/4` it changes nothing, and for the same reason it must be
  written down: a "no" moves no status, so the pair would be offered again forever.
  """
  def distinguish_claims!(claim, from, curator, reason) do
    attributed!(curator, :distinguish_claims, reason, [claim_id: claim.id], fn ->
      {%{"not" => "#{from.kind} — #{from.subject}", "not_id" => from.id}, claim, nil}
    end)
  end

  # The canonical is the earlier happening; a tie falls to the earlier record. The
  # same order `Merge` applies, computed here so the act can name what was folded away
  # before the fold makes it harder to read.
  defp ordered(one, other) do
    if {one.first_seen_at, one.inserted_at} <= {other.first_seen_at, other.inserted_at},
      do: {one, other},
      else: {other, one}
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

  # Keeps a string the Place used to answer to, marked as the mistake it was: still
  # recognized when a Post writes it, never emitted into a query of ours.
  #
  # A row the Place already holds is corrected rather than doubled. It usually IS
  # already held — the gazetteer records its canonical name as a name — and it was
  # almost always recorded `:official`, which after a rename it plainly is not.
  defp remember!(place, was) do
    folded = Normalize.fold(was)

    case place.id |> Core.list_place_names!() |> Enum.find(&(&1.normalized == folded)) do
      nil ->
        Core.create_place_name!(%{
          place_id: place.id,
          name: was,
          kind: :error,
          emission: :recognition_only
        })

      held ->
        held
        |> Core.set_place_name_kind!(%{kind: :error})
        |> Core.set_place_name_emission!(%{emission: :recognition_only})
    end
  end

  # One of a Claim's fields as an Act may hold it. `before`/`after` are a display
  # record and not a query surface — string keys, scalar values — so `magnitude`, the
  # one field that is a map, is written the way a reader would read it aloud.
  defp show(claim, field) do
    case Map.get(claim, field) do
      nil -> nil
      value when is_binary(value) -> value
      value -> inspect(value)
    end
  end

  defp children_of(place) do
    place.event_id
    |> Core.list_places!()
    |> Enum.filter(&(&1.parent_id == place.id))
  end

  # Whatever the folded place answered to, the Place it turned out to be answers to
  # now — that is what makes the fold lossless. Kind and emission carry over
  # untouched: a fold moves a name, it does not re-judge what the name is. A string
  # the replacement already holds is skipped, canonical name included.
  defp carry_names!(place, into) do
    held =
      into.id
      |> Core.list_place_names!()
      |> MapSet.new(& &1.normalized)
      |> MapSet.put(Normalize.fold(into.canonical_name))

    ([%{name: place.canonical_name, kind: :official, emission: :raw}] ++
       Core.list_place_names!(place.id))
    |> Enum.reject(&MapSet.member?(held, Normalize.fold(&1.name)))
    |> Enum.uniq_by(&Normalize.fold(&1.name))
    |> Enum.each(fn name ->
      Core.create_place_name!(%{
        place_id: into.id,
        name: name.name,
        kind: name.kind,
        emission: name.emission
      })
    end)
  end

  # `:manual` and no confidence: a person decided this claim is about the replacement,
  # and a person does not estimate. It also stops a later run from re-resolving it.
  defp carry_link!(link, into) do
    Narrative.link_place!(%{
      claim_id: link.claim_id,
      place_id: into.id,
      how_resolved: :manual,
      confidence: nil
    })

    Narrative.unlink_place!(link)
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
