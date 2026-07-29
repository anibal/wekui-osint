# Mechanisms — how a question stops reaching a human

*Written 2026-07-28, after the operator said: "I am not answering that many questions
about places, this will take forever and it is not the point. The point is how we
develop mechanisms."*

Markers: **[PROPOSAL]** = my recommendation, overrule in a word. **[OPEN]** = I need
your answer. **[MEASURED]** = counted, not argued. **[BUILT]** = shipped.

---

## 1. The rule this document exists to enforce

> **Human attention is bounded. Machine attention is not.**
>
> The number of decisions the record asks a person for must stay roughly CONSTANT as
> the corpus grows. Anything that grows with the corpus is a mechanism's job, and a
> question that grows with the corpus is a defect in the mechanism above it.

The report asked 21 questions about **107 posts**. The corpus holds **6,982**. Linear
scaling means ~1,300 questions, and that is the end of the project — not because
anybody refuses, but because a person cannot be a subroutine.

## 2. [MEASURED] What the questions actually were

I looked at the fifteen low-confidence place questions the report was asking. **None
of them was the operator's to answer.**

| what it really was | count |
|---|---|
| the resolver's own proposal, asked about a second time in a different costume | **10** |
| a parse defect — half of real mentions run coarse-to-fine and were read backwards | **3** |
| a ruling the operator gave on 2026-07-27 that reached one module and not the other | **1** |
| a genuine ambiguity that needs a human | **1** |

Three fixes, no model, no API, no human: **21 questions → 11, and the place queue
15 → 5.**

The lesson is not "the resolver had bugs". It is that **a question is the last
resort, and we had been using it as the first.** Uncertainty was being treated as a
reason to stop rather than a reason to try harder.

## 3. [PROPOSAL] The ladder — cheapest first, human last

Every question passes down this ladder. It reaches a person only after everything
above has failed, and it reaches them **as a pattern, never as a row**.

| # | mechanism | cost | what it is good at | example from this record |
|---|---|---|---|---|
| 1 | **Deterministic evidence** | free | anything the record already knows | the numeral rule; corpus co-occurrence; handle collisions |
| 2 | **Structural repair** | free | the question is a defect | the parse direction; pruning stale links |
| 3 | **External corroboration** | quota | "does this exist in the world" | Tavily / Nominatim / OSM on an unresolved building |
| 4 | **Audit prompt** ✅ **[BUILT]** | cents | one narrow, checkable question about one artifact | `Wekui.Pipelines.ResidueAudit` — "does any theme already cover this?" |
| 5 | **Adversarial prompt** | cents | a confident answer that is wrong | "REFUTE this place match. Default to refuted if unsure." |
| 6 | **Independent panel** | cents×N | is the structure real or the reader's? | the three-reader taxonomy spike: 58–67% above chance |
| 7 | **A person** | irreplaceable | meaning the data cannot supply | *"Caraballeda is the parish"*; *"a death and a body are two facts"* |

**Rungs 1 and 2 are free and were never tried.** That is where the whole of §2 lived.

### The two rules that make the ladder work

- **A ruling must travel.** The operator's numeral rule lived in `Gazetteer.Duplicates`
  and not in `PlaceResolver`, so the same mistake it had already fixed kept generating
  questions. A rule that has to hold in two places is now written in neither of them —
  it lives in `Wekui.Gazetteer.Marks` and both read it. **[BUILT]**
- **A pass owns its whole output.** `link_place!` is an upsert, so the resolver only
  ever added: a claim accumulated every place it had ever guessed at, and the report
  asked which of the machine's own two guesses it had meant. A pass now retracts what
  the current reading does not support. **[BUILT]**

## 4. [PROPOSAL] What reaches the report changes shape

From **a queue of questions** to **a sample of decisions**.

Today: *"A place link the resolver is unsure of (0.5)"* × 15.
Instead: *"The resolver placed 49 mentions. Six were ties it broke on corpus
co-occurrence — here are three, spot-check them."*

- **Bounded.** Three spot-checks whether the corpus is 300 posts or 300,000.
- **Auditable.** He is checking the mechanism, not doing its work.
- **Honest.** The decision was made, with its provenance and confidence, and it is
  reversible by one act.

A real question survives only when **no rung could settle it**, and it is presented
**by pattern**: *"six mentions are ambiguous between a parroquia and the sector inside
it carrying its name — one rule settles all six. Which?"* That is one ruling that
becomes a sweep, which is the shape that has worked every time on this project.

## 5. [PROPOSAL] Where each remaining question class goes

| the report asks | rung | what it becomes |
|---|---|---|
| 39 persons at the handle gate | 1 then 4 | collisions and escape-hatch cases only. A clean, unique derivation is auditable, not askable. **The privacy decision stays human — this rung only removes the ones that are not decisions.** |
| 21 claims the support gate flagged | 5 | two independent refuters; agreement resolves, disagreement escalates. The gate is already known to contradict itself. |
| 10 places a machine proposed | 3 then 1 | external lookup, then the old app's gazetteer, then co-occurrence. Only the unverifiable reach a person. |
| 7 mentions that matched nothing | 3 | the web lookup `place-mapping-scenarios.md` has always named as the next step. |
| 4 claim pairs that may be one happening | 5 | adversarial pair judge — argue both sides; agreement resolves. |
| 5 remaining place ambiguities | 1 | corpus co-occurrence: if forty other posts put this building in Los Corales, the barrio is settled by weight of evidence, deterministically. |
| 32 proposed themes | **7** | **stays.** This is the 20% no data supplies, it is one artifact, and ratifying it governs everything below. |

## 6. The loop that closes

1. A mechanism proposes, with its provenance and confidence.
2. Cheaper mechanisms attack it; adversarial and audit prompts try to break it.
3. What survives is **recorded as a decision**, not asked.
4. What does not survive reaches a person **as a pattern**.
5. Their ruling becomes **a rule and a test**, and the rule is written where every
   consumer reads it.
6. Re-measure. The delta answers *did that help*.

Steps 4–6 exist. Step 1 exists. **Steps 2 and 3 are what is missing**, and they are
what "adversarial prompts, audit prompts, searches in different APIs" builds.

## 7. What must never be built

A loop where a model proposes, a model writes the test, and a model grades it is
closed: both sides can share one wrong prior and converge confidently on nonsense.

The anchor is **real posts** — text a family actually wrote. A model may label,
cluster and propose over them; every score is computed against the world, and every
negative test case is a real post. Independence beats iteration: three readers
compared by code told us more than one reader iterating three times ever could.

## 7b. [MEASURED] What the ladder has actually done

Rung 4 is built and in the sweep. On 18 accumulated residue entries it found **17
already covered** — at 17 themes the residue was the corpus asking for words; at 45 it
had become the extractor failing to find them. Since then the audited residue has held
near **1 entry per 100 posts** across ~2,000 posts.

The rule that makes it safe: it may only REMOVE an entry, never add or rewrite one. A
verdict naming a theme that does not exist covers nothing; an entry it does not rule on
stays; unreadable output suppresses nothing. A gap wrongly confirmed costs one glance,
and a real gap suppressed is a word the record never gets.

And rungs 1 and 2 keep paying. Four defects this week were found only by making an
instrument say what it was doing rather than that something happened: a model copying
an id's label (~50 claims lost), a routed topic whose citations were discarded (posts
re-read every sweep), a live-lock on two posts, and the F54 gate refusing 3% of all
claims because names were reaching `subject`. **Three of the four were in instruments
built to detect defects.**

## 8. [OPEN] Order

I would build in this order, each with a measured before/after on the question count:

1. **Corpus co-occurrence** (rung 1, free) — settles place ambiguity by weight of evidence.
2. **Handle audit** (rungs 1+4) — collisions are deterministic; the rest is one cheap prompt.
3. **Adversarial support verify** (rung 5) — the gate needs a second opinion; it contradicts itself today.
4. **External place lookup** (rung 3) — the biggest win, and the only one needing a key and a budget.
