# Curation scenarios — a human decides, and the record says who

**The gap, in one line.** [`actor`](pages/actor.md) already asserts *"Wherever this vocabulary
says that something was approved, proposed, judged or retired, an Actor did it, and we record
which one."* For an agent that is true — a [[run]] carries its executing agent. For a human it is
**false**: on 2026-07-27 two places were reparented, one claim was linked by hand and five persons
were approved, and not one of those acts records who did it. This document proposes the shape that
closes the gap, and answers [`open-actor`](pages/open-actor.md), open since 2026-07-22.

Markers: **[PROPOSAL]** = my recommendation, overrule in a word. **[OPEN]** = I need your answer.

---

## 1. The shape

### [PROPOSAL] A person is an Actor with a name

`Actor` already carries `kind: :person | :agent` and holds only agents. Add one attribute and one
action:

```elixir
attribute :name, :string        # "Aníbal Rojas". Absent for an agent.
create :register_person         # upsert on (event_id, name)
identity :unique_person, [:event_id, :name]
```

An agent leaves `name` NULL; a person leaves `model`, `prompt` and `content_hash` NULL. SQLite
treats NULLs as distinct in a unique index, so many agents coexist under `:unique_person` and many
persons under `:unique_agent`. *(Verified empirically before relying on it — see §5.)*

An Actor stays **remembered, never revised**: `register_person` is an upsert with `upsert_fields
[]`, so registering the same person twice returns the row we already hold. No update, no destroy —
same as an agent.

**An Actor's name is not a [[person]]'s name, and the F54 gate does not reach it.**
[`person`](pages/person.md) is explicit: a Person is *"whom a claim is about, never the actor who
made it."* Aníbal curating the record is an Actor; he is not a Person, `NoPrivateName` does not
apply to him, and an Actor's name never enters a Claim or a Beat. It appears only in the audit
trail and in the report's "already settled" section.

**Creating your Actor row is not itself a curation act** and carries no attribution. It is the
bootstrap — the same way the pilot's agent was registered by a seed script, not by a run.

### [PROPOSAL] Attribution is a record, not a stamp

Two ways to record who decided:

| | **(a) a stamp** | **(b) a record** |
|---|---|---|
| shape | `decided_by_actor_id` + `decided_at` + `note` on each curated thing | one append-only row per human act |
| cost | cheap; mirrors `Place.proposed_by_actor_id` | one resource, one table |
| second correction | **overwrites the first** — "what did he change on the 27th?" is unanswerable | both are there, in order |
| verdict | loses [[principle-never-rewrite-the-record]] | **recommended** |

The symmetry is the argument. The system's own acts just earned a receipt ([[run]]); a human's acts
deserve no less, in a project whose whole thesis is auditability. A stamp is a rewrite waiting to
happen, and the one thing this project will not do is rewrite the record.

*Considered and set aside:* reusing the [[judgment]] spine. It is the right **shape** — an Actor's
answer, append-only, superseding — but it is Post/Author-scoped, and stretching it over Places and
Persons costs more than it saves.

### [PROPOSAL] `Wekui.Curation.Act` — the resource

Table `curation_acts`. Append-only: a `record` create action, no update, no destroy.

| field | | |
|---|---|---|
| `event_id` | required | everything belongs to one Event |
| `actor_id` | required | **must be `kind: :person`** — validated on write, the mirror of `Provenance` |
| `kind` | required | the verb: `:promote_place`, `:reparent_place`, `:retype_place`, `:deprecate_place`, `:discard_place`, `:link_claim_place`, `:approve_person`, `:withhold_person`, `:set_person_handle`, `:set_person_kind`, `:retract_claim`, `:accept_support` |
| `reason` | **required** | why. One sentence. See the note below |
| `before` / `after` | `:map` | what it was, what it became — string-keyed JSON scalars only |
| `place_id` / `person_id` / `claim_id` | exactly one | the thing whose state changed |
| `inserted_at` | | the **when**; there is no separate `decided_at` to drift from it |

**[PROPOSAL] `reason` is required.** The project's own precedent is asymmetric — `discard_place`
requires a note ("the reason IS the record"), `deprecate_place` does not. Uniform-required is
simpler to hold in your head and costs one string per act; a batch of five person approvals passes
the same sentence. Say the word and it becomes optional.

**[PROPOSAL] Three targets, not four.** The brief proposed a fourth, `claim_place_id`. I dropped
it: when a claim is relinked, the thing that changed is *the claim's place set*, so the act targets
the **claim** and names the place in `after`. This keeps "exactly one target" true, keeps
`on_delete: :restrict` integrity, and makes "what did he change about this claim?" a single read.
The trade-off, stated plainly: a relink onto place X does not show up when you ask "what happened
to place X".

### [PROPOSAL] A new `Wekui.Curation` domain

Curation spans Core (places, actors) and Narrative (persons, claims), so it belongs to neither —
the same reasoning that gave `Wekui.Pipelines` its own domain last session. Added to `ash_domains`
in `config/config.exs`.

### [PROPOSAL] The act and the change are one transaction

Every curation verb is a code-interface function that performs the existing Ash action **and**
writes the Act, inside an explicit `Wekui.Repo.transaction/1` — the `Merge.do_merge` pattern,
because ash_sqlite cannot run Ash-managed transactions.

```elixir
Wekui.Curation.promote_place!(place, actor, "confirmed on the ground")
Wekui.Curation.link_claim_place!(claim, place, actor, "a bare Caraballeda means the parroquia")
Wekui.Curation.approve_person!(person, actor, "handle checked against the post")
```

This is load-bearing, not polish: if the Act write failed after the domain action succeeded, we
would have produced exactly the unattributed act this whole session exists to eliminate.

The curation surface is an **attribution layer over verbs that already exist** — `promote_place`,
`set_place_parent`, `approve_person`, `link_place`, `retract_claim` and the rest are all built and
green. Nothing here changes what the system can do; it changes what the record remembers about who
did it.

---

## 2. What the report does with this

Today the report re-asks every question forever. Most questions **suppress themselves** once
answered, because the answer changes the state the question reads:

| question | suppresses itself? | why |
|---|---|---|
| `unresolved` | ✅ | the claim now has a link |
| `pending_persons` | ✅ | status moves off `:pending_review` |
| `proposed_places` | ✅ | lifecycle moves off `:proposed` |
| `low_confidence` | ✅ | a manual link carries `confidence: nil`, and the guard requires one |
| `same_name` | ⚠️ **[PROPOSAL]** | the gazetteer tie persists — skip a mention whose link is `how_resolved: :manual`, because that *is* a human having decided |
| `flagged_claims` | ❌ | **"accept the attribution" changes nothing on the claim** — `support` stays `:overstated`. This one re-asks forever |

`flagged_claims` is the case that forces the report to read curation acts rather than infer from
state: an `:accept_support` act targeting the claim is the only record that the verdict was seen
and accepted. That is the whole reason `:accept_support` is in the `kind` vocabulary.

**[PROPOSAL] A "What you've already settled" section** at the foot of the report: each act, its
verb, its target, the person, the date and the reason. Without it the report is a nag; with it, it
is a record of a conversation.

---

## 3. What has no verb — deliberate additions, weighed

Building this surfaced four gaps. **Three are closed; one is left for you.**

1. **[BUILT] A `ClaimPlace` can now be unlinked.** Previously flagged as "a deliberate addition
   to weigh, not an oversight to patch" — so here is the weighing. Without it there is no such
   thing as *relinking*: `link_place` only ever adds, so correcting a wrong place would leave the
   claim about both. And "relink a claim" is half of what this session is for.

   Destroying a row is unheard of everywhere else in this model, and it is right here for one
   reason: a `ClaimPlace` is the **one deliberately mutable thing** in the design — its own
   doc says "re-resolution overwrites the provenance and confidence" — so a link is a *current
   best reading*, not a historical fact. And the Act preserves what it read, with who changed it
   and why. **The Act is what makes the deletion safe**: before curation existed, dropping a link
   would have lost information; now it moves that information into the audit trail. Say the word
   and it comes out again.
2. **[OPEN] A `PlaceName` cannot be retired.** `PlaceName` has `set_kind` and `set_emission` only.
   So "stop letting the populated_place answer to the bare name *Caraballeda*" — the durable fix
   for Q2 below — is still **not expressible**. Relinking fixes the affected claims; it does not
   stop the next run from tying again.
3. **[BUILT] A `Place` can now be renamed.** There was no `set_canonical_name`. `rename_place!`
   adds one — and **keeps the old string** as a `PlaceName` of kind `:error`, emission
   `:recognition_only`: still understood when a Post writes it, never emitted into a query of
   ours. Built for "San Juilán → San Julián", the typo you named while ruling two places apart.
4. **[BUILT] A `Claim` can now be corrected.** The report's own answer line on a flagged claim
   reads *"correct the claim, retract it, or accept the attribution"*, and the record could do
   only two of the three: one wrong word — "31 años" for 21 — meant withdrawing the whole
   account. `correct_claim!` drafts the corrected account as a **successor**, carrying the
   happening's first evidence, its citations and its people, and closes the wrong one onto it.
   The support verdict does not carry; the places carry unless the mention is what was corrected.

The one open gap and Q2 point the same way.

---

## 4. [OPEN] Q2 — the two Caraballedas, and the first attributed act

**They are not one place recorded twice.** The evidence settles that:

| | **Caraballeda** `3beeb2e4` | **Caraballeda** `5b443f04` |
|---|---|---|
| type | `parroquia` | `populated_place` |
| sits under | Vargas (municipio) | **the parroquia above** |
| holds | 169 children — incl. **22 populated_places**: El Zapatero, Filadelfia, San Julián, Antiguo Carmen de Uría… | 59 children — incl. **44 edificios**: Puerta al Mar, Celtimar I, Golf Mar, Coral Beach, Oasis Beach… |
| also answers to | — | **"Urbanización Caraballeda"** |

So: the parish that contains two dozen settlements, and — correctly nested inside it — the
beachfront town of buildings. Two real, different places. The only defect is that **both carry the
bare canonical name "Caraballeda"**, so a bare mention ties at 0.5 and the resolver picks one.

The symptom is in the beat: **"En Caraballeda" appears twice**, because two claims sit on two
different nodes of the same name.

| claim | mention | linked to | how |
|---|---|---|---|
| `búsqueda — un hombre` | "Caraballeda-La Guaira" | **parroquia** | `:manual` — your 2026-07-27 act |
| `rescate — una mujer` | "Caraballeda" | **populated_place** | `mention_exact`, confidence **0.5** |

**Three shapes for your answer:**

- **(a) They are one place — merge them.** `deprecate_place` + relink. The verbs exist. *The
  evidence above says this is wrong* — 22 settlements and 44 buildings are not the same node.
- **(b) A bare "Caraballeda" means the parroquia.** ← *recommended.* It is the coarser, safer
  reading: link the parish when the evidence does not name the town
  ([[principle-a-wrong-answer-is-worse-than-none]]), and the tree rolls the town up into it
  anyway. **Immediately**: relink `rescate — una mujer` onto the parroquia by hand — one
  attributed act, and the beat's double "En Caraballeda" collapses. **Durably**: the
  populated_place should stop answering to the bare name — which needs verb (1) from §3.
- **(c) Leave the tie and take whichever link each claim got.** Honest, but the beat keeps
  splitting Caraballeda in two.

I have **not** proposed a resolver rule ("prefer the ancestor when two places of one name tie").
It may well be right, but it is resolver code, not curation, and it belongs to its own change.
