# The operator's answers to the 2026-07-27 review report, applied.
#
#     mix run priv/scripts/curate_2026_07_27.exs
#
# A dated one-off, committed because a correction to the record deserves the same
# auditability as a machine's write: this file IS the account of what a human
# decided and why. It stands in for the curation path proper — which is the next
# thing to build, and whose missing piece these acts make plain: nothing here
# records WHICH human decided. `how_resolved: :manual` says "a person set this";
# it cannot say who.
#
# Idempotent: reparenting is a set, the claim-place link is an upsert, and
# approving an approved person is a no-op.

require Ash.Query

Logger.configure(level: :info)

alias Wekui.Core
alias Wekui.Narrative

event_name = System.get_env("EVENT", "litoral-central-2026")

event =
  Core.Event
  |> Ash.Query.filter(name == ^event_name)
  |> Ash.read_one!(authorize?: false)

places = Core.list_places!(event.id)
claims = Narrative.current_claims!(event.id)

find_place = fn name, type ->
  Enum.find(places, &(&1.canonical_name == name and &1.type == type)) ||
    Mix.raise("no place #{inspect(name)} (#{type}) in #{event_name}")
end

say = fn message -> IO.puts("  " <> message) end

IO.puts("\n── applying the operator's answers ──────────────────────────────\n")

# ── Q1 — the towers belong to the community, not beside it ───────────────────
#
# "It should live BELOW Residencias Caribe… if there are many buildings or towers
# part of a community, which was affected, or the one where help is required, or
# where people died, is relevant. That's why we have a recursive model."
#
# The posts named no tower — they said "Residencias Caribe" — so the three claims
# stay on the community, where the evidence puts them. What was wrong is the
# TREE: two towers sat as siblings of the community they belong to, so naming a
# tower could never roll up into it.
conjunto = find_place.("Conjunto Residencial Caribe", "edificio")

towers = [
  find_place.("Conjunto residencial Caribe Torre B", "edificio"),
  find_place.("Residencias Caribe, Torre C", "edificio")
]

for tower <- towers do
  if tower.parent_id == conjunto.id do
    say.("Q1 already: #{tower.canonical_name} under #{conjunto.canonical_name}")
  else
    Core.set_place_parent!(tower, %{parent_id: conjunto.id})
    say.("Q1 reparented: #{tower.canonical_name} → under #{conjunto.canonical_name}")
  end
end

# ── Q3 — the mention that matched nothing ────────────────────────────────────
#
# "This is Caraballeda, below La Guaira (the state, former Vargas)." The tree
# already holds that chain — Venezuela › La Guaira (estado) › Vargas (municipio)
# › Caraballeda (parroquia) — so the claim links to the parroquia, by hand. No
# confidence: a human did not estimate, a human decided.
parroquia = find_place.("Caraballeda", "parroquia")

unresolved =
  Enum.find(claims, fn claim ->
    claim.place_mention == "Caraballeda-La Guaira" and
      Narrative.list_claim_places!(claim.id) == []
  end)

case unresolved do
  nil ->
    say.("Q3 already: nothing left unresolved for “Caraballeda-La Guaira”")

  claim ->
    Narrative.link_place!(%{
      claim_id: claim.id,
      place_id: parroquia.id,
      how_resolved: :manual,
      confidence: nil
    })

    say.("Q3 linked: “#{claim.kind} — #{claim.subject}” → Caraballeda (parroquia)")
end

# ── Q4 — the handles are right ───────────────────────────────────────────────
#
# "These are all good." Approved for display; the full names stay protected, and
# a reader still meets only the handle.
pending = event.id |> Narrative.list_persons!() |> Enum.filter(&(&1.status == :pending_review))

for person <- pending do
  Narrative.approve_person!(person)
  say.("Q4 approved: #{person.display_handle}")
end

if pending == [], do: say.("Q4 already: no person is waiting")

IO.puts("""

  ── Q2 is NOT applied: the question was aimed wrong.

     The candidates offered were sectors of Caraballeda, which is what the
     answer explains — they were never rivals for a bare “Caraballeda”. The
     real tie is between two nodes of that exact name: the parroquia (under
     Vargas) and the populated_place (its own child). Re-asked in the report.
""")
