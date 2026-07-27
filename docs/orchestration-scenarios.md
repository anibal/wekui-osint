# Orchestration — scenarios for validation (the pipeline run)

**The job:** tie the built, proven capabilities — extract → resolve → verify → render — into **one
auditable pipeline run** on the seeded Caraballeda corpus. Markers: **[PROPOSAL]** my
recommendation · **[OPEN]** your call · **[SETTLED]** decided. Grounded in the real pilot data,
source-level reads of the runtime libraries, and an adversarial review pass whose confirmed
findings are folded in.

> **STATUS 2026-07-26 — BUILT AND RUN LIVE.** Every fork below is settled, the read path ships,
> and task 0b ran on the real model (scenario A holds the receipt).
>
> **On that live run:** I meant to smoke-test the 0b script *without* a key and watch preflight
> refuse — but `DEEPINFRA_API_KEY` is set in this shell's environment, so the run went through for
> real. Pennies, on the seeded corpus, within what the pilot sanctions; unintended all the same,
> and said plainly here rather than presented as planned.
>
> The parts: `Wekui.Pipelines.Run` (the receipt), `Wekui.Pipelines.ReadPath` (the Reactor) and
> `Wekui.Pipelines.run_read_path/4`, with 14 tests through `Req.Test`, plus `priv/scripts/` for
> task 0a (296 places seeded, 9 posts ported, re-runnable) and 0b. Where the built behaviour
> departs from what was proposed, the section says so and why; the departures are scenario D's
> re-run rule (the proposed one mis-fired on the happy path — see
> [`decision-2026-07-26-extract-once-per-event`](pages/decision-2026-07-26-extract-once-per-event.md))
> and the per-step retries (dropped: a stage records its errors instead).

## The runtime — [SETTLED 2026-07-26]: Reactor

**The pipeline orchestrator is [Reactor](https://github.com/ash-project/reactor)** — see
[`decision-2026-07-26-reactor-not-sagents`](pages/decision-2026-07-26-reactor-not-sagents.md).
Reactor 1.0.2 is **already installed** (Ash itself requires it; its helper processes already run in
this app), so this adds **zero dependencies**. You declare steps; each step names what it needs
(an input or another step's result); Reactor derives the order. Run with `async?: false` it
executes one step at a time, fully predictable. Its step events (start, finish, error, retry) are
where a Run receipt gets stamped. Steps are plain functions calling our existing code interfaces —
the documented, idiomatic pattern; the `Ash.Reactor` DSL extension is **not** used (its
`transaction` step misbehaves on SQLite: silently non-transactional, misleading error on failure).

**Clarification note — the sagents mistake, so it stays behind us.** The kickstart framed the
runtime as "Sage (sagents): saga/agent orchestration (steps, compensation, pause/resume)". A
source read of `deps/sagents` 0.9.0 showed that premise was wrong: sagents is not a saga engine
and has no step graph, no compensation, no rollback — it is "Sage *Agents*", an LLM-agent loop on
Elixir LangChain where the model decides what to call next, and its pause/resume approves tool
calls. It cannot run a fixed four-stage pipeline without putting a model over a sequence that has
no decisions in it. Reactor is the thing the kickstart was actually describing. Consequences:
- The **talking-agent layer** (a later rung: conversational driving, merge-judge as a tool, the
  spend gate) no longer has a settled runtime. sagents + LangChain remains *a* candidate there —
  decide when that rung arrives, not before. `docs/agent-architecture.md` and
  `docs/kickstart-agent.md` carry correction banners so their sagents framing reads as history.
- **[SETTLED — operator: remove]** `sagents` is gone from `mix.exs`; nothing in `lib/`, `test/` or
  `config/` referenced it. `langchain` stays: its `ChatOpenAI` takes a full-URL `endpoint`,
  verified against DeepInfra's shape, and any future agent loop needs a model client.
- **[SETTLED]** Reactor's usage rules are now a synced skill (`.claude/skills/reactor`). That
  needed `{:reactor, "~> 1.0"}` declared in `mix.exs`: `usage_rules` only discovers **top-level**
  deps, so a transitive one is silently skipped. No new package enters the build — `mix.lock` is
  untouched, Ash already required reactor 1.0.2 — and the read path `use`s Reactor directly, so
  declaring it also stops being a latent break if Ash ever drops it.

## First principles (inherited, made concrete)

1. **The read path has no agentic decisions.** Extract, resolve, verify, render run in a fixed
   order on a fixed scope. Deterministic orchestration; an LLM appears only *inside* two stages
   (extraction, support) through the settled Worker client.
2. **A run is a receipt, not an answer.** It records *that the system acted* — options in, summary
   out. The facts live in the claims; the receipt is auditable provenance (kickstart-runs' framing,
   now needed for real).
3. **HITL is a status, not a blocker.** The pipeline already sets the gates (Person
   `pending_review`, Claim `support` verdict, Place `:proposed`); the run *surfaces* them as
   queues in its summary. Nothing pauses in this iteration — "not a cop, not a blocker."
4. **No spend.** The pilot runs on the seeded corpus; inference is pennies and goes through the
   existing Worker client. What is settled about the future spend gate is only its principle —
   any step that spends money pauses for human approval; its mechanism is chosen with the
   acquisition rung, not before.
5. **The dignity gate is untouched.** The orchestrator adds no new write paths — every write goes
   through the same Ash actions with `NoPrivateName` and the `:active`-gazetteer vocabulary.

## The run on the real pilot — the Reactor's steps

`Wekui.Pipelines.ReadPath` (a Reactor, run serial), wrapped by
`Wekui.Pipelines.run_read_path(event, agent, %{place_id:, from:, to:}, opts)` — `agent` is the
extraction Actor, passed explicitly and recorded in `options` (Actors are content-addressed and
immutable; a prompt revision mints a *second* agent on the event, so "the event's agent" is
ambiguous — the ask must name it).

```
inputs      event · agent · place_id · from · to · opts
    ▼
PREFLIGHT   Worker.ready?  ·  place belongs to the event  ·  event has a gazetteer
    │            ·  posts in scope
    │            (fails → the run never opens a receipt; steps below depend on it)
    ▼
START RUN   Run receipt born :running — records the exact options asked
    ▼
EXTRACT     posts → Extract.run(event, agent, posts, opts)   [one batch on the pilot]
    │            writes Claims + Citations + Persons (born pending_review)
    │            PlaceResolver already runs inline per claim
    │            skipped outright when the event already holds claims (scenario D)
    ▼
RESOLVE     each current claim → PlaceResolver.resolve(claim, actor_id:, post_id:)
    │            safe-to-repeat re-pass (ClaimPlace upserts, proposals reuse); this is
    │            where the run CAPTURES the resolver counts Extract discards
    ▼
VERIFY      each current claim → Verify.run(claim)
    │            records the support verdict — flag-only, withholds nothing
    ▼
RENDER      BeatRenderer.render(place_id, from, to) → %{prose, clauses, sources}
    │            read-only
    ▼
FINALIZE    Run receipt → :completed — summary: per-stage counts + gate queues + the beat
```

Reactor gives the order (each step consumes an earlier step's result, or declares `wait_for`) and
full serial determinism (`async?: false`, set once by the wrapper — also required under test,
where the task path lacks the DB sandbox). We define **no undo callbacks**: the record is
append-only by doctrine, so a failed run must never quietly unmake what earlier steps honestly
wrote.

**Departure from the proposal: no retries anywhere** (`max_retries 0` on every step). Reactor only
retries a step whose `compensate/4` returns `:retry`, so declaring retry limits without writing
compensate callbacks would have been a claim the code did not keep. And a stage that *records* its
error in the summary is strictly more honest than one that silently repeats the call — the receipt
says what went wrong. Two preflight checks were added while building: the target place must belong
to the event, and the event's **Unplaced Place does not count** as a gazetteer (every event is born
with one, active, which would have made the gazetteer guard always pass).

Count scopes, stated plainly: **extract counts the batch it fed; resolve and verify are event-wide
snapshots** of the current claims at run time (labeled so in the summary) — on a second run the
receipt mixes a batch delta with snapshots, and that is the honest reading.

## Scenarios (the hard orchestration questions)

### A. A clean run — what the receipt says
The pilot ask (Caraballeda × the corpus span) on the **fresh task-0 event** finalizes with a
summary of this shape — and **it did, live, on 2026-07-26**: receipt `7bb0dcc3`, 23 seconds, one
extraction call and 8 support calls, all through the real model. The real numbers are below the
example, which is kept as the annotated shape:

```json
{
  "extract": {"ran": true, "posts": 9, "claims": 9, "drafted": 9, "skipped": 0, "skips": []},
  "resolve": {"claims": 9, "mentions": 9, "linked": 8, "proposed": 0, "unresolved": ["cerca de Caraballeda-La Guaira"]},
  "verify":  {"claims": 9, "judged": 9, "skipped": 0, "supported": 9, "overstated": 0, "unsupported": 0, "unverified": 0, "errors": 0, "error_reasons": []},
  "render":  {"place_id": "…", "place_name": "Caraballeda", "clauses": 6, "sources": 7},
  "gates":   {"persons_pending_review": {"count": 5, "ids": ["…"]}, "places_proposed": {"count": 0, "ids": []}, "claims_not_supported": {"count": 0, "ids": []}},
  "beat":    {"prose": "En Edificio OPP 25, …", "sources": [{"n": 1, "x_id": "3923", "post_id": "…"}]}
}
```

(That is the shape the code writes — string keys, scalars and lists only, so the receipt reads
back from its `:map` column exactly as written. The `options` alongside it record the ask:
`place_id`, `place_name`, `from`, `to`, `agent_id`, `agent_model`, `posts_in_scope`, and the
per-stage choices.)

**The actual first run** (task 0b, `litoral-central-2026`, the real 296-node tree):

```
extract  9 posts → 8 claims drafted, 0 skipped
resolve  8 claims, 8 mentions, 7 linked, 0 proposed, 1 unresolved: "Caraballeda-La Guaira"
verify   8 judged → 8 supported, 0 overstated, 0 unsupported, 0 errors
render   5 clauses, 6 sources   (8 claims − 2 at La Guaira level, above Caraballeda in the tree
         − 1 unresolved = 5: scope holds by construction, and the arithmetic closes)
gates    5 persons pending review · 0 places proposed · 0 claims flagged
beat     En Conjunto Residencial Caribe, se buscaba a Yaneth T. y Shaznay M.[1]; se buscaba a
         Damarys M., una maestra[2]; el edificio colapsó tras el terremoto[3]. En Caraballeda,
         los equipos rescataron con vida a una mujer[4]. En Edificio OPP 25, los equipos
         trabajaron para rescatar con vida a Aaron C., un hombre de 21 años[5][6].
```

Read honestly, because the receipt lets us:

- **8 claims where the old stub-tree pilot got 9.** The receipt says `"skipped": 0, "skips": []`,
  so nothing was refused by the F54 gate and nothing was dropped for bad citations — the model
  simply produced eight. That is single-pass MoE variance measured, not asserted; the gates and
  your review are the backstop, and the wiring is not the suspect.
- **The one unresolved mention has no ClaimPlace row at all**, so that claim ("un hombre",
  `Caraballeda-La Guaira`) is invisible to *every* beat, not merely to this one. Honest, and a
  reminder that UNRESOLVED is a silence, not a flag a reader ever sees.
- **Three of eight claims hang on one gazetteer alias, at a confidence that overstates it.** All
  three "Residencias Caribe" claims — two searches for named people and the collapse — resolved
  `mention_exact` at **0.9** to `Conjunto Residencial Caribe`, because the seeded gazetteer
  carries "Residencias Caribe" as a curated `spelling_variant` of it. The tree also holds a
  *distinct* building called `Residencias Caribe, Torre C` under the same barrio. So the mention
  is genuinely ambiguous in the world while the resolver reports near-certainty: an exact hit on
  an alias wins outright and never consults the ancestors. The link is defensible — a human put
  that alias there — but the **0.9 is not**, and three claims in a memorial beat rest on it. This
  is the "different Caribe building via an alias" item the backlog predicted, now concrete: a
  curation call for review, not a code fix.
- **The gates do not surface a low-confidence link.** The same run linked "Caraballeda" at
  **0.5** (the parroquia-vs-populated_place tie the resolver breaks arbitrarily) and said nothing
  about it in the receipt. `persons_pending_review`, `places_proposed` and `claims_not_supported`
  are the three queues; a fourth — *place links below a confidence threshold* — is missing, and
  is the cheapest addition the review console will want.
- Every person is a derived handle, none a raw name. And the beat now reads in time order across
  a month boundary — which it did not before this session (scenario C-bis).

Note what the fresh event does *not* demonstrate: the deliberately-overstated control claim is a
manual insert on the old pilot (stored verdict `:unsupported` — the kickstart calls it
"overstated" loosely) and posts-only porting does not re-create it, so `claims_not_supported` is
honestly 0 here. Verify's catch was already live-proven.

**[SETTLED — my call, per your "you take the decision"]: no control claim on the fresh event.**
Planting a knowingly false record in a corpus that is append-only, has no destroy action, and
exists to be a memorial is the wrong price for a demonstration. The path is instead proven where
proof belongs — in the suite: a test drives an `unsupported` verdict end to end and asserts it
reaches *both* the `claims_not_supported` gate queue and the beat's "según un reporte sin
confirmar" attribution. That is deterministic and repeats on every run, which a one-off manual
insert never was.

**[SETTLED — the summary embeds the beat, and nothing is final]:** the receipt keeps the rendered
prose + sources as a *receipt of output*, and the beat stays derived and re-derivable from the
claims — a test asserts a fresh `BeatRenderer.render/3` reproduces exactly what the receipt kept.
Your read is the operative one: there are no final products, so the run's copy is provenance and a
re-render is always available; the claims remain the substance.

### B. Preflight fails — no key, no gazetteer
`Worker.ready?` false (no `DEEPINFRA_API_KEY`), or the event has no `:active` place (the
forgot-to-seed guard — stub-vs-real cannot be told apart from the data and is task 0's
responsibility, not preflight's). **[SETTLED]** the preflight step fails the run before the
receipt step ever runs: the caller gets `{:error, {:preflight, reason}}` and **no** receipt
exists — a run that never ran is not a record of the system acting. The seed is not auto-run:
seeding is an explicit, separate act (already idempotent), not a side effect of asking for a
beat. Noted caveat for later rungs: once something other than you invokes the pipeline, a refused
preflight leaves no receipt — the caller's own record is then the only trace of the attempt.

### C. A crash mid-run — the `:running` crash artifact
Extract raises after drafting 4 of 9 claims (its writes are best-effort, not transactional — a
known reality). The Reactor unwinds — and because no step defines undo, unwinding just stops the
run; nothing is unmade. The receipt stays `:running` forever. **[SETTLED]** keep the two-state
receipt (kickstart-runs' shape): a `:running` row found later IS the crash signal; no `:failed`
state, no state machine. Stage errors the steps *can* catch (`{:error, …}` tuples from
Extract/Verify/Worker) are carried in step results as data and recorded in the summary — the run
still finalizes `:completed`, and a completed run with errors in its summary is an honest
receipt. Only a raise leaves `:running`.

One mechanical detail the build pinned down: **Reactor rescues a raising step**, so the raise does
not propagate to the caller — `run_read_path/4` returns `{:error, exception}` (unwrapped from
Reactor's error classes) and the receipt is left `:running`. Both halves are tested: the claims an
earlier stage wrote survive, and the stranded receipt is there to be found.

### C-bis. What a defect looked like — the beat read out of order
Wiring the run surfaced a real bug in code that was already "proven": `BeatRenderer` sorted its
place groups with `Enum.sort_by` over `DateTime` structs and no sorter, so Erlang's term ordering
compared the maps key by key — `day` before `month` before `year`. The pilot's July 1 official toll
therefore sorted *ahead* of the June 29 rescue it follows, silently. Fixed (name `DateTime` as the
sorter, as the within-group sort already did) with a regression test that crosses a month
boundary. Worth recording as the argument for orchestration itself: composing proven parts is what
exposed the seam between them.

### D. Re-running — the one duplicate hazard
`Claim.:draft` has no identity: re-extracting the same posts mints duplicate claims (everything
else on the path is safe to repeat — resolve upserts, verify overwrites its verdict, seed
reuses). Until the merge-judge lands, the orchestrator must not blindly re-extract.

**The proposed rule was wrong, and the pilot said so.** The proposal keyed on citation coverage:
no post in scope cited → extract; every post cited → skip; **partially** cited → refuse loudly.
Counting the pilot before building found **8 of its 9 posts cited** — v5 correctly drops a post
that evidences no happening, and a dropped post is cited by nothing. So "partially cited" is the
*happy path*, and the loud refusal would have fired on every honest re-run.

**[SETTLED]** the rule is binary: an event with **no current claim** extracts; an event that
**already holds one** skips extract and re-passes resolve + verify + render, unless asked with
`extract: :force`. The skip is stated in the receipt (`"ran": false, "reason": "claims_exist"`),
so it is loud where loudness belongs — in the record, not as a refusal. A crash that drafted part
of a batch is therefore never silently patched; recovery stays deliberate: retract the partials,
then force. Recorded as
[`decision-2026-07-26-extract-once-per-event`](pages/decision-2026-07-26-extract-once-per-event.md).

Per-post skipping was considered and rejected for the reasons that still hold: it re-feeds
no-claim posts on every run (a non-deterministic-model ratchet toward minting claims from noise v5
correctly dropped), it turns `{{material}}` into partial batches the v5 prompt was never proven
on, and it resurrects deliberately retracted accounts.

### E. The gates — record, not pause
The run finalizes with `persons_pending_review`, `places_proposed`, `claims_not_supported` queues
(counts + ids) in its summary. Nothing blocks; the review UI (deferred) will service the same
statuses off the resources themselves — the run's queues are a snapshot for the operator's
inspection, not the source of truth. Re-verification is a snapshot too: the MoE judge can flip a
verdict between runs, so an old receipt may honestly disagree with current claim state.
**[SETTLED]** a `verify: :skip_verdicted` option for cost/churn control; default re-verifies all
current claims. The one *blocking* gate remains future spend, designed with the acquisition rung.
The verdict tally in the summary is taken over *all* current claims after the pass — the state as
it now stands — while `judged` and `skipped` say what this particular run did.

### F. Post selection — what the extract stage feeds the model
**[SETTLED — my call]: the extract stage feeds the event's whole corpus; `from`/`to` scope the
beat only.** A `posted_at` window on extraction would mean a claim is never *drafted* because it
fell outside a render window — the read window would silently decide what the record contains,
which is backwards: extraction is what the record knows, the beat is one reading of it. Feeding
the whole corpus also makes scenario D's re-run rule crisp (one fixed scope, not a moving one) and
costs nothing at pilot scale — 9 posts, one batch. Windowed batching arrives when the corpus
outgrows one prompt, as its own rung. The `posts:` override remains for scripted runs, and the
prompt's `{{t_start}}`/`{{t_end}}` are filled from the corpus's own span (half-open, so the last
post falls inside).

## The Run receipt (shipped as drafted — Ash, per fork 2/5)

```
Wekui.Pipelines.Run  (table "runs")
  uuid_primary_key :id
  kind        :atom, one_of [:read_path]        # widened as rungs land (:polish, :acquisition…)
  status      :atom, one_of [:running, :completed]
  options     :map                              # the exact ask (place_id, from, to, agent id, stage opts)
  summary     :map                              # per-stage counts + gates + beat (scenario A)
  finished_at :utc_datetime_usec                # started_at is inserted_at — no duplicate column
  belongs_to :event (required) · belongs_to :actor (required — the EXECUTING agent, the same
    Actor whose prompt extraction uses; always exists after task 0a)

  create :start     — born :running, stamps options
  update :finalize  — sets summary, finished_at, status :completed
```

Two states, no `AshStateMachine`, no identities/partial indexes needed (nothing is
one-current-per-slot). All single-row writes — the ash_sqlite no-transactions reality doesn't
bite. `options`' DateTimes round-trip out of the `:map` column as ISO strings — fine for a
display receipt. `Wekui.Pipelines` is the Ash domain holding Run (fork 5), added to `ash_domains`
in config; the `ReadPath` Reactor and its steps are plain infra beside the existing
`Wekui.Pipelines.Extract`/`Verify`. One thing the build made stricter: **the whole summary is
string-keyed JSON scalars**, never structs or atoms — `BeatRenderer.render/3` returns a full
`Place` struct, which a `:map` column cannot hold, so the render step projects the fields it keeps
and a test asserts the summary reads back from the database byte-identical.

## The `run` concept page — [SETTLED: vocabulary; shipped]

Created as [`docs/pages/run.md`](pages/run.md) (`status:: built`) with its
[[ubiquitous-language]] hub line, in the same commit as the resource. The draft below is what it
says:

> - A **run** is the receipt of one execution of the system's own pipeline over an [[event]]:
>   which stages ran (extract, resolve, verify, render), over what scope, what each produced, and
>   which gates it left open. It records *that the system acted*, never a fact about the world —
>   the facts live in the [[claim]]s and their evidence.
> - A run is born **running** and **finalized** with a summary; a run still marked running long
>   after its start is a crash artifact, not a live process. Two states, deliberately.
> - A run carries the [[actor]] that performed it — the executing agent — the exact **options**
>   it was asked with, and a **summary** of what happened per stage — counts, verdicts, the
>   unresolved leftovers, and the gate queues it surfaced ([[person]]s pending review, proposed
>   [[place]]s, [[claim]]s the support gate flagged).
> - A run *surfaces* the human gates; it never blocks on them — gates are statuses on the things
>   themselves, serviced by review later. "Not a cop, not a blocker" at the orchestration layer.
> - A run may record the [[beat]] its render stage produced, as a receipt of output; the beat
>   stays derived and re-derivable from the claims — the run's copy is provenance, never the
>   canonical story.

## Task 0 — the clean pilot event ([SETTLED; 0a DONE, 0b awaiting the key])

Confirmed in the dev DB: pilot `eb8ec55b` has the 9 real posts + 10 claims (9 real + the control)
on a 6-place stub tree; demo `a38c70f0` has the 297-place real tree with junk claims
(`kind: "x"`). No event held both.

**Path (ii), split in two — 0a ran in dev on 2026-07-26** (`priv/scripts/pilot_event.exs`: 296
places seeded, 1 author + 9 posts ported, second run a no-op):
- **0a — deterministic setup (no key needed):** a small committed script creates a fresh event,
  seeds the real 296-node gazetteer (`Gazetteer.Seed.caraballeda/1`, born `:active`), registers
  the extraction agent (Actor with the `prompts/extraction.v5.txt` text + DeepSeek model — Extract
  reads the prompt from `Actor.prompt`, not the file), then ports the pilot's **author first**
  (`Post.:collect` requires a same-event `author_id`) and the 9 posts with their original
  payloads through `Capture` (immutable upserts; Post identity is `(event_id, x_id)`, so the same
  `x_id` on a new event is a fresh row).
- **0b — the live re-extract IS the pipeline's first real run.** Once the Run receipt + the
  `ReadPath` Reactor are green on `Req.Test`, you run one command with `DEEPINFRA_API_KEY` in the
  real env; extraction re-proves on the *real* tree and the whole session's deliverable lands in
  one auditable receipt. Pennies; N-run variance is the known MoE reality — the gates + your
  review are the backstop.

Path (i) (re-seed onto `eb8ec55b`) stays rejected: `Seed` keys idempotency on
`{folded name, type, parent}`, so the stub `Tanaguarena (sector)` ≠ real `barrio` and
`OPP 25` ≠ `Edificio OPP 25` → duplicate nodes + wrong ClaimPlace links, and `Place` has no
destroy action by design.

**[SETTLED — my call]: the canonical name goes to the canonical event.** The fresh event is
`litoral-central-2026`; the stub was renamed `litoral-central-2026-stub` and keeps its 9 posts and
10 claims intact as the source to port from and as the history of how the spine was proven. Two
events named for one earthquake would have been the worse outcome — the name describes the
happening, and it belongs to the event that holds the real gazetteer. The script does the rename
itself, once, on a rule it can explain: an event under the target name carrying posts but no
seeded gazetteer *is* the stub.

## The forks — all six settled

1. **How much runtime, now — [SETTLED 2026-07-26]: the pipeline is a Reactor.** The kickstart's
   fork (a) rested on the saga misread and dissolved with it; the corrected choice was
   hand-written module vs Reactor, and Reactor won: already installed, made for fixed step
   graphs, step ordering derived from declared needs, serial mode for determinism. Recorded
   in [`decision-2026-07-26-reactor-not-sagents`](pages/decision-2026-07-26-reactor-not-sagents.md).
   The talking-agent layer's runtime is a *later* decision, made at that rung.
2. **Run — vocabulary or machinery? [SETTLED: vocabulary]** — [`run`](pages/run.md) is a concept
   page, shipped with the resource. It is operator-facing persisted state with a lifecycle, and
   under the agent-as-product pivot the run receipt is the product's audit surface — the thing you
   inspect. The op-log precedent (machinery) fit a projection artifact; a run is a first-class
   thing you list, open, and reason about. kickstart-runs deferred this fork and the concept
   resurfaced on its own — evidence it's vocabulary.
3. **Gate points — [SETTLED: record now, pause later]** (scenario E). Pausing arrives with the
   review UI (content gates) and with acquisition (the spend gate).
4. **Model call path — [SETTLED: the pipeline keeps the Worker behaviour]** (`Req.Test`-proven,
   `retry: false` caller-owned — and the orchestrator adds no retries of its own; see the step
   graph). The future talking layer's model path is decided with its runtime; `langchain`'s
   DeepInfra-compatible `ChatOpenAI` is the noted candidate there.
5. **Domain placement — [SETTLED: `Wekui.Pipelines`]**, the Ash domain holding `Run` and the
   `run_read_path/4` entry point, with the `ReadPath` Reactor and its steps as plain infra beside
   the existing `Wekui.Pipelines.Extract`/`Verify` — one home for stages, orchestrator and
   receipt. (`Wekui.Runs` was the alternative; the namespace already said pipeline.)
6. **Scope of the first run — [SETTLED: read-path only]** (extract → resolve → verify → render on
   the seeded corpus). The beat LLM-polish stays the next rung, as an explicit separate step over
   the structured `clauses` — never an LLM over the renderer.

## What is left

- **Task 0b is done** (see scenario A). To run it again: `mix run priv/scripts/read_path.exs` —
  which now *skips* extract, since the event holds claims, and re-passes resolve + verify +
  render. `EXTRACT=force` re-extracts and would mint a second set until the merge-judge lands.
- **Your review of the 8 live claims** is the real next step: 5 persons sit `pending_review`, and
  a second pass would likely surface a different claim count (single-pass MoE variance).
- **Two findings from that run that belong to the backlog, not to this layer:** the
  `Residencias Caribe` alias resolving three claims at an overstated 0.9 (a gazetteer curation
  call — the ambiguity is real, the confidence is not), and the missing **fourth gate queue** for
  place links below a confidence threshold (the run linked one at 0.5 and said nothing).
- Next rungs, unchanged and unstarted: the **beat LLM-polish** over the structured clauses, the
  **merge-judge** (which two claims are one happening — and the thing that would let a re-run
  extract safely), the **support-prompt iteration** (v1 answers in English), the **review UI**
  that services the gate queues, and **live acquisition** behind the spend gate.
