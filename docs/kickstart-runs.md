# Kickstart: the Runs / pipeline execution layer (make the system *run*)

We are continuing a methodical, concept-by-concept port of the `wekui` app into this
repo (`wekui-new`) as idiomatic Ash. So far every ported concept has been a *noun* — a
record of the world (Event, Place, Post, Author) or an Actor's *answer* about one
(the Judgment cluster). This session builds the first *verb* layer: **Runs** — the
record of the system's own execution, plus the **agent pin** that says which agent
answers which question, plus the **runner** that actually drains a Search into Posts.

Read the hub [`docs/pages/ubiquitous-language.md`](pages/ubiquitous-language.md) first, then
[`actor`](pages/actor.md), [`search`](pages/search.md), [`query`](pages/query.md),
[`coverage`](pages/coverage.md), [`post`](pages/post.md), [`appearance`](pages/appearance.md),
[`judgment`](pages/judgment.md), and the audit report
[`docs/ubiquitous-language-audit.md`](ubiquitous-language-audit.md) (it names the one seam this
layer closes). **Do not write any code until I have approved the vocabulary and the execution-reach
decision (fork 1).**

**This is a big session by choice** (operator's scope: the whole next layer). It is different in
kind from everything so far — the prior layers had zero side effects; this one *acts on the world*
(HTTP to X, HTTP to an inference API). So the load-bearing decision is not a schema shape, it is
**how far execution reaches this session** (fork 1). Settle that first, then lean on the settled
patterns for the record-keeping parts.

---

## Priors — settled, do not relitigate

**The work.** Porting `/Users/anibal/Sandboxes/Venezuela7275/wekui` (Phoenix + Ecto + SQLite,
CLI-first: Twitter/X post acquisition around Venezuelan catastrophes) into this repo: Phoenix +
**Ash 3.x** + **ash_sqlite 0.2** + **ash_state_machine 0.2**. No data migration — we choose the
conventions.

**Already built and green (372 tests, `mix precommit`, no migration drift; docs↔code audited).**
The whole domain *vocabulary* is done:
- `Wekui.Core` — Event, Place, PlaceName, the Unplaced Place, **Actor** (person|agent; an agent
  is a content-addressed `(model, prompt)` upsert).
- `Wekui.Acquisition` — Search (draft→ready→active⇄paused→closed), SearchTerm, SearchPlace, Query,
  QueryName, QueryTerm; pure `QueryText` / `Decomposition`; `Plan` (the only writer of Queries).
  **Query state is a calculation** (never stored); coverage = completed ∧ latest via `read :covering`.
- `Wekui.Capture` — Post, Author, Appearance (all immutable upserts), plus `SameEvent`.
- `Wekui.Taxonomy` — Theme (What axis) and Author Tag (Who axis).
- `Wekui.Judgment` — the append-only/superseding mechanism and every judgment we have vocabulary
  for: ThemeJudgment(+ThemeNone), AuthorTagJudgment(+AuthorTagNone), Placement(+NoPlace). **Where a
  Post is about is DERIVED** (`Wekui.Judgment.Where.of/1`), never stored.
- **Shared infra:** `Wekui.Tree`, `Wekui.Validations.Reference`, `Wekui.Normalize`,
  `Wekui.Core.Changes.{Fold, ContentHash}`, and the judgment mechanism
  (`Wekui.Judgment.{Slot}`, `Changes.{Supersede, CloseCurrent, Retract}`, `SetReplacement`,
  `Validations.{Provenance, NotUnplaced}`).

**The judgment mechanism is the reusable spine for this session's pin.** An `event_prompt` (old
app) is "which prompt currently answers question X for this event" — *exactly* one-current-per-slot
superseding, which is already built. The **agent pin** reuses `Changes.Supersede` /
`Changes.Retract` / the partial-unique-`WHERE superseded_at IS NULL` index verbatim. This is the
cleanest part of the session — lead with it.

**Git model — LEAN.** Solo; no PRs. **Commit each sub-concept straight to `main`** (one tidy commit
each, with the `Co-Authored-By` + `Claude-Session` trailers) and `git push`. Even in a whole-layer
session, commit the pin, then the Run receipt, then the runner, **separately, each the moment it is
green** — never one mega-commit.

**Conventions locked in.** `uuid_primary_key :id`; all FKs `on_delete: :restrict`; **no Ash
multitenancy** — plain `belongs_to :event` + explicit cross-event validation via
`Wekui.Validations.Reference` (`:resource` + `:attribute`/`:argument`, plus `:lifecycle` /
`:not_self?` / `:outside_subtree?`); `Wekui.Capture.Validations.SameEvent` when 2+ references must
*agree* on their Event; `AshStateMachine` for curated lifecycles; **"status note"** is the one name
for *why this is where it is*, its argument always `:note`; **immutable facts use upsert**
(`create` + `upsert? true` + `upsert_identity` + `upsert_fields []`); opaque external blobs are
`attribute :_, :map` (like Post's `payload`); code interfaces via `define :verb, action:` on the
domain block (gives `verb` and `verb!`).

**Two ash_sqlite 0.2 realities the judgment cluster hit (both bite this layer too):**
1. **An identity's `where` does NOT become a partial index.** ash_sqlite builds identity indexes
   from the resource `base_filter`, not a per-identity `where`. "One current pin per `(event,
   question)`" is a **custom partial unique index** (`custom_indexes`, `unique: true, where:
   "superseded_at IS NULL", message: …`), NOT an Ash identity. Compile before codegen or the first
   migration silently makes a FULL unique index that blocks all re-pinning.
2. **ash_sqlite cannot run Ash-managed transactions** (`can?(:transact) == false`) — `transaction?
   true` is a no-op. Multi-step atomic work uses an explicit `Wekui.Repo.transaction/1` (as
   `SetReplacement` does). A single create with before/after_action hooks is NOT transactional —
   safe only when validations gate before the first write. **The runner's per-page write is exactly
   this shape** (each page one `Capture` transaction that also advances the frontier).

**Deliberately NOT built (candidates *after* this layer — do not pull in silently).** `whether`
(relevance, 13.2k rows) and `when` (time, 170 rows) — un-vocabularied judgment *kinds*;
**Beat / Narrative / extraction / assembly** (the OUTPUT layer — `beats` 17k, `beat_themes` 77k;
this was the fork you did **not** pick); the **person write-path** for Actor (`open-actor`);
**duplicate/near-dup detection** (`docs/clustering-spike.md`). None is a golden ticket.

---

## Standing constraints this layer inherits (read once, do not re-derive)

- **This is the first layer with side effects.** Every prior concept was inert data. A run *does
  things*: HTTP to X, HTTP to an inference API, and bulk writes of Posts/Appearances/judgments. The
  discipline that protects this: **the client is an injected behaviour, tested with `Req.Test`; the
  network is never in the test suite.** The old app already does exactly this (behaviour +
  `live.ex` Req impl + `Req.Test` plug) — mirror it.
- **A Run is a receipt, not an answer.** The old moduledoc calls it a *forensic receipt*: born
  `running`, finalized `completed` with a `summary`; a `running` row found later is a crash artifact
  (no successful finalize ran). It records *that the system executed*, not a fact about the world.
  Whether that makes it *vocabulary* (a concept page) or *machinery* (an architecture stance + code,
  like the outl op-log) is **fork 2** — decide it deliberately, don't default it into a concept page.
- **The runner closes the audit's one open invariant.** `appearance.md` states "Every Post has at
  least one Appearance," but nothing enforces it — because the *runner* is what creates a Post and
  its Appearance together, in one `Capture` transaction. So **live acquisition is what makes that
  Rule true**; if acquisition is stubbed this session, the invariant stays open (say so, don't
  claim it closed).
- **Cross-event agreement extends to the pin and the run.** A pin references an Actor(agent) and an
  Event; a Run references an Event, a Search, an Actor(agent). All event-scoped, all must agree —
  reuse `Reference` / `SameEvent`.
- **`judge.set` is not a run** (old app): a manual judgment already leaves its own row. Only the
  agent-driven invocations (`search.run`, `judge.run`, `discover.run`) get a receipt.

---

## Fundamental principles — non-negotiable

1. **Nothing gets a golden ticket.** No concept crosses without being discussed and refined with me
   first. Acute here: `whether`/`when`, the narrative/extraction/assembly questions, and the full
   `event_prompts` question enum are old-app machinery — none is auto-included.
2. **Doc first, then code.** New vocabulary (the pin; and Run *iff* fork 2 makes it a concept) goes
   into `docs/pages/` in plain language, marked **planned**; I review it whole. Only then code.
3. **Ash first.** Every persisted concept is an idiomatic Ash construct; `mix ash.gen.*` first, then
   refine. (Clients/runner are plain infrastructure modules, like `Tree`/`Normalize`.)
4. **Warnings in our own code are errors.** Library warnings are not.
5. **Comprehensive tests are mandatory**, and they test outcomes, not implementation. **The network
   is never in the suite** — drive clients through `Req.Test` / an injected stub.
6. **Done means congruent.** Doc, code, and database say the same thing in the same words.
7. **The doc says what things *are*.** How they are stored, fetched, or retried is technique, and
   belongs in the code.
8. **Commit each concept the moment it is green and congruent** — straight to `main`.
9. **An invariant enforced only in a read is not enforced.** Gate the writes.
10. **No new dependencies without asking.** Pre-approved: `Req` (already a dep) and
    `date_time_parser`. Both the X client and the inference client are plain `Req` — **this layer
    needs no new dep.** If you think it does, stop and ask.

---

## Heuristics — earned the hard way

- **Measure, never assert.** A number, or it did not happen.
- **The old app has a real database — use it as evidence.** `wekui_dev.db` (READ-ONLY on the
  original; disposable copy to write) holds one event. This layer's numbers, already pulled:
  **727 runs** — 677 `judgment`/completed, **31 `judgment`/running (crash/gated)**, 9
  `acquisition`/completed, 10 `discovery` (5 running); **0 `interrupted` ever** (the enum value is
  dead — drop it, keep the *concept* "a `running` row that never finished"). **14 `event_prompts`**
  across `whether/what/where/when/discovery/who/narrative/extraction`, superseding as prompts were
  re-pinned. Re-query for: run `summary` shapes actually stored, options actually passed, and how
  many acquisition runs a real Search took.
- **Reproduce before fixing.** Failing test first, watch it fail, then fix.
- **Absent is not zero. Derived beats stored.** (Query state, coverage, Where — all derived. Keep
  the run `summary` a stored receipt because it is a *record of a past act*, not a recomputable fact
  — the numbers cannot be re-derived once the frontier moved.)
- **Attempt the extraction to judge it.** The pin *is* the judgment mechanism — reuse, do not
  re-invent. The two clients share a "behaviour + Req live impl + Req.Test" shape — extract only if
  the second call site actually wants it.
- **Compile before codegen.** `mix compile --warnings-as-errors` on a new resource *before*
  `mix ash.codegen` — catch the partial-index / identity trap while the migration is cheap to shape.
- **Verify the RETURN, not just the write** for the pin (supersession must return the *new current*
  pin and leave the old closed) and the run (finalize must set `summary` + `finished_at` and flip
  `status`).
- **Check for an Ash builtin first** before hand-rolling.
- **Never coin a word that is not in the doc.**
- **If you disagree with a review finding, say so and explain.** Surface deviations from a decision
  I made as a *choice*, not a footnote. (Last audit, the advisor's "judgment runs need a new LLM
  dep" was wrong — the old worker is plain `Req` to DeepInfra; the primary source corrected it.
  Do that: check the source, don't inherit an assumption.)
- **When a fork hinges on an operational fact, go get the fact.** Fork 1 hinges on whether a
  `twitterapi` token and an inference token exist in config — that is not a design opinion, it is a
  `grep` + a question to me.
- **Delegate the wide read, keep the coupled core.** Fan out to read all `pipelines/*.ex` + the two
  clients + query the DB in parallel; build the pin/run/runner yourself; adjudicate every finding.
- **Call `advisor` at the real forks and before declaring done**, deliverable already durable.

---

## Strategy — the streamlined loop (operator wants to move faster where patterns are settled)

1. **Read once, in parallel.** Old source: `lib/wekui/runs/run.ex` + `runs.ex`, `runner.ex`,
   every `lib/wekui/pipelines/*.ex` (`scope`, `discover`, `extract`, `judge`, `assemble`,
   `narrative`, `template`), both clients (`clients/twitter_api.ex` + `twitter_api/live.ex`,
   `clients/worker.ex` + `worker/deep_infra.ex`), and `judgments/prompt.ex` + `event_prompt.ex` +
   the `pin_prompt!`/`close!`/`link!` helpers in `judgments.ex`. New repo: the built `actor.ex`,
   `search.ex`, `query.ex`, and the judgment `Changes.*`. Query the old DB for the run/pin numbers.
   A subagent fan-out is justified for this breadth.
2. **Settle fork 1 first, in prose, with me — a real stop-and-wait.** Present the two clients (both
   Req), the credential gate (what tokens exist), and the two honest options (live end-to-end vs
   behaviours + `Req.Test`, ready-to-run). Recommend one, even-handedly. Then batch the rest of the
   forks (pin question-enum, Run vocabulary-vs-machinery, run kinds in scope, Query frontier, Run
   shape, domain) in prose with a recommendation each. Reserve a second stop only for genuinely new
   vocabulary (the pin, and Run if it becomes a concept).
3. **Write the new vocabulary into `docs/pages/`** (load the `ubiquitous-language` skill first),
   plain language, **planned**, hub lines updated; I review the whole vocabulary once.
4. **Build sub-concept by sub-concept, committing each green, in this order** (cleanest → riskiest):
   **(a) the agent pin** — reuses the built superseding mechanism, no execution, pure record; proves
   the mechanism generalizes past judgments. **(b) the Run receipt** — born `running`, finalized
   `completed`, `options`/`summary` maps; still a pure record. **(c) the runner + clients** — the
   execution decision from fork 1 lives here; this is where HTTP, retries, the frontier, and the
   `Capture`-transaction-per-page live. For each: generate → refine → `mix ash.codegen <name> --yes`
   → migrate dev+test → comprehensive tests (network via `Req.Test`) → `advisor` + self-trace of
   novel logic → `mix precommit` + `mix ash.codegen --check` clean → unmark the doc → commit + push.
5. **Verify hard where it is novel.** `advisor` before committing to the execution approach and
   before declaring done; `/simplify` on novel code (skip-with-reason if it only mirrors settled
   code); a rigorous self-trace of the runner's failure/resume logic (I run `/code-review` — it is
   user-triggered and billed; you cannot launch it, so point me at the novel surface).
6. **Update memory and the docs** as each piece lands. If acquisition went live, note that the
   audit's OBS-1 (every Post ≥ 1 Appearance) is now *enforced by construction*; if stubbed, leave it
   open with a pointer.

---

## Tactics — commands and repo facts

```bash
# Generate (flags that work)
mix ash.gen.resource Wekui.Runs.Run --domain Wekui.Runs -u id \
  -a 'kind:atom:public,status:atom:public,options:map:public,summary:map:public,started_at:utc_datetime_usec:public,finished_at:utc_datetime_usec:public' \
  -r 'belongs_to:event:Wekui.Core.Event,belongs_to:search:Wekui.Acquisition.Search,belongs_to:actor:Wekui.Core.Actor' \
  --extend sqlite --yes           # then hand-edit: born-running create, finalize update, constraints

mix compile --warnings-as-errors  # BEFORE codegen — catch the partial-index/identity trap early
mix ash.codegen <name> --yes      # migration + snapshots
mix ash.codegen --check           # drift check; must be silent (exit 0)
mix ecto.migrate                  # + `MIX_ENV=test mix ecto.migrate`
mix precommit                     # docs_doctor + compile(warnings-as-errors) + format + test

# Old app evidence (READ-ONLY original; copy first to write)
sqlite3 -readonly /Users/anibal/Sandboxes/Venezuela7275/wekui/wekui_dev.db \
  "SELECT kind,status,count(*) FROM runs GROUP BY 1,2;"
```

- **The pin reuses the judgment mechanism verbatim.** Slot `(event_id, question)`; `Changes.Supersede,
  slot: [:event_id, :question]`; `Changes.Retract`; a `custom_indexes` partial unique on
  `WHERE superseded_at IS NULL`; `judged_at`→`pinned_at`. `question` is a constrained `:atom`
  (`one_of:` only the questions we actually pin — see fork 3). The pin points at an **Actor** (agent),
  not a bare prompt — an agent already *is* `(model, prompt)`, content-addressed.
- **The Run receipt idiom.** `create :start` born `status: :running`, `started_at` defaulted, sets
  `options`; an `update :finalize` sets `summary`, `finished_at`, `status: :completed`. No state
  machine needed for two states (drop `:interrupted`; a `running` row on read is the crash signal).
  `options`/`summary` are `:map` (the `payload` idiom) — the run summary is a *stored receipt*, not
  a derived value.
- **Clients are injected behaviours (mirror the old app).** `@callback` behaviour +
  `Wekui.Clients.TwitterApi.Live` (Req GET to the `twitterapi` service) + `Wekui.Clients.Worker.Live`
  (Req POST to the inference API). Config picks the impl (`Application.get_env`); tests pass a stub
  or `plug: {Req.Test, Mod}`. **Both are `Req` — no new dep.** The credential/config gate (a
  `twitterapi` token, an inference token) is fork 1's real hinge — `grep` config + ask me.
- **The runner is the crash-safe drain.** `run_search/2`: (optionally advance an open window), read
  `Acquisition.list_runnable_queries/1`, run each query paginating against the client, **each page a
  single `Wekui.Repo.transaction` that writes Posts+Appearances and advances the frontier** so a
  crash resumes. Failure fates: *transient* → bounded retry, frontier holds, resume; *permanent* →
  discard the Query with the reason. Opens an `acquisition` Run, finalizes with the summary
  (`queries_run / completed / discarded / incomplete / pages / new_posts / refound / appearances /
  errors`). `Task.async_stream/3` (if used) **always** `timeout: :infinity`.
- **Frontier state on Query — only if live acquisition lands (fork 1 + fork 6).** The old runner
  uses `query.cursor` + page counters; wekui-new's `Query` (just audited clean) has none. Adding
  `cursor`/`pages_fetched` modifies an audited resource — gate it explicitly on real collection
  being in scope; do not add it for a stubbed path.
- **Regenerating an unshipped migration:** delete the migration file *and* its snapshots under
  `priv/resource_snapshots/repo/<table>/`, regenerate, then drop **both** DBs
  (`mix ecto.drop --force` and `MIX_ENV=test mix ecto.drop --force`) before `mix ash.setup`.
- **`CLAUDE.md` is a symlink to `AGENTS.md`.** Edit `AGENTS.md`.
- **Test helpers:** grow `Wekui.Fixtures` (`run!`, `pin!`, a `Req.Test` stub helper) and use
  `error_on/2` in `Wekui.DataCase`.

---

## Tooling & environment protocol (repo-specific — this bit trips people up)

**The docs are an outl workspace with a live desktop app.**
- `docs/pages/*.md` are outl outlines: ONE physical line per bullet (never hard-wrap), two-space
  indent, `key:: value` props at the very top then a blank line, `[[slug]]` links. **Prose**
  (headings, code, tables — like THIS file and `ubiquitous-language-audit.md`) lives at **`docs/`
  root only**; outl bulletizes anything inside `docs/pages/`. A root prose doc gets **no `.outl`
  sidecar**.
- **Load the `ubiquitous-language` skill** before authoring/creating any page.
- Hub = `docs/pages/ubiquitous-language.md`; meta map = `docs/pages/index.md`. Concept pages carry
  `type:: concept` + `status:: built|planned`; open questions are `open-*` with `opened::`; an
  answered open page **shrinks to a pointer, never silently deleted**.
- Lint a page: `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )' docs/pages/<p>.md` → no output; every `[[slug]]`
  must resolve to a file. `mix precommit` runs a `docs_doctor` step. `outl -w docs doctor` is
  read-only and coexists with the app.
- **The `outl-desktop` app is (as of the audit session) RUNNING** (`pgrep -lf outl`). It adopts
  existing-page edits live and reprojects `.outl` sidecars — **NEVER start a second outl process.**
  Editing an existing page needs nothing. For a NEW page: the committed pre-commit hook
  (`git config core.hooksPath .githooks`, already enabled) handles the adopt pass — but **while the
  GUI is attached it DEFERS to the app and only warns**, so a new `.md`'s sidecar is regenerated by
  the app, not the commit.
- **STAGING — the landmine (lived it this session).** With the GUI attached, `.outl` sidecars are
  reconciled **separately** from the `.md` — a concept commit stages **`.md` + code only**; the
  `placement.outl` from the audit is still pending such a reconcile. **Stage explicit paths; never
  `git add -A` / `commit -am`.** Run `git status --short` and `git diff --cached --name-only`
  before every commit, and exclude `.outl` + unrelated live-app churn.

**Isolate a shared-infra extraction in its own commit**, with the full suite green *before* any new
code — that green suite is the proof of no-behaviour-change. (Reusing the judgment mechanism for the
pin needs no extraction; it is already shared.)

---

## Anti-goals

- Do not write code before I have approved the vocabulary AND fork 1 (execution reach).
- Do not transliterate the old app. Every field and every `question`/`kind` must earn its place —
  `interrupted`, the un-ported questions, and `assembly`/`narrative` run kinds are not golden tickets.
- Do not invent vocabulary. The pin (and Run, if it becomes a concept) goes in the doc first.
- **Do not add a dependency.** Both clients are `Req`. If you reach for an LLM SDK, an HTTP mock lib,
  or a job runner (`Oban`), STOP and ask — none is needed for this layer.
- **Do not put the network in the test suite.** Drive clients through `Req.Test` / an injected stub.
- Do not claim the audit's OBS-1 is closed unless live acquisition actually shipped this session.
- Do not build the OUTPUT layer opportunistically — Beat / Narrative / extraction / assembly is the
  fork you did **not** pick; a run *kind* for it does not exist until that concept does.
- Do not build one mega-commit. Pin, then Run, then runner — each green, straight to `main`.
- Do not re-introduce branches/PRs (lean-git). Do not fan out subagents for what you can do yourself
  in a few calls; do fan out for the wide old-app read + DB queries.

---

## State snapshot (where we are now)

- **Built & green:** Core (incl. Actor), Acquisition, Capture, Taxonomy, **the full Judgment
  cluster** — **372 tests**, `mix precommit`, no drift.
- **Just done:** a full docs↔code↔tests fidelity audit (`docs/ubiquitous-language-audit.md`). One
  finding, fixed (placement's where-read now says "proposed or active"). One open observation:
  **OBS-1 — "every Post has ≥1 Appearance" has no enforcement yet**; the runner this session is what
  would enforce it by construction.
- **Git:** everything on `main` (local + `origin/main`); last commit `edf492d` (the audit). Work
  directly on `main`. A `placement.outl` sidecar reconcile is pending from the audit session —
  exclude it from concept commits (or let the operator commit the reconcile).
- **Docs:** congruent. No `planned` concept pages currently — this session introduces the first new
  ones (the pin; maybe Run).
- **Evidence base:** `research-2026-07-23-old-app-corpus`, `docs/clustering-spike.md`, the run/pin
  numbers in Heuristics above, and the two clients' shapes (both `Req`).

---

## This session's task: the Runs / pipeline execution layer

Build the record of the system's own execution and the machinery that produces it: the **agent
pin**, the **Run receipt**, and the **runner** (with its clients), scoped to the pipeline stages
whose *output* vocabulary already exists.

**Anatomy (from a first read — confirm and deepen it):**
- **`Wekui.Runs.Run`** — "an execution receipt: one row per `search.run` / `judge.run` /
  `judge.rejudge` / `discover.run`" (`judge.set` is *not* a run). Fields: `kind`
  (`:acquisition | :judgment | :discovery`), `question` (nullable; acquisition carries none),
  opaque `options` + `summary` maps, `status` (`:running → :completed`; **`:interrupted` never
  used — 0 rows**), `started_at`, `finished_at`; belongs_to event, search (optional), **prompt**
  (→ Actor(agent) here). Born `running`; finalized `completed` with the CLI-envelope `summary`; a
  `running` row on later read is a crash artifact.
- **`event_prompts`** (14 rows) — the per-event **agent pin**: which prompt currently answers a
  question for an event. One current per `(event_id, question)` (partial unique on
  `superseded_at IS NULL`), history preserved, atomic supersession via `pin_prompt!` (sole writer).
  This is the built judgment mechanism under a different name.
- **`Wekui.Runner`** — the synchronous engine that drains an `active` Search's runnable Queries
  against the X client, paginating with a `cursor` frontier, each page one crash-safe `Capture`
  transaction; opens/finalizes an `acquisition` Run. Transient vs permanent failure fates.
- **`Wekui.Pipelines.*`** (`scope`/`discover`/`extract`/`judge`/`assemble`/`narrative`) — the stage
  bodies; each pins a prompt (agent), calls the worker client, writes its judgments, and opens a run.
- **Both clients are `Req` behaviours** with `.Live` impls + `Req.Test` mocks: `TwitterApi`
  (GET a `twitterapi` service) and `Worker`/`deep_infra` (POST an inference API). **No new dep.**

**The `question` vocabulary maps cleanly onto what is built vs deferred:**
`what → theme-judgment`, `who → author-tag-judgment`, `where → placement` (**built**);
`discovery`/`extraction` → propose Places/Themes/Tags (**`proposed_by` is built**);
`whether`/`when` → relevance/time (**deferred concepts**); `narrative`/`assembly` → Beat
(**deferred — the output layer you did not pick**).

**The forks I expect — batch them with a recommendation each (inline prose, not a click-through).
Reserve a real stop-and-wait for #1, and for any genuinely new vocabulary (the pin; Run iff #2
makes it a concept).**

1. **Execution reach — THE decision.** Both clients are `Req` (no new dep). The real gate is
   operational: is there a `twitterapi` token and an inference token in config? Two honest options:
   **(a)** wire **real end-to-end** execution (needs the tokens) — this actually collects, and
   *closes OBS-1*; or **(b)** build the Run + pin + runner + client **behaviours with `Req` live
   impls, tested via `Req.Test`**, ready to run live the moment tokens are set — no network in the
   suite, OBS-1 stays open. Recommend one after checking whether the tokens exist. Do **not**
   pre-steer to defer — the option you selected framed Runs as "toward working."
2. **Run — vocabulary or machinery?** It is the first record of the *system's own* execution, not of
   the world. Does it get a `docs/pages/` concept page (doc-first gate), or an `architecture` stance
   + code (like the outl op-log — "machinery, not the record")? It is operator-facing persisted state
   with a lifecycle (`run.list`), which leans concept; the op-log precedent leans machinery. Decide
   deliberately, don't default.
3. **The pin's `question` enum.** Its slot is `(event, question)`, and `question` spans un-ported
   concepts (`whether/when/narrative/extraction/assembly`). Carry the full old enum, or constrain
   `one_of:` to only the questions we can actually pin today (`what/who/where`, plus
   `discovery/extraction` iff those stages are in scope)? Recommend: pin only built questions; widen
   the enum as concepts land — don't encode vocabulary that does not exist.
4. **Which run *kinds*/stages are in scope.** `acquisition` (→ Capture) and `judgment` (→ built
   theme/tag/placement) are clearly in. `discovery`/`extraction` feed `proposed_by` (built) — in or
   deferred? `assembly`/`narrative` feed Beat (not built) — **out**. Recommend: `acquisition` +
   `judgment` for sure; `discovery` only if its output path is trivial; scope `Run.kind`
   accordingly.
5. **Run shape in Ash.** Two-state receipt: `create :start` (born `running`) + `update :finalize`
   (sets `summary`/`finished_at`/`completed`). Plain, or a state machine? Recommend plain (two
   states don't warrant `AshStateMachine`); drop `:interrupted` (0 rows) but keep the *concept* "a
   `running` row that never finished"; `options`/`summary` as `:map`.
6. **Frontier state on Query.** Live acquisition needs resumption state (old `cursor` + page
   counters); wekui-new's audited-clean `Query` has none. Add `cursor`/`pages_fetched` to `Query`
   (gated on fork 1 = real collection), or carry the frontier on the Run? Recommend: on `Query`, and
   **only if** live acquisition lands — don't modify a clean resource for a stubbed path.
7. **Domain placement.** A new **`Wekui.Runs`** (or `Wekui.Pipeline`) domain — Run + agent-pin, with
   the runner/clients as infra modules — referencing Core/Acquisition/Capture/Judgment? Recommend a
   new domain (it cross-references nearly everything).
8. **Scope guard — un-vocabularied questions.** `whether`/`when` and the whole
   narrative/extraction/assembly branch are old-app machinery with real data but **no new
   vocabulary**. Flag each as its own concept candidate (like Beat); do not port silently. `options`
   and `summary` are opaque maps, not vocabulary — do not mine field names out of them into concepts.

**Start by** reading the old `runs/run.ex` + `runs.ex`, `runner.ex`, every `pipelines/*.ex`, both
clients (`twitter_api/live.ex`, `worker/deep_infra.ex`), and `judgments/event_prompt.ex` +
`pin_prompt!`; and the built `actor.ex`/`search.ex`/`query.ex` + the judgment `Changes.*`. Query the
old DB (disposable copy to write) for the run summary/options shapes and the pin history. `grep` the
old + new config for the `twitterapi`/inference tokens (fork 1's hinge). **Bring me fork 1 settled,
the anatomy, the remaining forks batched, and a proposed doc refinement — not code.**

---

## Loose ends — a prioritized backlog (pick from these; do not lose them)

Some are now *in scope* via this layer (⟶); the rest stay parked.

- ⟶ **Audit OBS-1:** "every Post has ≥1 Appearance" — enforced by construction once the runner
  creates Post+Appearance in one transaction (only if live acquisition ships).
- ⟶ **`placement.outl` reconcile** pending from the audit session — commit it (or let the operator).
- **Core:** `set_unplaced_place` is unguarded (accepts a foreign/proposed/nil place); the reparent
  cycle check is read-then-write with no depth-guard on the `Wekui.Tree` CTEs; `unplaced_place_id`'s
  FK omits explicit `on_delete: :restrict`; "deprecated is final" for Place is untested (Theme tests
  it — backfill Place).
- **Acquisition:** `extend_window` on an *open* window doesn't reject an end behind existing
  coverage; anchored-name groups aren't operator-capped against X's limit. **`Query` needs
  resumption state if live acquisition lands (fork 6).**
- **Capture:** the cross-event error blames an arbitrary field when two references disagree
  (cosmetic); `SameEvent` swallows read errors as "does not exist".
- **Parked carry-overs:** `Core.list_active_places/1` *includes* the Unplaced Place — decide if the
  read should exclude it; whether a Query's state should be stored for speed (`open-query-state`).
- **Deferred concepts (candidates after this layer):** `whether` (relevance), `when` (time),
  **Beat/Narrative** (the output layer), the **person write-path** (`open-actor`), dedup
  (`docs/clustering-spike.md`).

---

## What worked last session — do more of it

- **Doc-first gate.** Vocabulary before code, reviewed whole — it caught real drift before it
  hardened, and the audit found the code and vocabulary in tight agreement because of it.
- **Batched, recommended forks; a real stop only for the load-bearing one.** The operator answers
  inline with a recommendation each; reserve `AskUserQuestion` / stop-and-wait for the genuinely
  load-bearing fork (here: execution reach).
- **Spike open questions against the old DB** on disposable copies — it settled `merge-is-deprecation`
  (0 rows → design-led) and corrected the "proposed_by will be empty" prior. Do it for the run
  summary/options shapes and the pin history.
- **Reuse the settled mechanism.** The judgment cluster's `Supersede`/`Retract`/partial-unique is the
  pin, verbatim — attempt the reuse first, don't re-invent.
- **Compile before codegen; verify the RETURN; check builtins first; network never in the suite.**
- **Commit each concept the moment it is green — straight to `main`**, explicit paths only, excluding
  `.outl` sidecar churn.
- **`advisor` at the forks and before declaring done**, deliverable already durable. Give its
  findings real weight, and **check the primary source** — it corrected the audit's page count and
  test-claim honesty; the operator's own `grep` corrected its "needs a new LLM dep" assumption.
- **Collaboration style that fits the operator:** decide the obvious, batch the genuine forks with a
  recommendation each; measure before asserting; report faithfully (tests failing = say so); lean
  process, high quality bar — and move faster where the patterns are settled.
