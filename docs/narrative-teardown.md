# The Narrative Layer — Teardown & the Claim Redesign

**This is a map for line-by-line validation, not a decision.** It captures a
critical read of the old app's narrative/extraction output, the root cause it
exposes, and a proposed redesign (Claim first-class). The **[OPEN]** items are as
much the point as the settled ones. Annotate freely (#TODO / #ANSWER).

**Session:** 2026-07-25. Continues the "agent as the product" pivot — the in-app
research agent is the deliverable; the June 2026 litoral-central earthquake is its
proving ground / eval. See also `kickstart-runs.md` (the execution layer this
narrative work sits above).

**Markers:** **[SETTLED]** decided this session · **[PROPOSAL]** my recommendation,
to beat up · **[EVIDENCE]** measured against the old DB · **[OPEN]** nobody has
answered yet.

**Drafted this session (review-ready, all `planned`, no code):** the vocabulary is
now written as concept pages — `docs/pages/claim.md` and `docs/pages/beat.md` — with
their hub lines in `ubiquitous-language.md` and a cross-link from
`open-when-two-posts-say-the-same-thing.md` (the Claim is the word that open question
was waiting for). Review the vocabulary *whole* before any code, per the doc-first gate.

---

## 1. What this session settled

| # | Decision | Value |
|---|---|---|
| 1 | **North star** | The **agent is the product**; the earthquake record is its eval harness. |
| 2 | **Canonical app** | `wekui-new` (Ash). Old `wekui` (Ecto) is engine-of-record to *mine, then retire*. |
| 3 | **Build strategy** | **Vertical slice**: port only what one research request needs; agent drives from day one. |
| 4 | **First slice** | **Caraballeda, first 24h.** Distinctive anchor; Cronista left baseline numbers here to grade against. |
| 5 | **Corpus** | **Seed-first**: import the slice from old wekui (facts are immutable — legitimate to import). Live acquisition (gated spend) is a *later* increment. |
| 6 | **Deliverable reach** | Answer **+ minimal narrative** — because the narrative is the hard problem the honesty thesis lives or dies on. |
| 7 | **Narrative remodel** | **Claim first-class, piloted** on Caraballeda-24h. Not a whole-record rebuild. |
| 8 | **Claim shape** | **Semi-structured** (fields + supporting posts); Spanish prose *rendered last*. |
| 9 | **Spend authority** | **Gated**: agent plans/reads freely; any credit-spending action pauses for human approval (HITL). |

---

## 2. The teardown — what the old narrative layer actually produced

The old `beats` table holds `minute` "milestone facts" (extraction prompt) and
`hour`/`day` prose (narrative prompt), keyed one-current-per-slot on
`(event_id, COALESCE(place_id,0), granularity, t_start)`.

### 2a. [EVIDENCE] Redundancy that the model cannot even name as redundancy

One rescue — *"un joven de 21 años rescatado tras 106 horas del edificio OPP 25 en
Tanaguarena"* — appears as **15 current minute-facts across 8 place_ids and 3 days.**

- *Some* fanout is by design: `narrative.run` runs per `--place`, so a rescue is
  in-scope for the building, its sector, its parish, and event-wide.
- But inside that: building **"Edificio OPPPE 25 G" (place 120) holds 6 current
  copies** (22:00, 04:00, 12:01, 12:03, 15:18, 05:28) — same fact, same place, six
  minute-slots. The unique index only blocks collisions at the *same* `t_start`;
  the prompt's "already told" dedup leaked completely.
- And it rides along with **place errors**: the same rescue is attributed to
  *"Opppe 22 Caribe"* (a different building), to *"Edificio OPP 25"* (place 530 — a
  **duplicate gazetteer node** for the same OPP 25 as place 120), and to
  *"5 de Julio"*.

**The disease:** the model has **no way to say "these 15 rows are one fact."**
Nothing is dedupable or correctable as a unit. (A crude 40-char-prefix scan flagged
559/3185 minute-facts as "near-dup," but that over-counted — the 12 *"Se reporta la
desaparición de una mujer…"* rows are **12 different missing women** sharing a
templated opening. Real dedup must be **semantic**, not surface. Note that too: the
extractor is **formulaic**, which makes distinct facts look alike.)

### 2b. [EVIDENCE] "Unsupported narrative," at confidence 0.95, through every gate

Hour beat **11048** (Caraballeda, conf 0.95), 5 cited posts. Four claims check out
(the 1.943/10.571 balance → post 4746; a niño de 12 años → 10271; RocaPark esperanza
→ 13074). But:

> *"Las zonas más afectadas por colapsos de edificios eran **Playa Los Corales,
> Playa Grande, Puerto Viejo y Playa Caribe**…"* — **in none of the cited posts.**

The nearest citation (post 4745) is real-estate chatter about upscale neighborhoods
— **noise**. And the niño de 12 años is in **Macuto**, a *different parish*, inside a
beat scoped to **Caraballeda**. So one beat **fabricates a fact**, **cites noise**,
and **breaks its own place scope** — and passes every gate.

**Why the gates miss it:** `apply_coerced_draft` checks citations *non-empty*,
*subset of offered*, *valid confidence*, *no private names*. **None checks whether
the prose is entailed by the evidence, or stays in scope.** Citation *presence* ≠
citation *support*.

### 2c. Root cause — one table, four concerns, wrong identity

The `beats` row conflates four things and keys identity on `(place, granularity,
t_start)` — which is **none** of what identifies a fact:

| Conflated concern | What it should be | Failure it causes |
|---|---|---|
| The atomic **claim** (a state-change) | its own identity = the event itself | can't dedup; ×6 copies; can't correct as a unit |
| The **place scope** | a *link*, resolved up the tree by query | fanout re-*stored*, not referenced; misattribution |
| The **time position** | an *attribute* (first-evidence time) | one fact spread across minute-slots = dup |
| The **prose rendering** | a *re-derivable view* | LLM-over-LLM rollups compound embellishment |

### 2d. What is good — keep it, do not throw the craft away

- Prompt **evidence-discipline**: "volume is not novelty," "attribute uncorroborated
  as claims," **null / empty is the correct answer** when material can't support one.
- The **person gate** — genuinely *mechanical* (a name-vocabulary diff against
  gazetteer + public-figure allowlist; F54). Keep verbatim.
- The **deterministic rejection vocabulary** (F34): every failure is one of a fixed
  set, logged live. Port this discipline directly.
- The **subset gate** (can't cite evidence it wasn't shown) and **content-addressed
  prompts / event pins**.
- The **density-tiered rollup** instinct.
- `narrative.dupes` clustering **was already built** — but `absorb` (applying it)
  was "deliberately unbuilt until the operator reviewed real proposals." You already
  sensed the dup problem; you just never closed the loop.

---

## 3. [PROPOSAL] The redesign — separate the Claim from the rendering

### 3a. Two objects instead of one

- **Claim** — one atomic, deduplicated, evidence-anchored **state-change**. The
  OPP-25 rescue is *one* Claim: linked to a building, anchored at first-evidence
  time, carrying its supporting posts. **Semi-structured** [SETTLED #8]:

  ```
  Claim
    actor/role      "un hombre de 21 años"        (never a private name — the F54 gate applies here)
    action/type     rescate | colapso | desaparición | cifra_oficial | ayuda_llega | infraestructura | …
    place_id        → the most specific place (Edificio OPP 25)     — a LINK, not stored fanout
    magnitude       {horas: 106} | {fallecidos: 1943, heridos: 10571} | …
    status          rescatado | desaparecido | fallecido | en_curso | …   (threadable: desaparecido→hallado)
    first_seen_at   the effective time of the strongest citation      — an attribute, not the identity
    confidence, method(worker|manual), prompt/actor pin, supporting posts[]
    prose?          optional short free-text nuance the fields can't hold   [OPEN — see §5]
  ```

- **Beat = a rendering** — prose composed **from claims** for a scope + interval +
  granularity, always re-derived from the *verified claim layer*, **never**
  LLM-over-LLM. A coarser rollup is the same claim-set rendered over a wider interval
  — no compounding, because prose is never drafted from prose.

### 3b. How it dissolves each failure

| Old failure | Under the Claim model |
|---|---|
| ×6 copies at one building | One Claim; re-extraction **merges** into it (evidence appended), never a new row. |
| ×15 across scopes | The Claim links to *one* place; parent scopes are a **subtree query**, not stored rows. |
| Place misattribution / dup nodes | A single correctable `place_id` link, not baked into N prose rows. |
| Fabricated "zonas más afectadas" | The rendering step is **constrained to see only the claim set, not raw posts** — so it can't invent a fact, only mis-word one, checkable against the claim fields. **If the renderer is handed post texts, invention returns** — so this constraint is load-bearing (§5 #4). |
| Macuto inside a Caraballeda beat | **Scope by construction — *given a correct place link*:** a Caraballeda rendering pulls only claims whose place is in the subtree, so the out-of-scope *pull* is impossible. A *wrong* link (OPP-22) is **relocated to one correctable field**, not eliminated. |
| Templating / formulaic prose | Attacked at the source: the verifiable content is *fields*; prose is a final rendering, not the unit of extraction. |
| Missing→found told as two facts | A **status transition** on one Claim (supersede/update), not two rows. |

### 3c. The seam — how Claim relates to the built judgment cluster [PROPOSAL]

A **judgment** answers a question about a *post* (whether/what/where/who/when). A
**Claim** is a *synthesis about the event*, citing posts. So a Claim is **not a
judgment kind — it is a layer above judgments**, but it **reuses the judgment DNA
verbatim**: append-only, superseding, `method`, actor/prompt pin, confidence,
provenance (the same mechanism the agent-pin already generalized in `kickstart-runs`).
A Claim's fields *draw on* judgments — its place is the **Where** of its cited posts,
its type/themes the **What**, its time the **When** (effective time). Claim **sits on**
the judgment + taxonomy layers; it does not replace them.

### 3d. The support gate — honest about what it can and can't be [SETTLED #9 + PROPOSAL]

The person gate is a *vocabulary* check; **entailment has no vocabulary to diff
against**, so a support gate is **necessarily an LLM-judge pass — probabilistic, and
it needs its own eval.** [PROPOSAL] a two-tier gate matching gated-spend/HITL:
**(1)** a cheap LLM-judge checks each claim's *fields* against its cited posts
("status=rescatado? horas=106? place=OPP25?") and flags unsupported spans; **(2)**
for a **public, donation-facing memorial**, a human confirms before anything
publishes. The judge's own accuracy is measured against Cronista's hand-verified
record (F50-style ground truth).

---

## 4. [PROPOSAL] The lean pilot — Caraballeda-24h, cheapest path to a real agent

The pilot can **skip porting acquisition and the judge pipeline entirely**:

1. **Seed** only the *relevance-accepted* Caraballeda-24h posts from old wekui, **with
   their existing What/Where judgments** (and When where divergent). "Capture is not
   evidence" is honored because we import only accepted posts. This defers porting
   `whether`/`when` as full concepts *and* the acquisition + judge pipelines — **but not
   `where`.** The imported Where links carry the very errors §2a exposes (place 120 vs
   the duplicate node place 530 for the *same* OPP 25; the OPP-22 misattribution). So
   step 1 includes a **place-reconciliation pass** — de-duplicate gazetteer nodes and
   quarantine known-bad links — or the Claim layer gets graded on a corpus whose places
   are known-wrong. A clean place baseline is a **precondition** of the pilot, not a
   freebie. The Tavily / Nominatim **location-assist tools** (`agent-architecture.md` §5)
   are what would perform this reconciliation — de-duplicating gazetteer nodes, anchoring
   colloquial names — under the human gate.
2. Build the **new** hard part in `wekui-new`: **Claim** (extract → merge/dedup →
   support-verify) + **Beat rendering** + the read surface for the cited answer.
3. Stand up the **agent** over cheap-inference tools only — extract-claims,
   review-merge, render, report/read. **No X spend in the pilot** → gated-spend risk
   is zero while the loop is proven.
4. **Grade the merge step against ground truth already in the record** — a concrete
   pass condition defined *before* the step is built, not "by eye": the **15 OPP-25
   rows must collapse to 1** claim, and the **12 *"…desaparición de una mujer…"* rows
   must stay 12** distinct claims (zero false collapses). That is a hand-labeled
   precision/recall pair the merge judge must pass. Then grade the rendering's support
   against Cronista's hand-verified set. Only then: live acquisition, then generalize
   past Caraballeda.

**What this pilot deliberately does NOT build:** the runner/clients, the judge
pipeline, `whether`/`when` vocabulary, week-granularity, person entities (still
BLOCKED per TIMELINE_VISION), multi-user/curator tooling.

---

## 5. [OPEN] The questions this redesign now owes an answer

**Priority is not list order.** #1 (merge key) gates pilot step 2 and must be answered
*before* building. #6 (runtime) gates step 3. **#2–#4 are better answered *by* the
pilot than before it** — don't spread the annotation pass evenly across all seven.

1. **Claim identity / merge key — now grounded in the corpus.** Two extractions are the
   same claim when their *distinguishing signature* matches, **weighted by specificity**
   — the finding the data forced. The OPP-25 rescue must merge to **1** *across* a
   duplicate gazetteer node (place 120 vs 530) and outright misattributions, because
   *man-21 / 106h* is specific enough to carry identity through place noise; the
   **981-post missing-woman set** (`open-when-two-posts-say-the-same-thing`) must **not**
   merge, because *una mujer* is generic and only `place` distinguishes. So merge is an
   **LLM judgment over structured claims**, prompted with the specificity rule, fronted
   by a cheap deterministic **pre-filter** (same What/theme + overlapping place-subtree +
   time proximity) that cuts the pairs it adjudicates. **Eval, defined before building:**
   (a) OPP-25 rescue → 1; (b) the 12-in-slice / 981-in-corpus missing-women → stay
   distinct (zero false collapses); (c) the false-*split* guard — Hotel Eduard's Suites'
   **12 `colapso` minute-facts at one building** → the true count of distinct
   collapses/updates (needs a hand-label), so the judge is graded against over-merge too.
   The concept is written: `docs/pages/claim.md`.
2. **Claim ↔ place granularity.** A rescue links to a building; a "state balance:
   1943 fallecidos" links to La Guaira *state*. Claims live at different place levels
   — fine, but the rendering's subtree query must handle a claim whose place is an
   *ancestor* of the rendered scope.
3. **Status threading.** desaparecido→hallado: new Claim linked to the old, or a
   supersession of one Claim? (The old extractor punted: "an update is a new fact.")
4. **Rendering prompt.** Does prose still need an LLM to write connective tissue over
   the fixed claim-set (yes, probably) — and is *that* output also entailment-checked
   against the claim texts it was handed?
5. **Where does Claim live in `wekui-new`?** A new `docs/pages/claim.md` concept
   (planned) + a domain (`Wekui.Narrative`? `Wekui.Output`?). Doc-first gate applies.
6. **Runtime — parked, now due.** [PROPOSAL] `ash_ai` to expose Ash actions as agent
   *tools* (+ structured/prompt-backed actions, MCP) **+ `sagents`** for the
   interactive loop, HITL approval gates, subagents, LiveView streaming. Bare Elixir
   LangChain is the fallback if sagents proves too heavy. Decide before building the
   agent, after the Claim substrate shape is fixed.
7. **Thin-agent boundary.** Draft split — *deterministic Ash*: scope/query planning,
   the merge/dedup mechanism, coverage/density/richness computations, the person +
   support gates, the rendering write-path. *Agent judgment*: request→scope, "what to
   fetch next" under budget, reading the statistician's outputs to decide
   saturate/steer/stop, and orchestrating the extract→merge→verify→render loop.

---

## 6. Anthropic guidance this leans on (July 2026)

- **Context engineering** — smallest high-signal token set; tools & their docs
  designed deliberately. The Claim fields *are* that curation for the rendering step.
- **Verification gates, not self-declaration** — the support LLM-judge and the
  Coverage/Density/Richness gates are exactly this; Cronista's numbers are the eval.
- **Long-running harness** — progress/receipt files, checkpoint/resume, don't
  one-shot. Maps onto the Run receipt (`kickstart-runs`) and cursor-resumable work.
- **Mechanical gates over prompt rules** — the whole F54 lesson; put invariants in
  the write path with a report to re-check, keep the agent thin.
