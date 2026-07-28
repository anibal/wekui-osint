# Measuring whether the vocabulary still fits — a process that learns

*Written 2026-07-28, after the operator ruled on the first proposed vocabulary and
asked for "a mechanism to evaluate the ontology and rebalance the tree while more
information is gathered."*

Markers: **[PROPOSAL]** = my recommendation, overrule in a word. **[OPEN]** = I need
your answer. **[MEASURED]** = counted, not argued.

---

## 1. Why this is not optional, in one number

The first vocabulary was read out of **302 posts spanning eight days**. The operator
then ruled on five themes, and **four of the five name things that corpus cannot
contain**: a body recovered versus a death declared, neighbours digging beside the
international teams, the aid chain past the moment of delivery.

He was right, and the full corpus proves it — the sample was simply too thin:

| what he said was missing | in the 302-post sample | in the 6,982 Caraballeda posts |
|---|---|---|
| neighbours | 6 | **215** |
| volunteers | 7 | **177** |
| bomberos | 5 | **143** |
| bodies | 0 for "recuperar el cuerpo" | 136 for "cuerpos", 5 for "recuperar el cuerpo" |
| collection points | **0** | 17 here, **115** across the event |
| displaced / shelter | — | 40 + 24, **and no theme covered them** |

**[MEASURED] And my own filter was wrong.** I seeded only themes that two of three
readers reached. That threshold filters by *sample size*, not by reality: a theme
carrying 0.6% of a corpus appears twice in 302 posts and can easily be found by one
reader alone. It cut `Damnificados y refugio` — 64 posts in the full corpus — and
`Daño estructural sin colapso`, which all three readers actually had but whose
post-sets overlapped too little to pair. Both are back, marked as mine to discard.

So: **any single snapshot under-fits, in both directions.** A vocabulary is not a
thing you get right once. That is the whole argument for this document.

## 2. What "the ontology drifts" actually means — three different things

Conflating them is the trap.

| what changes | example | is it a defect? |
|---|---|---|
| **the mix** | day 1 is pleas, day 6 is donations | **No.** Same words, different weights. This is one of the memorial's best outputs — the arc told by what people spoke about. |
| **new themes arrive** | `homenaje`, `reconstrucción`, `demanda judicial` | **Yes**, and unavoidable. The vocabulary must grow. |
| **a word's meaning shifts** | `búsqueda` on day 1 is rescuers digging; on day 40 it is a family who still does not know | **Yes, and it is the dangerous one.** |

The third is already answered by doctrine: **a theme's definition never drifts; the
tree grows instead**. A theme whose meaning moved is a *new* theme with the old one
deprecated onto it ([[decision-2026-07-24-merge-is-deprecation]]), because a rule that
shifts under the claims already resting on it is
[[principle-never-rewrite-the-record]] failing quietly. The mechanism below has to
*detect* that case, not permit it.

## 3. [PROPOSAL] Seven measurements, and what each one means

All deterministic. No model grades a model — the model classifies, the code scores.

### 3.1 Residue rate, per time window — *is the vocabulary falling behind?*

The share of posts in a window that fit no active theme. **Flat is healthy. Rising is
the alarm**, and the window it rises in tells you when the corpus moved.

Today, on the spike's own data, it is flat: 4.2% / 8.7% / 4.5% / 4.3% / 0% / 3.4% / 0%
across the eight days, and the 2% all three readers refused turned out to be posts
whose evidence is in an image — a modality gap, not a vocabulary one.

### 3.2 Theme load — *is one theme doing more than one job?*

The share of classified posts carrying each theme. A theme far above its siblings is a
split waiting to happen.

**This already worked.** `Solicitud de rescate o recursos` carried **18.5%** — third
largest of twenty-seven — and the operator split it without seeing that number. The
measurement would have raised the same question, which is the point: it turns his
intuition into something the system can ask on its own next time.

### 3.3 Refusal rate per theme — *is the rule wrong?* **The one that closes the loop.**

Of the claims drafted under theme T, what share does the support gate refuse?

A theme's `applies_when` is a **hypothesis**. The gate's verdict on claims made under
it is that hypothesis's **score**. A high refusal rate means the rule is too loose, or
names the wrong thing, or the boundary with its neighbour is not in the text.

This is what we did by hand three times, expensively, reading notes and rewriting
English. Per theme it becomes a number that can be watched. **It is the difference
between a system that is corrected and a system that learns.**

### 3.4 Confusion between siblings — *is the boundary real?*

For each pair of themes: how often are they assigned together, and how lexically alike
are the posts each takes alone? Two themes that always co-occur may be one. Two that
never co-occur but whose posts read alike have a boundary the rule has not captured —
which is exactly `búsqueda` versus `solicitud de información` before we separated them.

### 3.5 Sibling imbalance — *is the tree the right shape?*

A parent whose children split 90/5/5 is not a family, it is a theme with two
footnotes. A parent with one child is not a parent.

### 3.6 Drift of share over time — *has a theme aged out, or arrived?*

Each theme's share per week. A theme that was 30% in week one and 2% in week eight has
aged out of the live vocabulary (it stays in the record: the claims under it are still
true, and it did happen). One that was 0% and is now 15% arrived while nobody was
looking. **This is the operator's morph, as a number.**

### 3.7 Residue clustering — *what is the corpus asking for?*

Group the unfitted posts. A cluster above a threshold is a proposal for a new theme;
below it, the residue is allowed to stay residue — a prayer, a joke, an opinion
evidence nothing, and that is a correct outcome, not a backlog.

**Cluster first, propose second.** One theme proposed per unfitted post would
industrialise the over-splitting already measured: five spellings of one request.

## 4. [PROPOSAL] What the machine does, and what only you do

| decision | who | why |
|---|---|---|
| classify a post against active themes | LLM | entailment — irreducible |
| **compute every measurement in §3** | **code** | arithmetic over assignments. No judgment, no drift, no cost |
| decide a threshold is crossed | **code** | a stated number, in the report |
| name a candidate theme for a residue cluster | LLM | naming — irreducible |
| are two proposals the same theme | **code first** | folded-string closeness, already built |
| **split, merge, rename, reparent, promote, retire** | **you**, as a curation act | this is the 20% no data supplies |
| does a rule still hold after any change | **code** | its negative cases run in `mix test` |

The model is used exactly twice, and both times as a **proposer**. Everything that
decides is either arithmetic or a person.

## 5. [PROPOSAL] The loop, and where it already exists

1. A run classifies posts against the **active** vocabulary and records what fit nothing.
2. Code computes §3 and writes a **fitness section** into the report — one section, not
   one question per theme.
3. Anything past a threshold becomes **one question**: *"`Solicitud de recursos` carries
   19% of the corpus and its posts split cleanly in two — split it?"*
4. You rule. The ruling is a curation act, attributed, append-only.
5. **The ruling becomes a test.** The five you just made are now five tests, by name,
   because losing one is otherwise silent.
6. Re-measure. The delta is the answer to *did that help*.

Steps 4, 5 and 6 exist today. Steps 1–3 are what this document is asking for.

## 6. The thing that must not be built

A loop where a model proposes a theme, a model writes its test, and a model grades it
is closed: both sides can share one wrong prior and converge confidently on nonsense.

The anchor is **real posts** — the ones a family actually wrote. A model may label
them, cluster them and propose over them, but every score in §3 is computed against
text somebody wrote in the world, and the negative cases are real posts too. That is
what makes the loop open, and it costs nothing to keep it that way.

## 7. [OPEN] What I need answered

1. **When does this run?** Every read-path run, or a separate `mix run` you invoke? I
   say every run — it is arithmetic over what the run already produced.
2. **What thresholds?** I would rather derive them than pick them: a theme is
   "overloaded" if it is more than 3× the median live theme; residue is "rising" if a
   window exceeds twice the trailing median. Both are guesses and both should be
   measured before they are trusted.
3. **Does a fitness alarm become a report question, or only a section?** A question
   demands an answer; a section can be read and ignored. I say a section, escalating to
   a question only when a threshold is crossed — so a healthy vocabulary is silent.
4. **Is there a `split_theme` verb?** Today a split is *discard the merged one, create
   two* — two steps, and nothing links them but the reason text. Places have `fold`
   (two→one); themes want its inverse (one→two), and the act would name both
   successors.
