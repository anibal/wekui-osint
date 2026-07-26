# Orchestration — scenarios for validation (the pipeline run)

**The job:** tie the built, proven capabilities — extract → resolve → verify → render — into **one
auditable pipeline run** on the seeded Caraballeda corpus. Proposed for your feedback before any
code. Markers: **[PROPOSAL]** my recommendation · **[OPEN]** your call · **[SETTLED]** decided.
Grounded in the real pilot data, source-level reads of the runtime libraries, and an adversarial
review pass whose confirmed findings are folded in.

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
- **[OPEN]** the `sagents` dependency is installed and unused — remove it from `mix.exs` now, or
  leave it until the talking-layer decision? (`langchain` earns its keep either way: its
  `ChatOpenAI` takes a full-URL `endpoint`, verified against DeepInfra's shape, and any future
  agent loop needs a model client.)
- When Reactor code lands, widen the `usage_rules` sync pattern in `mix.exs` so Reactor's shipped
  usage rules become a synced skill like the Ash ones.

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
PREFLIGHT   Worker.ready?  ·  event has ≥1 :active place  ·  posts in scope
    │            (fails → the run never opens a receipt; steps below depend on it)
    ▼
START RUN   Run receipt born :running — records the exact options asked
    ▼
EXTRACT     posts → Extract.run(event, agent, posts, opts)   [one batch on the pilot]
    │            writes Claims + Citations + Persons (born pending_review)
    │            PlaceResolver already runs inline per claim
    │            max_retries 0 — a repeat would draft duplicate claims
    ▼
RESOLVE     each current claim → PlaceResolver.resolve(claim, actor_id:, post_id:)
    │            safe-to-repeat re-pass (ClaimPlace upserts, proposals reuse); this is
    │            where the run CAPTURES the resolver counts Extract discards
    ▼
VERIFY      each current claim → Verify.run(claim)     [a `map` step; retries allowed —
    │            a repeat only overwrites the same claim's verdict]
    │            records the support verdict — flag-only, withholds nothing
    ▼
RENDER      BeatRenderer.render(place_id, from, to) → %{prose, clauses, sources}
    │            read-only; retries allowed
    ▼
FINALIZE    Run receipt → :completed — summary: per-stage counts + gate queues + the beat
```

Reactor gives the order (each step consumes the previous step's result), per-step retry limits
declared where repeating is safe, and full serial determinism (`async?: false` — also required
under test, where the task path lacks the DB sandbox). We define **no undo callbacks**: the
record is append-only by doctrine, so a failed run must never quietly unmake what earlier steps
honestly wrote.

Count scopes, stated plainly: **extract counts the batch it fed; resolve and verify are event-wide
snapshots** of the current claims at run time (labeled so in the summary) — on a second run the
receipt mixes a batch delta with snapshots, and that is the honest reading.

## Scenarios (the hard orchestration questions)

### A. A clean run — what the receipt says
The pilot ask (Caraballeda × first days) on the **fresh task-0 event** finalizes with a summary
like this (illustrative; person/verdict counts ride the known MoE variance):

```json
{
  "extract": {"posts": 9, "claims": 9, "drafted": 9, "skipped": 0, "skips": []},
  "resolve": {"claims": 9, "mentions": 9, "linked": 8, "proposed": 0, "unresolved": ["cerca de Caraballeda-La Guaira"]},
  "verify":  {"claims": 9, "supported": 9, "overstated": 0, "unsupported": 0, "errors": 0},
  "render":  {"clauses": 6, "sources": 7},
  "gates":   {"persons_pending_review": 5, "places_proposed": 0, "claims_not_supported": 0},
  "beat":    {"prose": "En Edificio OPP 25, …", "sources": ["…"]}
}
```

Note what the fresh event does *not* demonstrate: the deliberately-overstated control claim is a
manual insert on the old pilot (stored verdict `:unsupported` — the kickstart calls it
"overstated" loosely) and posts-only porting does not re-create it, so `claims_not_supported` is
honestly 0 here. Verify's catch was already live-proven. **[OPEN]** re-create the control on the
fresh event in task 0a, or let that path stay proven-but-undemonstrated?

**[PROPOSAL]** the summary embeds the rendered beat (prose + sources) as a *receipt of output* —
the beat stays derived and re-derivable from the claims; the run's copy is provenance, never the
canonical story. **[OPEN]** or counts only, and the beat is always re-rendered on demand?

### B. Preflight fails — no key, no gazetteer
`Worker.ready?` false (no `DEEPINFRA_API_KEY`), or the event has no `:active` place (the
forgot-to-seed guard — stub-vs-real cannot be told apart from the data and is task 0's
responsibility, not preflight's). **[PROPOSAL]** the preflight step fails the run before the
receipt step ever runs: the caller gets `{:error, {:preflight, reason}}` and **no** receipt
exists — a run that never ran is not a record of the system acting. The seed is not auto-run:
seeding is an explicit, separate act (already idempotent), not a side effect of asking for a
beat. Noted caveat for later rungs: once something other than you invokes the pipeline, a refused
preflight leaves no receipt — the caller's own record is then the only trace of the attempt.

### C. A crash mid-run — the `:running` crash artifact
Extract raises after drafting 4 of 9 claims (its writes are best-effort, not transactional — a
known reality). The Reactor unwinds — and because no step defines undo, unwinding just stops the
run; nothing is unmade. The receipt stays `:running` forever. **[PROPOSAL]** keep the two-state
receipt (kickstart-runs' shape): a `:running` row found later IS the crash signal; no `:failed`
state, no state machine. Stage errors the steps *can* catch (`{:error, …}` tuples from
Extract/Verify/Worker) are carried in step results as data and recorded in the summary — the run
still finalizes `:completed`, and a completed run with errors in its summary is an honest
receipt. Only a raise leaves `:running`.

### D. Re-running — the one duplicate hazard
`Claim.:draft` has no identity: re-extracting the same posts mints duplicate claims (everything
else on the path is safe to repeat — resolve upserts, verify overwrites its verdict, seed
reuses). Until the merge-judge lands, the orchestrator must not blindly re-extract. **[PROPOSAL]**
an all-or-nothing scope rule, one citations query: **no** post in scope cited by a current claim →
extract runs; **every** post cited → skip extract (a pure re-pass run: resolve + verify + render);
**partially** cited → the extract step refuses, recorded as an error in the summary, unless
`extract: :force`. Partial coverage is precisely the dangerous state (a crashed extract, a
retracted claim's posts falling back out of citation) and should be loud, not silently patched;
recovery is manual — retract the partials, then force — until the merge-judge lands. Per-post
skipping was considered and rejected: it re-feeds no-claim posts on every run (a
non-deterministic-model ratchet toward minting claims from noise v5 correctly dropped), it turns
`{{material}}` into partial batches the v5 prompt was never proven on, and it resurrects
deliberately retracted accounts. This is also why the extract step declares `max_retries 0`.

### E. The gates — record, not pause
The run finalizes with `persons_pending_review`, `places_proposed`, `claims_not_supported` queues
(counts + ids) in its summary. Nothing blocks; the review UI (deferred) will service the same
statuses off the resources themselves — the run's queues are a snapshot for the operator's
inspection, not the source of truth. Re-verification is a snapshot too: the MoE judge can flip a
verdict between runs, so an old receipt may honestly disagree with current claim state.
**[PROPOSAL]** a `verify: :skip_verdicted` option for cost/churn control; default re-verifies all
current claims. The one *blocking* gate remains future spend, designed with the acquisition rung.

### F. Post selection — what the extract stage feeds the model
**[PROPOSAL]** posts of the event whose `posted_at` falls in `[from, to]`, in one batch at pilot
scale (9 posts); windowed batching is a later rung when the corpus grows. An explicit `posts:`
override exists for scripted runs. (The beat's own interval then filters on claim
`first_seen_at` — consistent, since a claim's `first_seen_at` is its first-listed citation's
`posted_at`.) **[OPEN]** should the window filter on `posted_at` at all, or should a pilot run
always feed the event's whole corpus and let the beat's own interval do the scoping?

## The Run receipt (draft shape — Ash, per fork 2/5)

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
display receipt. `Wekui.Pipelines` becomes the Ash domain holding Run (fork 5), added to
`ash_domains` in config; the `ReadPath` Reactor and its step modules are plain infra beside the
existing `Wekui.Pipelines.Extract`/`Verify`.

## Proposed vocabulary — the `run` concept page (draft, pending fork 2)

To be created as `docs/pages/run.md` (status `planned`) + its hub line, **only if fork 2 lands on
"vocabulary"**:

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

## Task 0 — the clean pilot event (blocks everything above)

Confirmed in the dev DB: pilot `eb8ec55b` has the 9 real posts + 10 claims (9 real + the control)
on a 6-place stub tree; demo `a38c70f0` has the 297-place real tree with junk claims
(`kind: "x"`). No event holds both.

**[PROPOSAL] Path (ii), split in two:**
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
destroy action by design. **[OPEN]** the fresh event's name (reuse `litoral-central-2026` and
retire the old event as backlog cleanup, or a distinct name?).

## The forks — one settled, the rest batched with a recommendation each

1. **How much runtime, now — [SETTLED 2026-07-26]: the pipeline is a Reactor.** The kickstart's
   fork (a) rested on the saga misread and dissolved with it; the corrected choice was
   hand-written module vs Reactor, and Reactor won: already installed, made for fixed step
   graphs, declared retries, step events for the receipt, serial mode for determinism. Recorded
   in [`decision-2026-07-26-reactor-not-sagents`](pages/decision-2026-07-26-reactor-not-sagents.md).
   The talking-agent layer's runtime is a *later* decision, made at that rung.
2. **Run — vocabulary or machinery? Recommend vocabulary** (a `run` concept page, draft above).
   It is operator-facing persisted state with a lifecycle, and under the agent-as-product pivot
   the run receipt is the product's audit surface — the thing you inspect. The op-log precedent
   (machinery) fit a projection artifact; a run is a first-class thing you list, open, and reason
   about. kickstart-runs deferred this fork and the concept resurfaced on its own — evidence it's
   vocabulary.
3. **Gate points — recommend record now, pause later** (scenario E). Pausing arrives with the
   review UI (content gates) and with acquisition (the spend gate).
4. **Model call path — recommend: the pipeline keeps the Worker behaviour** (settled,
   `Req.Test`-proven, `retry: false` caller-owned — with retry limits now declared per Reactor
   step where repeating is safe). The future talking layer's model path is decided with its
   runtime; `langchain`'s DeepInfra-compatible `ChatOpenAI` is the noted candidate there.
5. **Domain placement — recommend `Wekui.Pipelines` as the new Ash domain** holding `Run`, with
   the `ReadPath` Reactor and step modules as plain infra beside the existing
   `Wekui.Pipelines.Extract`/`Verify` (no `lib/wekui/pipelines.ex` exists today; Extract/Verify
   are plain modules, so no collision — the namespace already says pipeline; one home for stages,
   orchestrator, and receipt). Alternative: `Wekui.Runs`.
6. **Scope of the first run — recommend read-path only** (extract → resolve → verify → render on
   the seeded corpus). The beat LLM-polish stays the next rung, as an explicit separate step over
   the structured `clauses` — never an LLM over the renderer.
