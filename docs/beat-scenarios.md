# Beat rendering — scenarios for validation

**The job:** turn the structured **[[claim]]s** that hold for a **[[place]]** and a stretch of
time into the Spanish prose a reader actually meets — *derived, never authored from scratch,
and never by an LLM re-writing claims* (`docs/pages/beat.md`). Proposed for your feedback before
any code. Markers: **[PROPOSAL]** my recommendation · **[OPEN]** your call. Grounded in the 9 real
Caraballeda claims.

## First principles (from `beat.md`, made concrete)

1. **A beat says only what its claims say.** It may word them, connect them, and drop the lesser
   ones — never add a fact. The old app's beat 11048 *fabricated* a fact and *cited noise*; the
   renderer must be incapable of that by construction (it reads claim fields, it does not invent).
2. **Scope holds by construction.** A beat for a place draws only claims whose place is in that
   place's **subtree**, within the interval — so a Caraballeda beat cannot wander into Macuto, and
   a state-level toll does not leak into a parish beat (La Guaira is Caraballeda's *ancestor*, not
   in its subtree).
3. **Deterministic, not generative.** The Spanish is composed from claim fields by a
   template/grammar per `kind` + light connective tissue — **no LLM over the LLM**. Same claims →
   same beat, re-derivable at any time.
4. **The person red line is inherited, and rendering is where it bites.** A private person shows by
   **handle** (approved) or **role**, a minor by **role only**, never a raw name — and a
   person-status account (trapped/rescued/missing/dead) is **gated** until a human approves.
5. **A coarser beat is written from the same claims over a wider interval — never from the finer
   beats beneath it.** No account-from-account; nothing a lesser telling got wrong compounds upward.

---

## A rendered example — a Caraballeda day-beat from the real claims

The claims in scope (place inside Caraballeda's subtree, first days) rendered to prose:

> **En el edificio OPP 25, en Tanaguarena,** los equipos de rescate trabajaron para sacar con vida
> a **Aaron C., un hombre de 21 años**, tras 106 horas atrapado bajo los escombros;⁽¹⁾ en el mismo
> edificio fue recuperado el cuerpo de otra persona.⁽²⁾ **En Residencias Caribe,** que colapsó tras
> el terremoto,⁽³⁾ se buscaba a **una mujer y a su sobrina**⁽⁴⁾ y a **una maestra** que residía en
> el piso 9.⁽⁵⁾ **En Caraballeda,** un equipo de la USAR de El Salvador rescató con vida a **una
> mujer**.⁽⁶⁾

Excluded from *this* beat, correctly, by scope: the **official toll** ("1.943 fallecidos … en el
estado La Guaira") and the search for **a 9-year-old** — both carry a place (La Guaira estado) that
is Caraballeda's *ancestor*, not in its subtree; they belong to a **La Guaira beat**. Julio's
disappearance ("cerca de Caraballeda") is **unplaced** (relational), so it renders only in an
event-wide beat, not a parish one — until a human resolves its place.

---

## Scenarios (the hard rendering questions)

### A. Person shown by handle, role, or withheld — gated by approval
Aaron (approved) → **"Aaron C., un hombre de 21 años"**. Yaneth + Shaznay (not yet approved) →
**roles only**, "una mujer y su sobrina". A 9-year-old → **"un niño de 9 años"**, role only, always.
**[OPEN] The gate question:** for an *unapproved* person-status claim, does the public beat (a)
render it **role-only** (dignity-safe, the happening still told), or (b) **withhold it entirely**
until approval? `person.md` says "no such claim is public until a human approves" — which reads as
(b). **[PROPOSAL]** two renderings from the same claims: a **review beat** (everything, handles
shown *pending*, for the console) and a **public beat** (approved persons by handle; unapproved
person-status claims withheld; non-person claims — collapse, toll — always shown).

OPERATOR RESPONSE: Let’s not gate _YET_ by approval, I need to be able to review and understand the potential, limitations and risks by inspection. I like a lot the idea of a preview/public beat, keep that focus on a process that is not a cop, not a blocker, but a continuos refinement. Note that for the future iterations please.

### B. Anaphora — a person across several claims
First mention: full handle + role ("Aaron C., un hombre de 21 años"); later mentions in the same
beat: **first name or pronoun** ("Aaron", "él"), never re-introducing the role. **[OPEN]** how far
does anaphora reach — within one beat only, or across a person's arc? **[PROPOSAL]** within one
beat; a coarser beat re-derives its own anaphora from scratch.

OPERATOR RESPONSE: Agreed, good call.

### C. Status threading — the world moved
Julio: **desaparecido** → (later) found. **[OPEN]** does the beat show the **current** status, the
**arc** ("estuvo desaparecido cinco días; fue hallado con vida"), or both — and does it depend on
grain (an hour beat shows the moment, a day beat the arc)? **[PROPOSAL]** the beat renders the
**current** claim; the arc is shown only when both states fall inside the interval.

OPERATOR RESPONSE: That’s a great question, I would say that for this iteration we stick to the current state, and we explore later how to enhance the narrative arcs. This is a really powerful proposal, take note of it.

### D. Grouping & connective tissue
**[PROPOSAL]** group in-scope claims by **sub-place** (OPP 25 · Residencias Caribe · Caraballeda-
wide), each group ordered by `first_seen_at`, rendered with light connectives ("en el mismo
edificio", "además"). Not a bare list, not free prose — a fixed skeleton. **[OPEN]** group by
sub-place, or strictly chronological across the whole beat?

OPERATOR RESPONSE: Honestly not sure, lets go with the simplest thing that can work and leave proposed options to explore later written down.

### E. What gets dropped
A beat "may leave out the lesser ones." **[PROPOSAL]** drop claims below a confidence floor, and
render an **overstated/unsupported** claim (the support gate's verdict) either attributed
("según un reporte sin confirmar") or not at all — never as plain fact. **[OPEN]** the floor, and
attribute-vs-omit for unsupported.

OPERATOR RESPONSE: "según un reporte sin confirmar” and similar, should do the trick, let’s try this and check if it actually works seeing the whole thing.

### F. Multi-place claim
A claim spanning siblings ("OPP 22 y 24") → **[PROPOSAL]** rendered once, naming both places
("en los edificios OPP 22 y 24"), under whichever sub-place group it best anchors.

OPERATOR RESPONSE: Agreed.

### G. Citations — the beat is not evidence
Every rendered clause traces to its claim, and through it to the **posts**. **[PROPOSAL]** numbered
markers per claim (as above), resolving to the cited posts — the reader can always reach the
evidence. **[OPEN]** per-claim markers (shown) vs per-sentence vs a trailing source list.

OPERATOR RESPONSE: Love it.

### H. Grain ladder
**[PROPOSAL]** build the **day** grain first (the showcase reads in days), hour/minute as later
rungs — each re-derived from the claims over its own interval, never from a finer beat.

OPERATOR RESPONSE: Agreed, good call.

---

## Cross-cutting decisions for feedback

1. **[PROPOSAL] Deterministic rendering** — a template per `kind` (rescate, búsqueda, colapso,
   fallecimiento, cifra …) filling from claim fields, + an anaphora pass + connectives. No LLM.
   Right approach, or do you want a thin generative *polish* pass (which reintroduces LLM-over-LLM
   risk)? OPERATOR RESPONSE: I think this won’t be able to cut it in the end, *BUT* I’m a big fan of squeezing from deterministic approaches as much as possible before switching to the help of LLMs, also we can think this as process. Is we can “advance” this process deterministically 90% and leave preprocessed options for the LLM, that could be a great optimization.
2. **[PROPOSAL] Two renderings** — a review beat (all, pending handles) and a public beat (approved
   only). Agree? OPERATOR RESPONSE: Let’s go full publi now, but this idea is gold.
3. **[OPEN] Status:** current vs arc (Scenario C): OPERATOR RESPONSE: Current for the moment.
4. **[OPEN] Grouping:** by sub-place vs chronological (Scenario D): OPERATOR RESPONSE:  Again, not sure.
5. **[OPEN] Drop/attribute** rules for low-confidence and unsupported claims (Scenario E): OPERATOR RESPONSE: As answered before
6. **[PROPOSAL] Grain:** day first. Agree? OPERATOR RESPONSE: YES!

**How to give feedback:** mark up any scenario or decision, or rewrite the example prose in the
voice you want the memorial to read in — that voice is the spec I'll build the templates against.
