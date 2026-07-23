# Kickstart: migrate the Actor concept (person | agent)

We are continuing a methodical, concept-by-concept port of the `wekui` app into this
repo (`wekui-new`) as idiomatic Ash. The domain vocabulary is a linked outline under
`docs/pages/` — read the hub [`docs/pages/ubiquitous-language.md`](pages/ubiquitous-language.md)
first, plus [`actor`](pages/actor.md) and [`open-actor`](pages/open-actor.md), which already
define this concept as **(planned)**. **Do not write any code until I have approved a plan.**

---

## Priors — settled, do not relitigate

**The work.** Porting `/Users/anibal/Sandboxes/Venezuela7275/wekui` (Phoenix + Ecto +
SQLite, CLI-first: Twitter/X post acquisition around Venezuelan catastrophes) into this
repo: Phoenix + **Ash 3.29** + **ash_sqlite 0.2** + **ash_state_machine 0.2**. No data
migration — we are free to choose conventions.

**Already built and green (280 tests, `mix precommit`, no migration drift):**
- `Wekui.Core` — Event, Place, PlaceName, plus the Unplaced Place.
- `Wekui.Acquisition` — Search, SearchTerm, SearchPlace, Query, QueryName, QueryTerm,
  plus pure `QueryText` / `Decomposition` and `Plan` (the only writer of Queries).
- `Wekui.Capture` — Post, Author, Appearance, plus the `SameEvent` cross-event validation.
- `Wekui.Taxonomy` — **Theme** (What axis: a Place-shaped tree, minus the name layer / Type)
  and **Author Tag** (Who axis: a Theme minus the tree — flat, open, same full lifecycle).
- **Shared infrastructure** (extracted this migration): `Wekui.Tree` (recursive-CTE tree
  walks, parameterized by resource), `Wekui.Validations.Reference` (cross-event reference
  check, parameterized by `:resource`), `Wekui.Normalize` (the fold).

**Git model — LEAN (this superseded the old "branch + PR per concept").** Solo development;
PRs add no value here. **Commit each concept straight to `main`** (one tidy commit, with the
`Co-Authored-By` + `Claude-Session` trailers) and `git push origin main`. No feature branches,
no PRs unless I ask. Quality gates are unchanged — leanness is git ceremony only.

**Conventions locked in.** `uuid_primary_key :id`; all FKs `on_delete: :restrict`;
**no Ash multitenancy** — plain `belongs_to :event` with explicit cross-event validation via
the shared `Wekui.Validations.Reference` (`:resource` + `:attribute`/`:argument`, plus
`:lifecycle` / `:not_self?` / `:outside_subtree?`); `Wekui.Capture.Validations.SameEvent`
stays separate (it checks two references *agree* on their Event). `AshStateMachine` for every
curated lifecycle; recursive tree walks are read actions whose `prepare` calls `Wekui.Tree`;
**"status note"** is the one name for *why this thing is where it is*, and its action argument
is always `:note`, never `:reason`; **immutable facts use upsert, not a state machine**
(Post/Author/Appearance are `create` with `upsert? true` + `upsert_identity` + `upsert_fields
[]`); the raw X record is stored as `attribute :payload, :map`.

**Settled design calls.** Query state is derived, never stored. Decomposition is a
calculation. `Plan.build/2` never rewrites an existing Query, so decompose (wipe + build) and
extend (build) are one engine. Concept names are **network-neutral** (Post/Author) but identity
is the honest `x_id`. Name / label strings get Ash's **default whitespace trim** but are
**never folded** (case/accents preserved) — congruent with PlaceName; do not write "as-is" into
the doc, it over-promises. Theme/Author-Tag mirror the full Place lifecycle including `deprecate`
+ `replaced_by`.

**Deliberately not built (staged, not forgotten).** **Placement** (where a Post is about — a
judgment; `No place`, `Place.proposed_by`, Theme `proposed_by`, and Post-relocation-on-settle
all wait on it); **duplicate/near-dup detection** (deferred; strategy measured in
`docs/clustering-spike.md`); **applying a Theme/Tag to a Post/Author** (the judgment itself).
All marked **(planned)** / **(open)** in the doc.

---

## Fundamental principles — non-negotiable

1. **Nothing gets a golden ticket.** No concept crosses from the old repo without being
   discussed, validated and refined with me first.
2. **Doc first, then code.** Write the concept into `docs/pages/` in plain, non-slang language,
   marked **(planned)**; I review it whole. Only then code. This gate made everything better.
3. **Ash first.** Every concept becomes an idiomatic Ash construct. Reach for `mix ash.gen.*`
   before hand-writing; refine afterwards.
4. **Warnings in our own code are errors.** Library warnings are not.
5. **Comprehensive tests are mandatory**, and they test outcomes, not implementation.
6. **Done means congruent.** At the end, the doc, the code and the database must all say the
   same thing in the same words.
7. **The doc says what things *are*.** How they are stored or computed is a technical matter and
   belongs in the code, not the vocabulary.
8. **Commit each concept the moment it is green and congruent** — straight to `main`, not at the
   end of everything.
9. **An invariant enforced only in a read is not enforced.** Gate the write actions too.

---

## Heuristics — earned the hard way

- **Measure, never assert.** "This is faster / used / needed" is not a claim without a number.
- **The old app has a real database — use it as evidence.** `wekui_dev.db` holds one event,
  ~12 searches, ~556 queries, ~13,248 posts, ~6,239 authors, ~932 places, 32 themes, 10 tags,
  and **62,248 + 6,087 judgments — all `method=worker`, zero `manual`**. Querying it has killed
  features (empty `search_terms`), settled questions (dedup, FTS5, trim-vs-fold), and will scope
  Actor. **For anything that writes, work on a disposable copy — never touch the original.**
- **Reproduce before fixing.** Write the failing test first, watch it fail, then fix.
- **Fix the root, not the symptom.**
- **A structural invariant must never rest on an editable label.** Use a distinguished pointer.
- **Absent is not zero.** Unknown is never written down as zero.
- **Derived beats stored** whenever the two could disagree.
- **Extract when duplicated, inline when single-use** — but *attempt* the extraction to judge it,
  don't pre-decide. `Wekui.Tree` and `Wekui.Validations.Reference` earned it at the 2nd–4th use;
  the `SameEvent` `event_path` over-generalization was flagged and narrowed. Do not build
  generality past what the call sites use.
- **Check for an Ash builtin first** (`Ash.Resource.Change.Builtins`,
  `Ash.Resource.Validation.Builtins`) before hand-rolling.
- **Never coin a word that is not in the doc.**
- **If you disagree with a review finding, say so and explain** rather than silently complying
  or silently ignoring. (The advisor caught me burying the "as-is" mismatch — surface, don't bury.)
- **Verify the RETURN, not just the write** for upsert-for-immutable-facts.
- **Delegate the delegable, keep the coupled core.** Fan out subagents for wide investigation and
  large well-scoped suites; do the tightly-coupled building yourself; adjudicate every finding.
- **Call `advisor` at real forks and before declaring done**, with the deliverable already durable.

---

## Strategy — the loop for one concept

1. **Read the source.** Its schema modules, its context module, the migrations that made its
   tables — and the already-written `docs/pages/` entry if the concept is pre-vocabularied.
2. **Query the old database** for what actually happened: counts, always-null columns, unused
   features, lifecycle distribution, method distribution. Bring numbers. Disposable copy to write.
3. **Present the anatomy and the forks.** Use `AskUserQuestion` for real decisions; recommend one
   option rather than surveying all of them.
4. **Write it into `docs/pages/`** (load the `ubiquitous-language` skill first), plain language,
   marked **(planned)**, with a one-line hub entry; leave open questions as `open-*` pages. Wait
   for my review of the whole vocabulary.
5. **Generate**, then refine: `mix ash.gen.resource` → hand-edit to mirror the settled patterns.
6. **`mix ash.codegen <name> --yes`**, review the migration, migrate dev + test.
7. **Write comprehensive tests**, including the edge cases the doc's rules imply.
8. **Verify hard**: `advisor` before committing to the approach and before declaring done;
   `/simplify` if there is novel code (skip with a stated reason if it only mirrors settled code);
   a correctness pass (I run `/code-review` — it is user-triggered and billed; you cannot launch
   it, so do a rigorous self-trace of any novel logic and recommend I run it, pointing at the
   novel surface).
9. **`mix precommit`** and **`mix ash.codegen --check`** (drift) must both be clean.
10. **Unmark (planned)** in the doc (`status:: planned` → `built`, drop `#planned` tags), update
    memory, **commit the concept to `main` and push**, and report.

---

## Tactics — commands and repo facts

```bash
# Generate (the flags that work)
mix ash.gen.resource Wekui.X.Y --domain Wekui.X -u id \
  -a 'field:string:required:public,other:string:public' \
  -r 'belongs_to:event:Wekui.Core.Event' \
  --timestamps --extend sqlite --yes         # then hand-edit: state machine, self-refs, actions

mix ash.codegen <name> --yes     # migration + snapshots
mix ash.codegen --check          # drift check; must be silent (exit 0)
mix ecto.migrate                 # + `MIX_ENV=test mix ecto.migrate` for the test DB
mix precommit                    # docs_doctor + compile(warnings-as-errors) + deps.unlock + format + test

# The old app's evidence (READ-ONLY on the original; copy first to write)
sqlite3 /Users/anibal/Sandboxes/Venezuela7275/wekui/wekui_dev.db ".schema prompts"
```

- **State-machine create idiom (critical):** `initial_states` is enforced ONLY through
  `AshStateMachine.transition_state/2`. Accepting the state attribute in a create action bypasses
  it silently. Take a constrained argument (`constraints one_of: [...]`, `default`) and call
  `transition_state` in a `change`. Do NOT declare the lifecycle attribute yourself —
  `state_attribute :lifecycle` creates it. (See `Wekui.Core.Place`, `Wekui.Taxonomy.Theme`.)
- **Tree walks:** `Wekui.Tree.ancestor_ids/2`, `subtree_ids/2`, `order_by_ids/2`, parameterized by
  resource. Ecto 3.14 **rejects** a pinned `from(n in ^resource)` source — start the query from
  the queryable module and pipe `where`/`select`/`join` instead.
- **Cross-event references:** `validate {Wekui.Validations.Reference, resource: __MODULE__,
  attribute: :parent_id}` (or `argument:`, plus `not_self?` / `lifecycle:` / `outside_subtree?`).
- **Upsert idiom:** `create` with `upsert? true`, `upsert_identity :ident`, `upsert_fields []`.
- **Code interfaces:** `define :verb, action: :x, args: [...]` on the domain resource block gives
  both `verb` and `verb!`. Mirror `Wekui.Taxonomy` / `Wekui.Core`.
- **Regenerating an unshipped migration:** delete the migration file *and* its snapshots under
  `priv/resource_snapshots/repo/<table>/`, regenerate, then drop **both** DBs
  (`mix ecto.drop --force` *and* `MIX_ENV=test mix ecto.drop --force`) before `mix ash.setup`.
- **`CLAUDE.md` is a symlink to `AGENTS.md`.** Edit `AGENTS.md`.
- **ash_sqlite 0.2:** indexes via `custom_indexes`; FK behaviour via `references do reference :x,
  on_delete: :restrict end`. **No database aggregates** — calculations or manual reads. FTS5
  (+ trigram) is compiled into its bundled SQLite 3.53.3 if ever needed.
- **Bulk writes:** `Ash.bulk_create/4` with `return_records?: true, sorted?: true`;
  `Ash.bulk_destroy/4` with `strategy: [:stream]`. `Task.async_stream/3` always `timeout: :infinity`.
- **Test helpers:** `Wekui.Fixtures` (`test/support/fixtures.ex`) and `error_on/2` in
  `Wekui.DataCase`. Grow fixtures per concept; test-local `foo!` helpers are also fine (see
  `place_test.exs` / `theme_test.exs`).

---

## Tooling & environment protocol (repo-specific — this bit trips people up)

**The docs are an outl workspace with a possibly-live desktop app.**
- `docs/pages/*.md` are outl outlines: ONE physical line per bullet (never hard-wrap), two-space
  indent, `key:: value` props at the very top then a blank line, `[[slug]]` links. Prose (headings,
  code, tables — like THIS file and `clustering-spike.md`) lives at **`docs/` root only**; outl
  would bulletize it inside `docs/pages/`.
- **Load the `ubiquitous-language` skill** before authoring/creating any page.
- Hub = `docs/pages/ubiquitous-language.md`; the meta map = `docs/pages/index.md` (first-principles,
  search-strategy, architecture, decision-log, open-questions, research). Concept pages carry
  `type:: concept` + `status:: built|planned`; questions are `open-*` with `opened::`.
- `mix precommit` runs a **`docs_doctor`** step: every page must parse in the outl dialect
  ("no sidecar" warnings are allowed). Lint a page: `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )'
  docs/pages/<p>.md` → no output; every `[[slug]]` must resolve to a file.
- **A `outl-desktop` app may be RUNNING** (`pgrep -lf outl`). If so it adopts new pages live and
  re-projects frontmatter (alphabetical props) — **NEVER start a second outl process**. For a NEW
  page when nothing is running: commit the `.md`, `outl -w docs serve &` … ~8s … kill it, then
  `outl -w docs doctor`, then commit the `.outl` sidecar. Edits to existing pages need nothing.
- **At commit time, STAGE EXPLICIT PATHS — never `git add -A` / `commit -am`.** The live app
  produces frontmatter-reorder churn (e.g. `unplaced-place.md`) that must not be swept into a
  concept commit. (`git add lib/... test/... docs/pages/<yourpages>.md ...`.)
- `outl -w docs doctor` is read-only and coexists with the app; `outl -w docs backlinks page
  <slug>` / `query --prop status=planned` answer graph questions.

**Isolate a shared-infra extraction in its own commit**, with the full existing suite green
*before* you write any new-concept code — that green suite is the proof of no-behaviour-change.

---

## Anti-goals

- Do not write code before I have approved the doc entry.
- Do not transliterate the old app. Every field must earn its place.
- Do not invent vocabulary. A new word goes in the doc first, or it does not exist.
- Do not build **(planned)** items opportunistically — placement, `proposed_by`, and the
  judgments themselves are staged deliberately. (This is a live tension for Actor — see the task.)
- Do not report a property you have not measured or tested.
- Do not fan out subagents for work you could finish yourself in a few tool calls.
- Do not re-introduce branches/PRs — commit straight to `main` (lean-git).

---

## State snapshot (where we are now)

- **Built & green:** Core, Acquisition, Capture, Taxonomy — **280 tests**, `mix precommit`, no drift.
- **Git:** everything is on `main` (local + `origin/main`); no other branches. Work directly on `main`.
- **Docs:** the outl workspace is congruent; `actor.md` (**planned**) and `open-actor.md` (**open**)
  already exist — Actor is pre-vocabularied, so step 4 is *refining* a page, not writing from scratch.
- **Evidence base:** `research-old-app-corpus` and `docs/clustering-spike.md`.

---

## This session's task: the Actor concept (person | agent)

Build **Actor** as a standalone concept — the small prerequisite that makes "an Actor did it"
real and unblocks the judgment cluster, placement, and every `proposed_by`. Judgments come in a
LATER session; Actor first.

**Anatomy (from a first read — confirm and deepen it):**
- `docs/pages/actor.md` already says: *an Actor is whoever or whatever performed a deliberate act
  — a **person** or an **agent**; an agent is a machine worker driven by a **model and a prompt**;
  we treat people and agents the same so we can later ask "how good is this agent vs a person" on
  evidence.* That framing is settled vocabulary — refine attributes, do not re-open the definition.
- **The old app has NO Actor/agent/person/user table.** "Who did it" was `method`
  (`worker` | `manual` | `merge`) + `prompt_id` on each judgment/beat. There IS a first-class
  **`prompts`** table (`content_hash`, `text`, `model`, `question`; UNIQUE on `content_hash,model`;
  15 rows) and **`event_prompts`** (prompts linked per event). So Actor is a genuine *elevation*
  of the implicit `method` + `prompt` into a first-class thing.
- **Evidence:** every real judgment is `method=worker` (62,248 theme + 6,087 tag; **zero manual**).
  Agents are the reality; person-actors exist for *curation* (promote/deprecate/discard, which the
  old app performed but never recorded a who for), not for observed judging.

**The forks I expect (bring these to me — with a recommendation each, not a survey):**
1. **Agent identity = model + prompt?** Is an agent Actor defined by `(model, prompt text,
   question)`, deduped like old `prompts` (content_hash + model)? Is each prompt *version* a
   distinct agent (so "how good is this agent" measures a fixed model+prompt)? Or is **prompt a
   separate concept** an agent points at (old app had first-class `prompts` + `event_prompts`)?
2. **Person Actors — model now or defer?** Zero manual judgments ever, but persons *curate*.
   Model person Actors now (e.g. a single "operator"), or defer persons until there's a manual
   action to attribute?
3. **One resource or two?** `Actor` with a `kind` (`:person | :agent`) discriminator + nullable
   agent fields (model/prompt), or separate `Person` / `Agent` resources. (Ash favours one
   resource with a kind unless behaviour truly diverges.)
4. **Event scope — the sharp one.** Everything so far is "nothing shared between Events." But an
   agent is a `(model, prompt)` that could be reused across events, and `event_prompts` links
   prompts *to* events. Are Actors **event-scoped** (a new Actor per event, uniform with the rest)
   or **global** (one agent spans events, with per-event usage recorded elsewhere)? This decides
   whether `Wekui.Validations.Reference` even applies to Actor references.
5. **Domain placement.** A new `Wekui.Judgment` domain (Actor + judgments together, later), a
   standalone `Wekui.Actor`, or fold into `Wekui.Core`? Actor is referenced cross-domain.
6. **Retrofit scope (respects the anti-goal).** Actor unblocks `proposed_by` (Place/Theme, now
   `#planned`) and actor-stamping of lifecycle steps. Build ONLY the Actor registry this session
   and wire consumers when judgments/placement arrive, or wire `proposed_by` now that Post exists?
   Default: registry only — do not build staged items opportunistically — but raise it.
7. **`open-actor.md` reframing.** It currently says Actor "is wired when we reach the judging
   concepts." Building Actor first means updating that page (Actor becomes real ahead of judgments);
   decide whether `open-actor` closes into a `decision-*` or simply the `actor` page unmarks.

**Start by** reading old `lib/wekui/judgments.ex` and `lib/wekui/judgments/*.ex`
(theme_judgment, author_tag_judgment), the `prompts` / `event_prompts` schemas and their modules,
and the new-repo `docs/pages/actor.md` + `open-actor.md`. Query the old DB (disposable copy to
write): the 15 prompts' distinct `model`s and `question`s, how prompts map to events via
`event_prompts`, and confirm the method distribution (all worker). **Bring me the anatomy, the
forks, and a proposed doc refinement — not code.**

---

## Loose ends — a prioritized backlog (pick from these; do not lose them)

None block Actor; surface them when relevant or when I ask.

- **Core:** `set_unplaced_place` is unguarded (accepts a foreign/proposed/nil place); the reparent
  cycle check is read-then-write with no depth-guard on the `Wekui.Tree` CTEs; `unplaced_place_id`'s
  FK omits the explicit `on_delete: :restrict`; "deprecated is final" for Place is untested (Theme
  now tests it — consider backfilling Place).
- **Acquisition:** `extend_window` on an *open* window doesn't reject an end behind existing
  coverage; anchored-name groups aren't operator-capped (could exceed X's limit).
- **Capture:** the cross-event error blames an arbitrary field when two references disagree
  (cosmetic); `SameEvent` swallows read errors as "does not exist".
- **Parked carry-overs:** `Core.list_active_places/1` *includes* the Unplaced Place — decide if
  that read should exclude it (matters when empty-scope Decomposition meets placement); whether a
  Query's state should be stored for speed (`open-query-state`).
- **Doc seam:** the **(planned)** `settling-a-collected-place` page still reads as if Posts point at
  a Place; Posts carry no `place_id`. Resolve deliberately when placement is built.
- **New concept spotted:** **Beat** (time+place-bucketed drafted digests; `beat_themes` tags them,
  77k rows) — not yet discussed; a candidate after Judgments.

---

## What worked this session — do more of it

- **Doc-first gate.** Vocabulary before code, reviewed whole. `AskUserQuestion` for the real forks
  with a recommended option each (not a survey).
- **Spike open questions against the old DB** on disposable copies — it settled trim-vs-fold, the
  proposed_by deferral (0/32 ever set), and the tag lifecycle (the table already carried the shape).
- **Attempt the extraction to decide it.** `Wekui.Tree` / `Wekui.Validations.Reference` came out
  clean at the union of real call sites; isolate such refactors in their own green commit first.
- **Commit each concept the moment it is green and congruent** — straight to `main`.
- **`advisor` at the forks and before declaring done**, deliverable already durable. It caught the
  Fork-4 evidence-framing error and the buried "as-is" mismatch — give its findings real weight,
  and surface disagreements rather than burying them.
- **Collaboration style that fits you:** decide the obvious, ask the genuine forks; recommend, don't
  survey; measure before asserting; report faithfully (tests failing = say so); lean process, high
  quality bar.
