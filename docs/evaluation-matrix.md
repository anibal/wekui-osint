# Evaluation Matrix — the whole system, honestly

**A step back after the core extraction layer went live.** Where every layer stands, how
it was proven, and — separately — how we will judge whether the *record itself* is good.
Written to be argued with; the ratings are mine, change them.

**Revised 2026-07-27:** the *write-back* half now exists too — a person's answer to the report
lands as an attributed, append-only **curation act** (who, when, what changed, why), in one
transaction with the change it attributes, and the report reads its own acts back so a settled
question stops being asked. `open-actor`, open since 2026-07-22, is closed.

**State in one line (revised 2026-07-26):** the whole read path — public posts → structured,
dignity-safe, evidence-cited **claims** → gazetteer places → a support verdict → the Spanish a
reader meets — is built, orchestrated into **one auditable run**, and **proven end to end on real
data with the real model**: 9 posts → 8 claims → 7 of 8 mentions linked → 8/8 supported → a cited
5-clause Caraballeda beat, in one receipt (`7bb0dcc3`, 23 seconds, pennies). What's missing is
what services it: the review console, the merge-judge, the LLM polish, a reader UI, and live
collection.

Legend — Status: ✅ built · ◐ partial · ○ planned. Proven: **live** (real DeepSeek + real
posts) · **unit** (test suite) · — (not yet). Confidence: H / M / L.

---

## A. Capability maturity

| Layer | Status | Proven | Conf | Key gap / risk | Next |
|---|---|---|---|---|---|
| Domain records (Event, Place, Post, Author, judgments) | ✅ | unit | H | — | — |
| **Claim** (structured account) | ✅ | **live** | H | prose-vs-fields boundary settled; kind is an open string (by design) | — |
| **Person** write-path (identity, handle, gate, arcs) | ✅ | **live** | H | handle heuristic fallible on 3-token / particle names (escape hatch covers) | — |
| **Person red line / gate** | ✅ | **live** + unit | H | subject now **strict** — no name ever, not even a public figure (the Montero hole, closed); nuance lenient | — |
| Claim **merge** (dedup, deterministic) | ◐ | unit | M | the *merge-judge* (WHICH two are the same) is NOT built → cross-batch dup recurs at scale | build the merge-judge (specificity rule) |
| **Extraction prompt** (v5) | ✅ | **live** | M–H | MoE non-determinism; low-confidence noise leaks (self-labeled) | multi-pass; keep in the loop |
| **Extraction pipeline** (posts → claims) | ✅ | **live** | H | best-effort per claim (not transactional) — a crash leaves partial claims, now visible as a `:running` receipt | — |
| DeepSeek worker client | ✅ | unit | H | single-shot, no retry (caller owns) | retry/backoff when at scale |
| **Place mapping** (place_mention → gazetteer) | ✅ | **live** | M | an exact hit on a curated alias wins outright and never consults ancestors, so an ambiguous short name ("Residencias Caribe") links at 0.9 — 3 of 8 live claims do; and a mention matching nothing stays honestly UNRESOLVED with no ClaimPlace at all (1 of 8) | disambiguate alias hits by ancestors; a gate queue for low-confidence links; Tavily/Nominatim for the leftovers |
| **Support gate** (entailment: do the posts bear the claim?) | ✅ | **live** | M | flag-only (records a verdict, withholds nothing); judge prompt is an un-iterated v1 (answers in English); no console services verdicts | iterate the judge prompt; wire into the review flow |
| **Beat rendering** (claims → the story a reader reads) | ✅ | **live** | M–H | deterministic templates on an open `kind` — wording is serviceable, not polished; one ordering defect found and fixed by orchestrating it | the LLM polish rung over the structured clauses |
| **Orchestration** (the read-path run + its receipt) | ✅ | **live** + unit | H | records three gate queues, pauses at none; a **fourth queue is missing** — place links below a confidence threshold go unmentioned; no re-extract until the merge-judge lands | add the low-confidence-link queue; pause points arrive with the review console and the spend gate |
| **Talking agent** (conversational driving, tools, HITL) | ○ | — | — | runtime deliberately undecided; the read path needed none, having no agentic decisions | decide the runtime at that rung |
| Live acquisition (X collection, spend-gated) | ○ | — | — | pilot runs on a seeded corpus; no live spend yet | the runner + X client, gated |
| **Curation** (a human's act, attributed) | ✅ | unit | H | every verb records who/when/what/why in one transaction with its change; the report reads its own acts back and stops re-asking. No UI: the surface is a code interface + a dated script | the review console, when a UI is wanted |
| Human-review workflow / UI | ◐ | — | — | the *workflow* now exists end to end — report asks, human answers, `Wekui.Curation` applies it attributed, report stops asking. What is missing is only the **interface**: today it is a markdown file and a script | a LiveView review console |
| Read / timeline UI | ○ | — | — | nothing to look at but the DB | port feed/timeline after Beats |
| whether / when judgments (relevance, time) | ○ | — | — | seeded = accepted; time via posted_at | port when the corpus needs it |

---

## B. How we judge the record is *good* (the output dimensions)

The original frame was **Coverage · Density · Richness** (acquisition). Building the honest
record surfaced four more that matter just as much. For each: what it measures, the evidence
today, and the metric or gate that will measure it going forward.

| Dimension | Measures | Evidence today | The measure / gate | Conf |
|---|---|---|---|---|
| **Dignity & safety** | no private name shown; minors; public figures; human gate | live: 0 leaks, minors held, all pending-review — and the subject is now **mechanically** name-free (strict gate), not reliant on v5 | strict `NoPrivateName` on subject + `names[]==[]` for minors | **H** |
| **Honesty (support)** | the claim's assertion is *entailed* by its cited posts | **live: verify passed all 9 real claims and caught a deliberately-overstated control** | the **support gate** (LLM-judge) — built, flag-only; v1 prompt un-iterated | **M** |
| **Recall** | the real happenings are captured | live: caught deaths + a hidden collapse; noise dropped | precision/recall vs Cronista's hand-verified set | **n/m** |
| **Precision** | no fabricated or noise "happenings" | live: real-estate dropped; analysis self-labels low-conf | confidence filter + human review; false-claim rate | **n/m** |
| **One claim per happening** | no duplication across posts/batches/scopes | live: within-batch dedup works (Aaron 2→1) | merge-judge eval: OPP-25→1, 981 missing-women→distinct, Hotel Eduard's→guard over-merge | **n/m** |
| **Coverage** | how much of the window/scope is collected | n/a (seeded) | `report.coverage`, completed latest-mode queries | — |
| **Density** | λ(t), the story's pulse | n/a (seeded) | posts/claims per time bucket | — |
| **Richness** | how representative the sample is | n/a (seeded) | Good–Turing, capture–recapture, saturation | — |
| **Reproducibility** | same input → stable output | live: single-pass drops vary (MoE) | N≥3 passes; the merge-judge + human catch drops | M |

**n/m** = *not measured* — an impression from a single 9-post live run, not a metric. Turning
these three into numbers against Cronista's hand-verified record is itself a task (§C.6, §D).

---

## C. Top risks & unknowns

1. **Honesty is now checked, not yet enforced.** The support gate is **built and live-proven**
   — it verified all 9 real claims and caught a deliberately-overstated control. But it is
   **flag-only** (records a verdict, withholds nothing), its judge prompt is a first draft
   (un-iterated, and it answers in English), and nothing services the flags yet. Enforcement
   needs the review console + a publish path that keys off `support == :supported`.
2. **The dignity gate hole — CLOSED (2026-07-26).** The subject field is now **strict**:
   `NoPrivateName` rejects any person name there, including an allowlisted public figure (the
   Montero shape), so dignity is mechanically gated rather than resting on the model behaving.
   The nuance stays lenient (a public official may be named). Dignity is now the one solidly
   gated property.
3. **Dedup does not scale yet.** The deterministic merge exists; the *judge* that decides what
   to merge does not — so across many batches/scopes the OPP-25-style duplication returns.
4. **The human gate is a workflow now, but not an interface (2026-07-27).** `pending_review` is
   serviced end to end: the report asks, a person answers, `Wekui.Curation` applies the answer
   with **who, when and why** in one transaction, and the report reads its own acts back and
   stops asking. Two things are still missing — an interface better than a markdown file and a
   script, and the fact that a *machine* can still call the underlying actions directly, so
   attribution is a discipline of the curation surface rather than something the resource
   enforces on every caller.
5. **Place is text, not geography.** Until `place_mention` is mapped, the place-tree (subtree
   rollup, "filter to Caraballeda") — a core showcase feature — doesn't work on claims.
6. **Everything rides on a small model's judgment.** DeepSeek-Flash is good but fallible and
   non-deterministic; the gates + human review are the real backstop (the thin-agent thesis),
   and two of those gates aren't built.
7. **No numbers against ground truth — the loudest gap.** Every "M" and win in §B is a
   *qualitative read of one 9-post run*, not a measurement. We have no precision/recall/dedup
   figures against Cronista's hand-verified Caraballeda record. *Measure, never assert* — until
   that pass runs, this matrix is a considered opinion, not evidence.

---

## D. Critical path to the Caraballeda showcase (the north star)

Roughly in order, what stands between here and a shippable, donation-facing Caraballeda story:

1. ~~**Human-review console**~~ — the *loop* is built (2026-07-27): the report asks, a person
   answers, `Wekui.Curation` applies it as an attributed act, the report stops asking. What is
   left of this item is the **console** itself — an interface instead of a markdown file — plus
   the publish path keying off `support == :supported` + person `approved`. Worth doing when
   the record is big enough that a file stops being readable in one sitting.
2. ~~**Place mapping**~~ — built: deterministic resolver + ClaimPlace, live on the real tree.
3. **Merge-judge** — so one happening is one claim across the whole corpus. Also what would let
   a run re-extract safely rather than skipping.
4. ~~**Beat rendering**~~ — built and orchestrated; the **LLM polish** over its structured
   clauses is the remaining half.
5. **Read UI** — the timeline, place-filterable. The run receipt is the other thing worth a
   screen: it is the product's audit surface.
6. **(then) live acquisition** — grow the record, behind the spend gate.

A measurement pass against Cronista's hand-verified Caraballeda set should run *alongside* 1–3
to turn the qualitative reads in §B into numbers (§C.7).

---

## E. Cost — inference is cheap; acquisition is the constraint

The original frame was economic ("brute-forcing chronologically is not economical"). With real
numbers now in hand, the shape is clear — and it's the *opposite* of where the caution was
aimed:

- **Extraction (inference):** a batch runs ~1.4–2.8k tokens on DeepSeek-Flash. The old corpus
  is ~13k posts; in batches of ~10–15 that's ~1k batches ≈ low single-digit **millions of
  tokens** → **a few dollars** for the whole Caraballeda corpus (Cronista did the old runs "for
  DeepSeek pennies"). Judging is cheap.
- **Place mapping (Tavily):** ~$0.016/lookup × the ~350 Caraballeda places ≈ **$5–6**, one-time,
  and inside Tavily's free tier.
- **Acquisition (X credits):** this is the real spend and the reason for "inspect before spend"
  — but the pilot runs on a **seeded** corpus, so it's **$0 today**. It only appears when live
  acquisition lands.

**Implication for sequencing:** the honesty/quality layers (support gate, merge-judge, rendering)
cost near-nothing to run and re-run — so iterate them freely against the seeded corpus. The
gate that guards money is for *acquisition*, which is deliberately last.
