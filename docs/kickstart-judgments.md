# Kickstart: migrate the Judgment cluster (an Actor's answers about a Post/Author)

We are continuing a methodical, concept-by-concept port of the `wekui` app into this
repo (`wekui-new`) as idiomatic Ash. The domain vocabulary is a linked outline under
`docs/pages/` — read the hub [`docs/pages/ubiquitous-language.md`](pages/ubiquitous-language.md)
first, plus [`theme`](pages/theme.md), [`author-tag`](pages/author-tag.md), [`actor`](pages/actor.md),
[`post`](pages/post.md), [`author`](pages/author.md), [`place`](pages/place.md),
[`unplaced-place`](pages/unplaced-place.md), and the **(planned)** pages this cluster fills in:
[`no-place`](pages/no-place.md), [`settling-a-collected-place`](pages/settling-a-collected-place.md),
[`open-placement`](pages/open-placement.md), [`open-actor`](pages/open-actor.md). **Do not write
any code until I have approved the vocabulary.**

**This is a big session by choice.** The whole judgment cluster, in one go, pulling in the
extras Actor unblocked. That is more surface than any prior session — so lean on the settled
patterns (they are the point), commit each sub-concept the moment it is green, and do not let the
breadth erode the doc-first gate for the *new* vocabulary.

---

## Priors — settled, do not relitigate

**The work.** Porting `/Users/anibal/Sandboxes/Venezuela7275/wekui` (Phoenix + Ecto +
SQLite, CLI-first: Twitter/X post acquisition around Venezuelan catastrophes) into this
repo: Phoenix + **Ash 3.30** + **ash_sqlite 0.2** + **ash_state_machine 0.2**. No data
migration — we are free to choose conventions.

**Already built and green (292 tests, `mix precommit`, no migration drift):**
- `Wekui.Core` — Event, Place, PlaceName, the Unplaced Place, **and `Actor`** (the newest).
- `Wekui.Acquisition` — Search, SearchTerm, SearchPlace, Query, QueryName, QueryTerm,
  plus pure `QueryText` / `Decomposition` and `Plan` (the only writer of Queries).
- `Wekui.Capture` — Post, Author, Appearance, plus the `SameEvent` cross-event validation.
- `Wekui.Taxonomy` — **Theme** (What axis: a Place-shaped tree minus the name layer / Type)
  and **Author Tag** (Who axis: a Theme minus the tree — flat, open, same full lifecycle).
- **Shared infrastructure:** `Wekui.Tree` (recursive-CTE tree walks, parameterized by
  resource), `Wekui.Validations.Reference` (cross-event reference check, parameterized by
  `:resource`), `Wekui.Normalize` (the fold), `Wekui.Core.Changes.Fold` (fold one attr into
  another), `Wekui.Core.Changes.ContentHash` (SHA-256 one attr into another).

**Actor — just built, and the direct prerequisite for this cluster.** `Wekui.Core.Actor` is the
first-class "who did it". Read `lib/wekui/core/actor.ex` and `test/wekui/core/actor_test.exs`
first — it sets the patterns you will reuse. Settled facts about it:
- `kind :person | :agent` discriminator (one resource, per-kind rules). An **agent = (model,
  prompt)**, content-addressed: `register_agent` upserts on `(event_id, content_hash, model)`,
  `content_hash` = SHA-256 of `prompt` (derived on write via `ContentHash`, never accepted).
- **No lifecycle** — an Actor is an immutable fact (no update/destroy), like Post/Author.
- **Event-scoped** — I recommended *global*; the operator chose **event-scoped** to keep the
  "nothing is ever shared between Events" invariant intact. Consequence you must honour: a
  judgment's Actor is in the *same Event* as its Post/Theme/Place — so `SameEvent` /
  `Wekui.Validations.Reference` **do** apply to the Actor leg. "How good is this agent" is a
  within-Event question.
- Only the **agent** write-path exists; the **person** write-path is deferred (`open-actor`,
  narrowed to that residual). The old app's `method=manual` was anonymous — a person Actor is
  the first time a human act can carry a who.

**Git model — LEAN.** Solo development; no PRs. **Commit each sub-concept straight to `main`**
(one tidy commit each, with the `Co-Authored-By` + `Claude-Session` trailers) and
`git push origin main`. No feature branches. Quality gates are unchanged — leanness is git
ceremony only. Even in a "whole cluster" session, commit theme-judgment, then author-tag-judgment,
then placement, etc., **separately, each the moment it is green** — never one mega-commit.

**Conventions locked in.** `uuid_primary_key :id`; all FKs `on_delete: :restrict`; **no Ash
multitenancy** — plain `belongs_to :event` with explicit cross-event validation via the shared
`Wekui.Validations.Reference` (`:resource` + `:attribute`/`:argument`, plus `:lifecycle` /
`:not_self?` / `:outside_subtree?`); `Wekui.Capture.Validations.SameEvent` stays separate (it
checks two references *agree* on their Event); `AshStateMachine` for every curated lifecycle;
recursive tree walks are read actions whose `prepare` calls `Wekui.Tree`; **"status note"** is
the one name for *why this thing is where it is*, and its action argument is always `:note`,
never `:reason`; **immutable facts use upsert** (`create` + `upsert? true` + `upsert_identity` +
`upsert_fields []`) — Post/Author/Appearance/**Actor-agent**; **content-addressing** is a
`ContentHash` change (SHA-256, derived-never-cast); name/label strings get Ash's **default
whitespace trim** but are **never folded**; the raw X record is `attribute :payload, :map`.

**Settled design calls that ripple into this cluster.** Query state is derived, never stored.
Concept names are **network-neutral** (Post/Author) but identity is the honest `x_id`.
Theme/Author-Tag mirror the full Place lifecycle including `deprecate` + `replaced_by`. Defaults
are provenance, not judgment (see the old app's §Semantics quoted below). An invariant enforced
only in a read is not enforced — gate the writes.

**Deliberately not built (staged beyond this cluster).** **Runs** (execution records for the
judge/collect pipeline), **Beat** (time+place-bucketed drafted digests; `beat_themes`, 77k rows),
**Narrative/extraction/discovery/assembly** prompts, probes, `expected_posts`,
`pages_fetched`/`cursor`. And the un-vocabularied old-app judgment *questions* — **`whether`
(relevance)** and **`when` (time)** — are NOT auto-ported (see the task's fork on scope).

---

## Standing constraints this cluster inherits (read once, do not re-derive)

- **A judgment is NOT an immutable-upsert fact.** It **supersedes**: re-judging closes the prior
  answer and opens a new one; retraction closes without a successor. So judgments need a
  *different* pattern than Actor/Post — an append-only history with one current row per slot.
  This is the central new mechanism; everything else in the cluster reuses it.
- **Provenance maps onto Actor, and `merge` is the open edge.** The old `method ∈ {worker,
  manual, merge}` becomes: `worker → agent` Actor (+ `confidence`), `manual → person` Actor
  (no confidence), `merge → ???`. `merge` is neither person nor agent (it is dedup bookkeeping).
  You are building it this session — decide what performs a merge (a third Actor kind? a
  system/no-Actor operation?). Evidence: **0 merge rows ever** in the corpus, so this is
  design-led, not evidence-led — say so.
- **Cross-event agreement now includes the Actor.** A judgment references a Post/Author, a
  Theme/Tag/Place, AND an Actor — all event-scoped, all must agree on their Event. Reuse
  `SameEvent` (extend its `references:` list) and/or `Reference`.
- **The old worker invariant (verbatim, from `lib/wekui/judgments.ex` moduledoc):** *"Facts are
  immutable; every answer is an append-only judgment row. Supersession is atomic… Retraction is
  close-without-successor… Defaults are provenance, not judgment: Where falls back to the origin
  query's swept place, When to `posted_at`, What to unclassified. Whether has no default…
  Worker provenance: `prompt_id` is set iff `method == :worker`; `confidence` is required for
  workers and forbidden otherwise."*
- **The doc seam this cluster must resolve.** `settling-a-collected-place` still reads as if
  Posts point at a Place, but **a Post carries no `place_id`** (placement is a judgment). Placement
  is where you decide, deliberately, whether a Post gains a place pointer or the "where" is always
  read from the current place-judgment.

---

## Fundamental principles — non-negotiable

1. **Nothing gets a golden ticket.** No concept crosses from the old repo without being
   discussed, validated and refined with me first. (Acute here: `whether`/`when`/`merge` and
   `event_prompts` are old-app machinery — none is auto-included.)
2. **Doc first, then code.** Write the new vocabulary into `docs/pages/` in plain,
   non-slang language, marked **(planned)**; I review it whole. Only then code.
3. **Ash first.** Every concept becomes an idiomatic Ash construct. Reach for `mix ash.gen.*`
   before hand-writing; refine afterwards.
4. **Warnings in our own code are errors.** Library warnings are not.
5. **Comprehensive tests are mandatory**, and they test outcomes, not implementation.
6. **Done means congruent.** At the end, the doc, the code and the database say the same thing
   in the same words.
7. **The doc says what things *are*.** How they are stored or computed is a technical matter and
   belongs in the code, not the vocabulary.
8. **Commit each concept the moment it is green and congruent** — straight to `main`.
9. **An invariant enforced only in a read is not enforced.** Gate the write actions too.

---

## Heuristics — earned the hard way

- **Measure, never assert.** "This is faster / used / needed" is not a claim without a number.
- **The old app has a real database — use it as evidence.** `wekui_dev.db` (READ-ONLY on the
  original; disposable copy to write) holds one event with **62,248 theme + 6,087 author-tag +
  10,389 place + 13,250 relevance + 170 time judgments**, plus **12,339 post-∅ + 616 author-∅**
  none-judgments, and **15 prompts / 14 event-prompt pins**. Method is ~entirely `worker`; only
  **5 manual** (3 place + 2 relevance, anonymous, null prompt); **0 merge**. Querying it killed
  features, settled trim-vs-fold, and corrected the "zero manual" prior — do it again for
  supersession/retraction rates, confidence distribution, and default usage.
- **Reproduce before fixing.** Write the failing test first, watch it fail, then fix.
- **Fix the root, not the symptom.** **Absent is not zero.** **Derived beats stored.**
- **Attempt the extraction to judge it.** `Wekui.Tree` and `Wekui.Validations.Reference` earned
  it at the 2nd–4th call site. The judgment cluster has ≥3 near-identical shapes (theme, tag,
  place ± their ∅s) — *attempt* a shared judgment behavior/mechanism and let the real call sites
  decide its surface. Do not build generality past what they use.
- **Compile before codegen.** `mix compile --warnings-as-errors` on a new resource *before*
  `mix ash.codegen` — catch DSL/identity warnings while the migration is still cheap to shape.
  Regenerating a shipped-in-session migration means deleting it + its snapshots + dropping both
  DBs, so get the resource right first.
- **Verify the RETURN, not just the write** for anything content-addressed or superseding — the
  supersession must return the *new current* row and leave the old one closed, provably.
- **Check for an Ash builtin first** (`Ash.Resource.{Change,Validation}.Builtins`) before
  hand-rolling — `present`, `absent`, `set_attribute`, `transition_state`, `relate_actor`.
- **Never coin a word that is not in the doc.**
- **If you disagree with a review finding, say so and explain** rather than silently complying or
  ignoring. Surface deviations from a decision I made as a *choice*, not a footnote (the advisor
  caught the `open-actor` override this way — I made the call, then put it back to the operator).
- **When evidence and a standing invariant collide, lead with the concrete downstream cost.**
  Actor's event-scope: I recommended global on the evidence; the operator kept event-scoped to
  protect "nothing shared between Events". State the cost of each side sharply, then let me pick.
- **Delegate the delegable, keep the coupled core.** Fan out subagents for wide investigation
  (e.g. reading all old judgment modules + querying distributions in parallel); do the
  tightly-coupled mechanism yourself; adjudicate every finding.
- **Call `advisor` at real forks and before declaring done**, with the deliverable already durable.

---

## Strategy — the streamlined loop (operator asked to move faster)

The patterns are settled; spend the round-trips only where the decision is genuinely novel.

1. **Read once, in parallel.** The old judgment source (`lib/wekui/judgments.ex` +
   `lib/wekui/judgments/*.ex`), the built `actor.ex`/`theme.ex`/`author_tag.ex`/`place.ex`, and
   the **(planned)** doc pages. Query the old DB for the numbers that decide the forks. A subagent
   fan-out is justified for this breadth.
2. **One doc-first pass for the whole cluster.** Present the anatomy **and all the forks batched
   in prose** (not one `AskUserQuestion` per fork — I would rather answer inline). Recommend one
   option each. Reserve a real stop-and-wait only for the **supersession model** (fork 1) and any
   genuinely new vocabulary (No place, the merge-actor, whether/when if pulled in).
3. **Write the new vocabulary into `docs/pages/`** (load the `ubiquitous-language` skill first),
   plain language, **(planned)**, hub lines updated; I review the whole vocabulary once.
4. **Then build sub-concept by sub-concept**, in a tractable order, committing each green:
   **(a) the judgment mechanism via Theme judgment** (establishes supersession/history + Actor
   provenance + confidence + examined-empty ∅), **(b) Author-Tag judgment** (the author-scoped
   analog — proves the mechanism generalizes; attempt the extraction here), **(c) Placement**
   (the where-judgment: No place, the Unplaced interaction, settling-a-collected-place, the
   Post-place seam), **(d) `proposed_by`** on Place/Theme → Actor, **(e) `merge`/dedup**. For each:
   generate → refine → `mix ash.codegen <name> --yes` → migrate dev+test → comprehensive tests →
   `advisor` + self-trace of novel logic → `mix precommit` + `mix ash.codegen --check` clean →
   unmark the doc → commit + push.
5. **Verify hard where it is novel.** `advisor` before committing to the supersession approach
   and before declaring done; `/simplify` if there is novel code (skip with a stated reason if it
   only mirrors settled code); a rigorous self-trace of any novel logic (I run `/code-review` — it
   is user-triggered and billed; you cannot launch it, so point me at the novel surface).
6. **Update memory and the cluster's open pages** as each piece lands; close `open-placement`
   into the built vocabulary; keep `open-actor` open (person side) unless the person path is built.

---

## Tactics — commands and repo facts

```bash
# Generate (the flags that work)
mix ash.gen.resource Wekui.Judgment.ThemeJudgment --domain Wekui.Judgment -u id \
  -a 'confidence:float:public,judged_at:utc_datetime_usec:public' \
  -r 'belongs_to:post:Wekui.Capture.Post,belongs_to:theme:Wekui.Taxonomy.Theme,belongs_to:actor:Wekui.Core.Actor' \
  --extend sqlite --yes         # then hand-edit: supersession, provenance rules, ∅, actions

mix compile --warnings-as-errors # BEFORE codegen — catch identity/DSL warnings early
mix ash.codegen <name> --yes     # migration + snapshots
mix ash.codegen --check          # drift check; must be silent (exit 0)
mix ecto.migrate                 # + `MIX_ENV=test mix ecto.migrate` for the test DB
mix precommit                    # docs_doctor + compile(warnings-as-errors) + deps.unlock + format + test

# The old app's evidence (READ-ONLY on the original; copy first to write)
sqlite3 -readonly /Users/anibal/Sandboxes/Venezuela7275/wekui/wekui_dev.db ".schema theme_judgments"
```

- **Immutable-upsert idiom** (Actor/Post/Author): `create` + `upsert? true` +
  `upsert_identity :ident` + `upsert_fields []`. **Content-address idiom:** a `ContentHash` change
  (mirror `Wekui.Core.Changes.ContentHash`), identity includes the derived hash.
- **Discriminator idiom** (Actor's `kind`): one resource, `attribute :kind, :atom,
  constraints: [one_of: […]]`, set in the action via `change set_attribute`, per-kind invariants
  via `validate present([…])` / `absent([…])` (builtins — no `where` timing surprises if you set
  the discriminator in the same action).
- **State-machine create idiom (critical, if a judgment lifecycle uses one):** `initial_states` is
  enforced ONLY through `AshStateMachine.transition_state/2`; accepting the state attribute in a
  create bypasses it. Take a constrained argument + call `transition_state` in a `change`. Do NOT
  declare the lifecycle attribute yourself — `state_attribute` creates it. (See `Place`, `Theme`.)
- **Supersession has no repo precedent yet** — it is the thing to design. Candidates to weigh:
  a `supersede` update action that closes the current row (sets `superseded_at`/`superseded_by_id`)
  and creates the successor in one action/transaction; a partial identity on
  `(slot) WHERE superseded_at IS NULL` (Ash identities support `where`, confirmed) to guard "one
  current per slot"; retraction as close-without-successor. Prove atomicity with a test.
- **Cross-event references:** `validate {Wekui.Validations.Reference, resource: R, attribute: :x}`
  (or `argument:`); `Wekui.Capture.Validations.SameEvent, references: [{:field, Resource}, …]` when
  two+ references must *agree* on their Event (extend it to include the Actor leg).
- **Code interfaces:** `define :verb, action: :x, args: […]` on the domain resource block gives
  both `verb` and `verb!`. Mirror `Wekui.Core` / `Wekui.Taxonomy`.
- **Regenerating an unshipped migration:** delete the migration file *and* its snapshots under
  `priv/resource_snapshots/repo/<table>/`, regenerate, then drop **both** DBs
  (`mix ecto.drop --force` *and* `MIX_ENV=test mix ecto.drop --force`) before `mix ash.setup`.
- **`CLAUDE.md` is a symlink to `AGENTS.md`.** Edit `AGENTS.md`.
- **ash_sqlite 0.2:** indexes via `custom_indexes`; FK behaviour via `references do reference :x,
  on_delete: :restrict end`. **No database aggregates** — calculations or manual reads. Identities
  may carry a `where` (partial unique index); nullable identity columns are SQLite nulls-distinct.
- **Bulk writes:** `Ash.bulk_create/4` (`return_records?: true, sorted?: true`);
  `Ash.bulk_destroy/4` (`strategy: [:stream]`). `Task.async_stream/3` always `timeout: :infinity`.
- **Test helpers:** `Wekui.Fixtures` (grow it: a `judgment!`/`agent!`-style factory per sub-concept)
  and `error_on/2` in `Wekui.DataCase`; test-local `foo!` helpers are also fine.

---

## Tooling & environment protocol (repo-specific — this bit trips people up)

**The docs are an outl workspace with a possibly-live desktop app.**
- `docs/pages/*.md` are outl outlines: ONE physical line per bullet (never hard-wrap), two-space
  indent, `key:: value` props at the very top then a blank line, `[[slug]]` links. Prose (headings,
  code, tables — like THIS file) lives at **`docs/` root only**; outl would bulletize it inside
  `docs/pages/`.
- **Load the `ubiquitous-language` skill** before authoring/creating any page.
- Hub = `docs/pages/ubiquitous-language.md`; the meta map = `docs/pages/index.md`. Concept pages
  carry `type:: concept` + `status:: built|planned`; open questions are `open-*` with `opened::`;
  an answered open page **shrinks to a pointer, it is never silently deleted** (hub rule — this is
  why `open-actor` was narrowed, not removed).
- `mix precommit` runs a **`docs_doctor`** step: every page must parse. Lint a page:
  `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )' docs/pages/<p>.md` → no output; every `[[slug]]` must
  resolve to a file. `outl -w docs doctor` is read-only and coexists with the app.
- **A `outl-desktop` app may be RUNNING** (`pgrep -lf outl`; it was, PID-wise, last session). It
  adopts existing-page edits live and reprojects sidecars — **NEVER start a second outl process.**
  Editing an existing page needs nothing. For a NEW page when nothing is running: commit the `.md`,
  `outl -w docs serve &` … ~8s … kill it, then `outl -w docs doctor`, then commit the `.outl`.
- **STAGING — the landmine, verified against git history.** Concept commits stage **`.md` docs +
  code only**; `.outl` sidecars are reconciled *separately* (this is what commit `e82ed98` did, and
  `1e02520` was such a reconcile). So: **stage explicit paths**, and **exclude the `.outl`
  sidecars and any unrelated live-app churn** (e.g. `open-placement.*` rode along uncommitted last
  session). **Never `git add -A` / `commit -am`.** Run `git status --short` and
  `git diff --cached --name-only` before every commit.

**Isolate a shared-infra extraction in its own commit**, with the full existing suite green
*before* you write any new-concept code — that green suite is the proof of no-behaviour-change.

---

## Anti-goals

- Do not write code before I have approved the vocabulary.
- Do not transliterate the old app. Every field, and every judgment *kind*, must earn its place —
  `whether`/`when`/`event_prompts`/`merge` are not golden-tickets just because the tables exist.
- Do not invent vocabulary. A new word (No place, the merge-actor) goes in the doc first.
- Do not report a property you have not measured or tested. `0 merge` rows means merge is
  design-led — say so, don't pretend it's evidenced.
- Do not build one mega-commit. Commit each sub-concept green.
- Do not fan out subagents for work you could finish yourself in a few tool calls; do fan out for
  the wide read + old-DB distribution queries.
- Do not re-introduce branches/PRs — commit straight to `main` (lean-git).
- Do not let "streamline" erode the doc-first gate for genuinely new vocabulary, or the
  verify-hard pass on the novel supersession mechanism.

---

## State snapshot (where we are now)

- **Built & green:** Core (incl. **Actor**), Acquisition, Capture, Taxonomy — **292 tests**,
  `mix precommit`, no drift.
- **Git:** everything on `main` (local + `origin/main`); last commit `403532c` (Actor). No other
  branches. Work directly on `main`. Uncommitted at session start may include live-app sidecar
  churn (`*.outl`) and `open-placement.*` — exclude it from concept commits.
- **Docs:** congruent; `actor` is **built**; `open-actor` is **open** (person side); `no-place`,
  `settling-a-collected-place`, `open-placement`, `open-query-state` etc. remain **planned/open**.
- **Evidence base:** `research-old-app-corpus`, `docs/clustering-spike.md`, and the numbers in the
  Heuristics section above.

---

## This session's task: the whole Judgment cluster (operator's scope: all of it)

Build the judgment mechanism and every judgment we currently have vocabulary for, plus the extras
Actor unblocked. A **judgment** is an Actor's answer about a Post or Author, recorded append-only
and superseding, with its provenance (which Actor, and for an agent, a confidence).

**In scope (confirmed by the operator):**
1. **The judgment mechanism** — append-only history, one current row per slot, atomic supersession,
   retraction as close-without-successor. This is the shared spine; attempt to extract it.
2. **Theme judgment** (Post → Theme) and **Author-Tag judgment** (Author → Tag) — the two
   classification judgments over the built taxonomies. Any number current per Post/Author, at most
   one per `(post, theme)` / `(author, tag)`.
3. **Examined-empty ∅ (none-judgments)** — first-class "asked with this Actor, answer was nothing",
   distinct from "never asked". Post-scoped (`(post, question)`) and author-scoped variants.
4. **Placement (the where-judgment)** — Post → Place, including **No place** (recorded "about
   nowhere", never confused with Unplaced), the Unplaced-Place interaction, and
   **settling-a-collected-place** (what becomes of a Post's "where" when its Place is settled).
   Resolve the **Post-has-no-`place_id` seam** here, deliberately.
5. **`proposed_by`** on Place and Theme → the Actor that proposed it (0/32 historically — build the
   field + action; it will simply be empty).
6. **`merge`/duplicate handling** — the third provenance mode. Decide what performs a merge (it is
   neither person nor agent). 0 rows ever, so this is design-led; keep it minimal and honest, and
   lean on `docs/clustering-spike.md` for the detection strategy.

**The forks I expect (bring these batched, with a recommendation each — inline prose, not a
click-through). Reserve a real stop-and-wait for #1 and any brand-new vocabulary.**
1. **Supersession model in Ash** (THE decision). Mirror the old close-old/open-new atomic pattern
   as a `supersede`/`retract` action pair with a partial identity guarding "one current per slot"?
   Or a state-machine (current→superseded) + relational `superseded_by`? Prove atomicity + the
   returned current row with tests. Bring supersession/retraction *rates* from the old DB.
2. **One shared judgment behavior, or per-kind resources?** Old app: separate tables per kind.
   Attempt a `Wekui.Judgment` shared mechanism (like `Tree`/`Reference`) and let the ≥3 call sites
   (theme, tag, place, ∅s) decide its surface. Do not over-generalize.
3. **Provenance + the merge-actor.** `worker→agent`, `manual→person`, `merge→?`. Is merge a third
   Actor `kind`, a null-Actor system op, or its own tiny concept? And confidence: agent-only,
   `0..1`, forbidden otherwise (mirror the old invariant, gated on the write).
4. **∅ shape.** One none-judgment resource keyed `(post, question)` + a separate author-∅ (old
   app's split), or per-concept ∅? How ∅ participates in supersession (an answer landing supersedes
   the ∅, and vice-versa).
5. **Placement & the Post-place seam.** Does a Post gain a `place_id` on settle, or is "where"
   always read from the current place-judgment (derived-beats-stored)? How No place and the Unplaced
   default coexist. This rewrites `settling-a-collected-place` from planned to built.
6. **Domain placement.** A new **`Wekui.Judgment`** domain (the judgment resources + the shared
   mechanism), referencing Actor/Place (Core), Post/Author (Capture), Theme/Tag (Taxonomy)? This is
   where a judgment domain finally earns its name — vs folding into an existing domain.
7. **Scope guard — un-vocabularied questions.** `whether` (relevance) and `when` (time) are old-app
   judgment kinds with real data (13,250 / 170) but **no new vocabulary**. Recommend: do NOT port
   them silently — flag each as its own concept candidate to discuss, like Beat. Same for
   `event_prompts` (the per-event agent pin — pipeline machinery; likely defer).

**Start by** reading the old `lib/wekui/judgments.ex` (the context: `find_or_create_prompt`,
`apply_judgment`, `pin_prompt!`, the supersession helpers `close!`/`link!`, the §Semantics
moduledoc) and every `lib/wekui/judgments/*.ex` schema, plus the built `actor.ex` and the
**(planned)** doc pages. Query the old DB (disposable copy to write) for supersession/retraction
rates, confidence distribution, default usage, and the ∅ counts. **Bring me the anatomy, the forks
batched, and a proposed doc refinement — not code.**

---

## Loose ends — a prioritized backlog (pick from these; do not lose them)

Several are now *in scope* via this cluster (marked ⟶); the rest stay parked.

- ⟶ **Doc seam:** `settling-a-collected-place` reads as if Posts point at a Place; Posts carry no
  `place_id`. Resolve deliberately when placement is built (fork 5).
- ⟶ **`open-placement`**: closes into built vocabulary this session.
- **Core:** `set_unplaced_place` is unguarded (accepts a foreign/proposed/nil place); the reparent
  cycle check is read-then-write with no depth-guard on the `Wekui.Tree` CTEs; `unplaced_place_id`'s
  FK omits the explicit `on_delete: :restrict`; "deprecated is final" for Place is untested (Theme
  tests it — backfill Place).
- **Acquisition:** `extend_window` on an *open* window doesn't reject an end behind existing
  coverage; anchored-name groups aren't operator-capped (could exceed X's limit).
- **Capture:** the cross-event error blames an arbitrary field when two references disagree
  (cosmetic); `SameEvent` swallows read errors as "does not exist".
- **Parked carry-overs:** `Core.list_active_places/1` *includes* the Unplaced Place — decide if
  that read should exclude it (matters when empty-scope Decomposition meets placement); whether a
  Query's state should be stored for speed (`open-query-state`).
- **New concepts spotted, not yet discussed:** **Beat** (77k rows), **Runs**, **relevance/time**
  judgments — candidates after this cluster.

---

## What worked last session — do more of it

- **Doc-first gate.** Vocabulary before code, reviewed whole. It caught the event-scope and
  open-actor calls before they hardened.
- **Batched, recommended forks.** The operator prefers answering *inline* with a recommendation
  each over a click-through survey — this session, batch the forks in prose. Use `AskUserQuestion`
  sparingly, only for the load-bearing ones (supersession).
- **Spike open questions against the old DB** on disposable copies — it corrected the "zero manual"
  prior and will settle the supersession/confidence questions.
- **Attempt the extraction to decide it.** `Tree` / `Reference` / `Fold` / `ContentHash` all came
  out clean at the union of real call sites; the judgment mechanism is the next candidate — isolate
  such a refactor in its own green commit.
- **Compile before codegen; verify the RETURN; check builtins first.**
- **Commit each concept the moment it is green — straight to `main`**, explicit paths only,
  excluding sidecar/`open-placement` churn.
- **`advisor` at the forks and before declaring done**, deliverable already durable. Give its
  findings real weight and **surface disagreements or decision-overrides as choices**, not
  footnotes.
- **Collaboration style that fits the operator:** decide the obvious, batch the genuine forks with
  a recommendation each; measure before asserting; report faithfully (tests failing = say so);
  lean process, high quality bar — and now, **move faster where the patterns are settled.**
