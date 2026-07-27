# Kickstart: the curation path — a human decides, and the record says who

The read path is **built, orchestrated and proven live**: posts → claims → gazetteer places →
a support verdict → the Spanish a reader meets, in one auditable [[run]]. The operator can now
*read* the record (`mix run priv/scripts/report.exs`) and *answer* the questions it raises. What
he cannot do is have those answers land as **attributed acts**. This session closes that loop.

It is not a new idea. [`docs/pages/open-actor.md`](pages/open-actor.md), open since 2026-07-22,
says it exactly:

> the open question is not *what is a person* but *what does recording a person's act require*:
> how we name a person, and whether attribution is settled the moment the first curation act
> needs a who. **It waits for that first act.**

**That act happened on 2026-07-27** — and happened *unattributed*, which is the debt this session
pays. See "The first acts, and their honest debt" below.

**Read first:** [`docs/pages/index.md`](pages/index.md) → [`ubiquitous-language`](pages/ubiquitous-language.md),
then [`actor`](pages/actor.md) + [`open-actor`](pages/open-actor.md) (the question you are
answering), [`person`](pages/person.md), [`place`](pages/place.md), [`claim`](pages/claim.md),
[`run`](pages/run.md), and [`principle-never-rewrite-the-record`](pages/principle-never-rewrite-the-record.md).
Then the live design docs: [`orchestration-scenarios.md`](orchestration-scenarios.md) (what the
last session settled and why) and [`evaluation-matrix.md`](evaluation-matrix.md) (honest
layer-by-layer status). Skim `lib/wekui/report.ex` — it is the surface this work serves.

---

## Priors — settled, do not relitigate

**The pivot.** The in-app research agent *is* the product; the June 2026 La Guaira / Caraballeda
earthquake record is its eval harness. `wekui-new` (Ash) is canonical; the old Ecto `wekui` is a
reference to mine and retire. Build by vertical slice, **seed-first**. The deliverable is a cited
answer + a dignity-safe narrative for a public, donations-facing memorial.

**Built and green — 496 tests, `mix precommit` clean, `mix ash.codegen --check` exit 0.**
- `Wekui.Core` (Event, Place, PlaceName, **Actor — agents only**), `Wekui.Capture`,
  `Wekui.Acquisition`, `Wekui.Taxonomy`, `Wekui.Judgment`.
- `Wekui.Narrative` — Claim + ClaimCitation + ClaimPerson + ClaimPlace, Person, Handle,
  PrivateNames (the F54 gate), Merge (**executes** a fold; the judge is unbuilt), PlaceResolver,
  BeatRenderer.
- `Wekui.Pipelines` — `Run` (the receipt), `ReadPath` (a Reactor), `run_read_path/4`,
  `Extract`, `Verify`.
- `Wekui.Report` — the record as markdown a person can read and answer.
- `Wekui.Clients.Worker` (behaviour + `.Live` over `Req` → DeepInfra) and `Wekui.Gazetteer.Seed`.

**The orchestration decisions (2026-07-26), all settled.** Read
[`orchestration-scenarios.md`](orchestration-scenarios.md) rather than re-deriving:
- The pipeline runs on **Reactor** ([`decision-2026-07-26-reactor-not-sagents`](pages/decision-2026-07-26-reactor-not-sagents.md)).
  `sagents` was a misread and is **removed**; `langchain` stays for the later talking rung.
- A **run is vocabulary**, not machinery: two states, born `:running`, finalized `:completed`.
- **Extract once per event** ([`decision-2026-07-26-extract-once-per-event`](pages/decision-2026-07-26-extract-once-per-event.md)):
  no current claim → extract; any current claim → skip unless `extract: :force`.
- **No retries, no undo callbacks.** A stage records the errors it can catch in the summary; a
  raise leaves the receipt `:running`, which IS the crash signal.
- Gates **record**, never pause. The blocking gate is future spend, designed with acquisition.

**The live proof.** Task 0b ran for real: 9 posts → 8 claims → 7/8 mentions linked → 8/8
supported → a cited Caraballeda beat. Receipt `7bb0dcc3`. 23 seconds, pennies. Eight claims where
the old stub-tree pilot got nine — measured single-pass MoE variance (`"skipped": 0`, empty
`"skips"`), not a regression.

**The operator's review (2026-07-27) — his answers are facts now, not proposals.**
- The Caribe **towers** were siblings of the community they belong to; both are now beneath
  `Conjunto Residencial Caribe`. His words: *"if there are many buildings or towers part of a
  community, which was affected, or the one where help is required, or where people died, is
  relevant. That's why we have a recursive model, to allow this granularity."*
- The three "Residencias Caribe" claims **stay on the community** — the posts named no tower.
- `"Caraballeda-La Guaira"` is Caraballeda, under La Guaira (the state, formerly Vargas). Linked
  by hand, `how_resolved: :manual`, no confidence.
- All five handles **approved**. He read all 8 claims and the beat: *"Correct"* / *"Looks good."*

**Gazetteer sourcing — decided, build deferred.** Future events self-seed from OpenStreetMap by
bounding box, ODbL accepted ([`decision-2026-07-26-gazetteer-from-osm`](pages/decision-2026-07-26-gazetteer-from-osm.md)).
Not this session.

**Git — lean.** Solo, no PRs, no branches. Commit each sub-concept straight to `main` the moment
it is green, with the `Co-Authored-By` + `Claude-Session` trailers. Never a mega-commit.

**Two ash_sqlite realities.**
1. An identity's `where` is **not** a partial index. "One current X per slot" is a
   `custom_indexes` partial unique, never an Ash identity.
2. ash_sqlite **cannot run Ash-managed transactions** (`transaction? true` is a no-op). Multi-step
   atomic work uses an explicit `Wekui.Repo.transaction/1` (as `Merge.do_merge` does).

**Conventions locked.** `uuid_primary_key :id`; FKs `on_delete: :restrict`; no multitenancy (plain
`belongs_to :event` + `Wekui.Validations.Reference` / `Capture.Validations.SameEvent`); immutable
facts = `upsert? true` + `upsert_identity` + `upsert_fields []`; a mutable link upserts its
changing fields; opaque blobs are `:map`; code interfaces via `define` on the domain block.

---

## The live question waiting for him — do not lose it

**Q2 of the report is unanswered:** two places are called "Caraballeda" — the **parroquia** (under
Vargas) and the **populated_place** inside it. A bare "Caraballeda" ties between them, which is why
the resolver scored 0.5. The symptom is visible in the beat: **"En Caraballeda" appears twice**,
because Julio's claim sits on the parroquia and the woman's rescue on the populated_place, so they
group as if they were two places.

Ask it early — the answer may be "one place recorded twice," which is a gazetteer merge, or "a bare
mention means the parroquia," which is a resolver rule. Either way it is a *curation act*, so it is
the perfect first customer for what you are building.

---

## Fundamental principles — non-negotiable

1. **Doc-first, scenarios-first.** New vocabulary goes to `docs/pages/` (load the
   **`ubiquitous-language` skill** first). New *behaviour* gets a scenarios doc at `docs/` root
   with `[PROPOSAL]`/`[OPEN]` markers, annotated by the operator, *then* code. This is the pattern
   that aligned extraction, naming, place-mapping, beats and orchestration.
2. **Done means congruent** — doc, code and database say the same thing in the same words. This
   session exists because they *disagree*: [`actor`](pages/actor.md) already asserts *"Wherever
   this vocabulary says that something was approved, proposed, judged or retired, an Actor did it,
   and we record which one"* — and the code records no such thing for a human. Close the gap, and
   update `status::` on every page whose code caught up.
3. **The record is never rewritten** ([`principle-never-rewrite-the-record`](pages/principle-never-rewrite-the-record.md)).
   We append; we never edit history to match new understanding. The deliberate exception is a
   *link*: `ClaimPlace` is mutable by design ("re-resolution overwrites the provenance and
   confidence"). Know which one you are touching before you touch it.
4. **A wrong answer is worse than none** ([`principle-a-wrong-answer-is-worse-than-none`](pages/principle-a-wrong-answer-is-worse-than-none.md)).
   Never invent precision the evidence does not reach — link the community when no tower was
   named. An honest absence beats a guess.
5. **The dignity red line is mechanical (F54), never a prompt.** `NoPrivateName` refuses a private
   name in a Claim `subject`, checked against the event's **`:active`** gazetteer plus the
   public-figure allowlist. A machine-proposed place is `:proposed` and cannot widen the gate until
   a human promotes it. **A curation act can widen it — that is exactly why it must be attributed.**
6. **Deterministic ~90%, LLM for the last ~10%, and never an LLM over an LLM.** Nothing in this
   session needs a model at all.
7. **Ash-first** for persisted concepts (`mix ash.gen.*`, then hand-edit). Orchestrators, clients,
   renderers and the report are plain infra modules.
8. **Warnings in our code are errors. The network is never in the suite** (`Req.Test` / injected
   stub). **No new dependencies** — ask first; `date_time_parser` is the only pre-approval.
9. **Measure, never assert.** Commit each concept the moment it is green.

---

## Heuristics — earned the hard way, most recently

- **`advisor` at the real forks and before declaring done**, deliverable already durable. It has
  earned its keep every session: it caught the ClaimPlace mutability, the merge place-union, the
  `:active` gate-widening risk, the retries-without-compensate lie, and the citation-coverage
  misfire below — all before they shipped. Give its findings real weight, then check the primary
  source yourself.
- **Measure a rule against real data before shipping it.** The proposed re-run rule ("partially
  cited → refuse loudly") died on one query: the pilot has **8 of 9 posts cited**, because v5
  correctly drops noise and a dropped post is cited by nothing. *A rule that fires on the happy
  path is not a safety net, it is noise.*
- **Ask the sharper question.** The report's first "which place?" question offered look-alikes and
  buried the real tie. Two fixes made it answerable: a place carrying the **same name outright**
  beats a name that merely starts alike, and a look-alike **beneath** the linked place is no rival
  at all — the tree settles it, so *fixing the tree makes the question disappear*.
- **Verify the RETURN, not the vibe.** "7 of 8 mentions linked" read as clean until the links
  themselves were queried; three claims turned out to hang on one gazetteer alias at an
  overstated 0.9.
- **`Enum.sort_by` over `DateTime` structs without a `DateTime` sorter compares maps key by key**
  — day before month before year. It silently mis-ordered beats across a month boundary. Any
  `sort_by`/`min`/`max` over dates names its sorter.
- **Reactor rescues a raising step**: the caller gets `{:error, exception}`, it does not propagate.
  And Reactor only retries where a `compensate/4` returns `:retry` — a bare `max_retries` is a
  claim the code does not keep.
- **An Ash `:map` column takes string-keyed JSON scalars only.** `BeatRenderer.render/3` returns a
  full `Place` struct; projecting it is mandatory. Assert the value **reads back** identically.
- **Every Event is born with an `:active` Unplaced Place**, so "does this event have active
  places?" is always true. Discount `event.unplaced_place_id` in any gazetteer guard.
- **`usage_rules` only discovers top-level deps** — a transitive one is silently skipped, which is
  why `reactor` is now declared in `mix.exs` (no new package; `mix.lock` untouched).
- **`Logger.configure(level: :info)` at the top of a script**; dev logs every query at `:debug` and
  drowns the output.
- **Make every script idempotent** (find-or-create + upsert) and commit it: a dated one-off like
  `priv/scripts/curate_2026_07_27.exs` *is* the audit record of what a human decided.
- **Iterate prompts by removing, not adding**; test on the production model, N≥3. (Not needed this
  session — no prompt work.)

---

## Strategy — the loop for this session

1. **Read once, in parallel**: `lib/wekui/core/actor.ex`, `lib/wekui/narrative/person.ex`,
   `lib/wekui/core/place.ex`, `lib/wekui/narrative/claim_place.ex`,
   `lib/wekui/judgment/validations/provenance.ex`, `lib/wekui/report.ex`, and the pages listed at
   the top. **A subagent fan-out is not justified** — this is a small, dense surface.
2. **Settle the forks below.** Fork 2 (stamp vs. record) is load-bearing: bring both, recommend
   one, stop and wait. Batch the rest inline with a recommendation each.
3. **Build sub-concept by sub-concept, committing each green:** person Actor → attribution on the
   curation acts → the `Curation` surface the agent calls → the report showing what is already
   settled. For each: `mix ash.gen.*` → hand-edit → `mix compile --warnings-as-errors` **before**
   `mix ash.codegen <name>` → migrate dev **and** test → tests → `advisor` → `mix precommit` →
   commit.
4. **Answer Q2 with him, and apply it through the new path** — the first attributed act, and the
   proof the loop closed.
5. **Close [`open-actor`](pages/open-actor.md)**: write the dated decision page, then shrink the
   open page to a pointer (never delete it — the outline convention is in the
   `ubiquitous-language` skill). Update [`actor`](pages/actor.md) so its attribution claim is true.
6. **Re-run and regenerate** — `mix run priv/scripts/read_path.exs` (it will skip extract) then
   `mix run priv/scripts/report.exs` — and hand him the file.
7. **Update memory + the evaluation matrix** as pieces land.

**Definition of done.** A human decision — approve a person, relink a claim, reparent or promote a
place, retract a claim — is recorded with **who** made it, **when**, and **why**, through an Ash
action; the report shows what is already settled so it stops re-asking; `open-actor` is closed by a
dated decision; `actor.md` no longer over-claims; `mix precommit` clean; each piece its own commit.

---

## The forks — batched, with a recommendation each

1. **How a person Actor is named.** *Recommend:* add `name` to `Actor` plus
   `register_person`, with `identity :unique_person, [:event_id, :name]`. Agents leave `name`
   NULL, and SQLite treats NULLs as distinct in a unique index, so many agents coexist under it —
   **verify that** before relying on it. `Provenance` already handles `kind: :person` (a person's
   judgment carries no confidence), so the validation layer is waiting for this.
2. **Attribution: a stamp, or a record? — THE fork.**
   - **(a) A stamp**: `decided_by_actor_id` + `decided_at` + `note` on each thing a human touches.
     Cheap, mirrors the existing `Place.proposed_by_actor_id`. Cost: a second correction
     **overwrites** the first, so "what did he change on the 27th?" is unanswerable — and that is
     [`principle-never-rewrite-the-record`](pages/principle-never-rewrite-the-record.md) losing.
   - **(b) A `Curation` record** — append-only, one row per human act, carrying the actor, the
     target, what changed, and the reason. *Recommended.* The symmetry is the argument: the
     system's own acts just earned a receipt ([`run`](pages/run.md)); a human's acts deserve no
     less, in a project whose whole thesis is auditability. It also answers `open-actor` properly
     rather than deferring it again. Consider a denormalized stamp **alongside** the record if
     reads need it — but the record is the truth.
   - Considered and set aside: reusing the [`judgment`](pages/judgment.md) spine. It is the right
     *shape* (an Actor's answer, append-only, superseding) but it is Post/Author-scoped; stretching
     it over Places and Persons costs more than it saves. Say so rather than silently skipping it.
3. **What a Curation points at.** *Recommend:* nullable FKs per target (`place_id`, `person_id`,
   `claim_id`, `claim_place_id`) with an "exactly one" validation — it keeps `on_delete: :restrict`
   integrity and the project's FK discipline, and there are only four targets. Alternative: a
   polymorphic `{target_type, target_id}` pair, which SQLite cannot enforce.
4. **Domain placement.** *Recommend:* a new `Wekui.Curation` Ash domain, following the
   `Wekui.Pipelines` precedent from last session — curation spans Core (places, actors) and
   Narrative (persons, claims), so it belongs to neither. Add it to `ash_domains` in
   `config/config.exs`.
5. **Does the report show what is settled?** *Recommend:* yes, and it is what closes the loop — a
   "settled" section naming the act, the person and the date, and questions suppressed once
   answered. Without it the report re-asks forever and the operator stops trusting it.
6. **How answers are applied.** *Recommend:* a `Wekui.Curation` code interface the agent calls,
   plus a dated one-off script per review as the audit trail. **Do not build a markdown parser**
   for `OPERATOR'S ANSWER:` blocks — the answers are prose with reasoning in them ("it should live
   *below*…"), and the reasoning is the valuable part. A parser would flatten judgment into
   syntax.
7. **Curation as vocabulary?** If fork 2 lands on (b), it is a concept:
   `docs/pages/curation.md` + its hub line, in the same commit as the resource. Same call the
   `run` page faced, and it went the same way.

---

## The first acts, and their honest debt

On 2026-07-27, before any of this existed, three curation acts were applied by
`priv/scripts/curate_2026_07_27.exs`: two places reparented, one claim linked by hand, five
persons approved. **None carries a who.** `how_resolved: :manual` says a person did it; it cannot
say which person.

**Do not retro-attribute them.** Inventing an actor row and back-dating it would be exactly the
rewriting the record forbids. The honest handling is a line in the decision page: these acts
predate attribution, and that committed script is their record. Say it plainly; it is a small,
real example of the discipline the whole project sells.

---

## Tactics — the tools, and repo facts

**Actions that already exist and need only a who** (this is the whole point — the curation surface
is an *attribution* layer over verbs that are already built):
```
Wekui.Core.set_place_parent!(place, %{parent_id:})     # cycle-safe
Wekui.Core.promote_place!(place)                       # :proposed → :active — the gate
Wekui.Core.set_place_type!(place, %{type:})
Wekui.Core.deprecate_place!(place, %{replaced_by_id:, note:})   # replacement required, note optional
Wekui.Core.discard_place!(place, %{note:})             # note REQUIRED, min_length 1 — the reason IS the record
Wekui.Narrative.approve_person!(person) / withhold_person!(person)
Wekui.Narrative.set_person_handle!(person, %{display_handle:})
Wekui.Narrative.set_person_kind!(person, %{kind:})
Wekui.Narrative.link_place!(%{claim_id:, place_id:, how_resolved: :manual, confidence: nil})
Wekui.Narrative.retract_claim!(claim)
```
`ClaimPlace.how_resolved` already carries `:manual` in its vocabulary — reserved for exactly this,
and first used on 2026-07-27. Its `confidence` doc says *"Absent when a human set it by hand"* — a
person decides, a person does not estimate. There is **no unlink action** for a ClaimPlace; if a
correction needs one, that is a deliberate addition to weigh, not an oversight to patch.

**The read path and the report:**
```
Wekui.Pipelines.run_read_path(event, agent, %{place_id:, from:, to:}, opts) :: {:ok, run}
Wekui.Report.render(event, opts) :: String.t()
```

**The scripts** (all idempotent, all committed):
```
mix run priv/scripts/pilot_event.exs   # task 0a — rebuild the clean event; no key, no spend
mix run priv/scripts/read_path.exs     # the pipeline; LIVE — see the warning below
mix run priv/scripts/report.exs        # writes tmp/<event>.md; free, read-only
mix run priv/scripts/curate_2026_07_27.exs   # his answers, applied
```

**The dev DB** (`wekui_dev.db`) holds three events:
- **`litoral-central-2026`** (`968e3d2c`) — the pilot. 9 posts, 8 claims, 297 active places,
  agent `8927561e`, Caraballeda parroquia `3beeb2e4`. Two run receipts: `7bb0dcc3` (the live
  first run) and `99ffa53e` (a re-pass that skipped extract).
- **`litoral-central-2026-stub`** (`eb8ec55b`) — the old pilot, renamed. Keeps its 9 posts + 10
  claims on the 6-place stub tree: the history of how the spine was proven. Do not extract on it.
- **`Caraballeda 2026 seed demo …`** (`a38c70f0`) — throwaway demo clutter; a purge is a backlog
  item.

**Config keys:** `:worker_client` (impl), `:deepinfra` (`base_url`, `api_key` from
`DEEPINFRA_API_KEY`, `req_options`), `:public_figures` (the F54 allowlist). Tests use
`Req.Test` + `api_key: "test-key"`.

**Migrations:** `mix ash.codegen <name>` — **never** hand-write one. If regenerating an unshipped
migration, delete the file **and** its `priv/resource_snapshots/repo/<table>/` snapshots, drop both
DBs, then `mix ash.setup`. Migrate dev **and** `MIX_ENV=test`. Finish with
`mix ash.codegen --check; echo $?` — and read the exit code, not just the tail of the output.

---

## Tooling & environment protocol — this trips people up

**⚠ `DEEPINFRA_API_KEY` is live in the operator's shell.** `mix run priv/scripts/read_path.exs`
**spends real money** (pennies, and the pilot sanctions it — but it is not a dry run). The last
session discovered this by expecting preflight to refuse and watching a live run go through
instead. Treat any `mix run` touching the worker as live, and say so before you run it.

**The docs are an outl workspace with a live desktop app.**
- `docs/pages/*.md` are outl outlines: **one physical line per bullet** (never hard-wrap),
  two-space indent, `key:: value` props at the top then a blank line, `[[slug]]` links. **Prose**
  (headings, tables, code — like THIS file) lives at **`docs/` root only**; outl bulletizes
  anything under `docs/pages/`. A root prose doc gets no `.outl` sidecar.
- Lint a page: `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )' docs/pages/<p>.md` → no output; every
  `[[slug]]` must resolve to a file. `mix precommit` runs `outl doctor`.
- **`outl-desktop` is usually RUNNING** (`pgrep -lf outl-desktop`). It adopts edits live and
  reprojects `.outl` sidecars — **NEVER start a second outl process.** Editing an existing page
  needs nothing.
- **Two sidecars are outstanding**: `docs/pages/run.outl` and
  `docs/pages/decision-2026-07-26-extract-once-per-event.outl` have not been generated yet. When
  they appear, commit them. Do not hand-write a sidecar.
- **STAGING — the landmine.** `.outl` sidecars reconcile separately from the `.md`. **Stage
  explicit paths; never `git add -A` / `commit -am`.** Run `git status --short` and
  `git diff --cached --name-only` before every commit. There is pre-existing uncommitted churn
  that is **not ours** — `docs/pages/{index,placement,ubiquitous-language}.outl`,
  `docs/journals/2026-07-25.*`, `.claude/worktrees/` — leave all of it alone.

**`CLAUDE.md` is a symlink to `AGENTS.md` — edit `AGENTS.md`.** A standing decision written to the
wrong file is silently lost.

**Skills to load on demand:** `ubiquitous-language` (before authoring any page — non-negotiable),
`ash-framework` (any resource/action/codegen work), `reactor` (pipeline changes), `prompt-craft`
(none needed here).

**`tmp/` is git-ignored** and is where the report goes — deliberately, because it names private
individuals. Never commit a generated report.

---

## Anti-goals

- **Do not build the review console / any UI.** The report is the review surface for now; the
  console is a later branch. If it feels tempting, make the report better instead.
- **Do not build a markdown answer parser.** See fork 6 — the reasoning in his answers is the
  valuable part, and it does not survive being parsed.
- **Do not re-extract.** The event holds claims, so `run_read_path` skips extract by design;
  `EXTRACT=force` would mint duplicates until the merge-judge exists.
- **Do not retro-attribute the 2026-07-27 acts.** Record the debt; do not fabricate the who.
- **Do not invent precision.** Link the coarser place when the evidence does not name the finer.
- **Do not loosen the F54 gate**, and remember a curation act *can* widen it — that is why it
  needs a who.
- **Do not add a dependency**; never `:ash_ai`, `:httpoison`, `:tesla`, `:httpc`, `Oban`.
- **Do not spend X / TwitterAPI.io credits.** Live acquisition is a later, spend-gated rung.
- **Do not put the network in the suite.**
- **Do not build one mega-commit**; do not re-introduce branches or PRs.

---

## Loose ends — a prioritized backlog, do not lose these

- ⟶ **Q2: the two Caraballedas** (above). His answer is the first attributed act.
- ⟶ **The gates have no fourth queue.** `persons_pending_review`, `places_proposed` and
  `claims_not_supported` are surfaced; a **place link below a confidence threshold** is not — the
  live run linked one at 0.5 and the receipt said nothing. The report catches it; the run receipt
  should too.
- ⟶ **The resolver reports "unresolved" forever.** A mention a human settled by hand still shows in
  `resolve.unresolved` on every later run, because that stage reports what the *resolver* could do.
  Honest per-stage, confusing per-record. Decide whether the receipt should say "settled by hand".
- ⟶ **An exact alias hit never consults ancestors**, so an ambiguous short name links at 0.9. Three
  live claims do. Consider disambiguating alias hits by ancestors the way multi-candidate matches
  already are.
- ⟶ **The merge-judge** (which two claims are one happening). Deterministic `Merge` exists; the
  judge does not. It is also what would let a run re-extract safely. Needs inference.
- ⟶ **The beat LLM-polish rung** — an explicit step over the structured `clauses`; never an LLM
  over the renderer.
- ⟶ **Support-prompt iteration** — `prompts/support.v1.txt` is un-iterated and answers in English.
- ⟶ **Make the record real** — port the rest of Caraballeda's posts from the old app. Do this
  *after* curation exists, or you will have a hundred claims and forty unanswerable questions. It
  is also what makes the merge-judge necessary.
- **Live acquisition** (TwitterAPI.io) — the only real money; behind the spend gate.
- **The OSM importer** — decided, deferred.
- **Dev DB cleanup** — the `a38c70f0` demo event.
- **Stale `status:: planned` pages** — `claim.md`, `beat.md`, `person.md` ship code but still read
  `planned`. He curates `status` in the outl app, so surface it rather than editing the prop.

---

## How Aníbal works — match this

- **Doc-first gate is constant**, but ceremony is not: he prefers **forks batched inline with a
  recommendation each** over click-through questions. Reserve a real stop-and-wait for the one
  load-bearing fork.
- **Decide the obvious and move.** When he says "judge you the rest," take the decision, state the
  reasoning in one or two sentences, and make it correctable in a word.
- **He answers in prose, with the reason attached** — and the reason is often a domain principle
  worth writing down ("that's why we have a recursive model"). Fold it into the docs.
- **Report faithfully.** A null magnitude is a data gap; say so. An unintended spend is an
  unintended spend; say so. He reads the honest read, not the pitch.
- **Lean process, high quality bar.** Move faster where the patterns are settled; slow down where
  the record's integrity is at stake.
- Write for a reader who is **lost**: he asked "in simple terms, where are we?" once already. Lead
  with the state, then the one recommended next step, then the detail.

---

## What worked this arc — do more of it

- **Scenarios-doc-first, then build.** Real examples with `[PROPOSAL]`/`[OPEN]` markers, annotated
  inline, then code.
- **Deterministic-first, LLM-last.** The resolver, the renderer, the orchestrator and the report
  needed no model at all.
- **Compose the proven parts — the seams are where the bugs are.** Orchestrating four "proven"
  layers exposed a silent beat-ordering defect that unit tests had never crossed.
- **Query the record before believing a summary.** Every honest finding this arc came from one
  more SQL query, not from re-reading code.
- **Give the human a file to answer.** One markdown report turned four vague worries into four
  numbered questions, and he answered all of them plus every claim in a single pass.
- **`advisor` at the forks and before done**, deliverable already durable.
- **Commit each concept the moment it is green — straight to `main`**, explicit paths only.
