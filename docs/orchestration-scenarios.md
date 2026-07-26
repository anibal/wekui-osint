# Orchestration — scenarios for validation (the pipeline run)

**The job:** tie the built, proven capabilities — extract → resolve → verify → render — into **one
auditable pipeline run** on the seeded Caraballeda corpus, and stand up the Sagents + LangChain
foundation for the agentic layer above it. Proposed for your feedback before any code. Markers:
**[PROPOSAL]** my recommendation · **[OPEN]** your call. Grounded in the real pilot data, a
source-level read of both runtime deps, and an adversarial review pass whose confirmed findings
are already folded in.

## The runtime, corrected — read this first

The settled decision (Sagents + LangChain, not ash_ai) **stands** — but the premise behind fork 1's
option (a) does not. A source read of `deps/sagents` (0.9.0) shows **`sagents` is not a saga
library**: no steps-with-compensation, no deterministic step graph, no rollback. The name is "Sage
*Agents*" — it is an **LLM-agent orchestration framework** on top of Elixir LangChain (same author),
where **the model is the sequencing authority**: an agent = a LangChain ChatModel + tools +
middleware (HumanInTheLoop, AskUserQuestion, Haltable, SubAgent), run in a loop until done or
`until_tool`. Its genuinely excellent pause/resume is **tool-call approval** — an interrupt raised
*before a gated tool executes*, restorable across restarts — which is exactly the shape of the
future **spend gate**, and not the shape of a fixed four-stage pipeline.

Consequence: running the deterministic read path *under* Sagents cannot be done without either
putting an LLM over a sequence that has no decisions in it, or writing a custom execution Mode that
abandons everything Sagents provides (middleware, state propagation, interrupts are all keyed off
the message loop). Either way the doctrine is violated for nothing — so the fork resolves more
cleanly than expected; see fork 1 below.

Two supporting facts from the LangChain read (0.9.3): `ChatOpenAI` takes a full-URL `endpoint`
field, so pointing it at DeepInfra's OpenAI-compatible `/chat/completions` is the documented
pattern — and a `ChatOpenAI` struct is directly usable as a Sagents agent's model. For tests,
`req_config: %{plug: {Req.Test, …}}` is merged into the request right before post — the same
`Req.Test` seam the Worker client already uses (code-read conclusion; confirm with one throwaway
test when the agent rung lands).

## First principles (inherited, made concrete)

1. **The read path has no agentic decisions.** Extract, resolve, verify, render run in a fixed
   order on a fixed scope. Deterministic orchestration; the LLM appears only *inside* two stages
   (extraction, support) through the settled Worker client.
2. **A run is a receipt, not an answer.** It records *that the system acted* — options in, summary
   out. The facts live in the claims; the receipt is auditable provenance (kickstart-runs' framing,
   now needed for real).
3. **HITL is a status, not a blocker.** The pipeline already sets the gates (Person
   `pending_review`, Claim `support` verdict, Place `:proposed`); the run *surfaces* them as
   queues in its summary. Nothing pauses in this iteration — "not a cop, not a blocker."
4. **No spend.** The pilot runs on the seeded corpus; inference is pennies and goes through the
   existing Worker client. The spend gate is designed-for (it is Sagents' HumanInTheLoop, at the
   tool boundary) but not built until live acquisition lands.
5. **The dignity gate is untouched.** The orchestrator adds no new write paths — every write goes
   through the same Ash actions with `NoPrivateName` and the `:active`-gazetteer vocabulary.

## The run on the real pilot — the step graph

`Wekui.Pipelines.Orchestrator.run_read_path(event, agent, %{place_id: caraballeda, from: ~U[…], to: ~U[…]}, opts)`
— `agent` is the extraction Actor, passed explicitly and recorded in `options` (Actors are
content-addressed and immutable; a prompt revision mints a *second* agent on the event, so "the
event's agent" is ambiguous — the ask must name it).

```
PREFLIGHT   Worker.ready?  ·  event has ≥1 :active place  ·  posts in scope
    │            (a failed preflight refuses to start — no receipt is opened)
    ▼
Run :start        born :running — records the exact options asked
    ▼
EXTRACT     posts → Extract.run(event, agent, posts, opts)   [one batch on the pilot]
    │            writes Claims + Citations + Persons (born pending_review)
    │            PlaceResolver already runs inline per claim
    ▼
RESOLVE     each current claim → PlaceResolver.resolve(claim, actor_id:, post_id:)
    │            idempotent re-pass (ClaimPlace upserts, proposals reuse); this is
    │            where the run CAPTURES the resolver counts Extract discards
    ▼
VERIFY      each current claim → Verify.run(claim)
    │            records the support verdict — flag-only, withholds nothing
    ▼
RENDER      BeatRenderer.render(place_id, from, to) → %{prose, clauses, sources}
    ▼
Run :finalize     summary: per-stage counts + gate queues + the rendered beat
```

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
responsibility, not preflight's). **[PROPOSAL]** refuse to start: return
`{:error, {:preflight, reason}}` and open **no** receipt — a run that never ran is not a record of
the system acting. The seed is not auto-run: seeding is an explicit, separate act (already
idempotent), not a side effect of asking for a beat. Noted caveat for the agent rung: once
`run_pipeline` is an agent tool, a refused preflight leaves no receipt — the agent conversation is
then the only trace of the attempt.

### C. A crash mid-run — the `:running` crash artifact
Extract raises after drafting 4 of 9 claims (its writes are best-effort, not transactional — a
known reality). The receipt stays `:running` forever. **[PROPOSAL]** keep the two-state receipt
(kickstart-runs' shape): a `:running` row found later IS the crash signal; no `:failed` state, no
state machine. Stage errors the orchestrator *can* catch (`{:error, …}` tuples from
Extract/Verify/Worker) are recorded in the summary and the run still finalizes `:completed` — a
completed run with errors in its summary is an honest receipt. Only a raise leaves `:running`.

### D. Re-running — the one duplicate hazard
`Claim.:draft` has no identity: re-extracting the same posts mints duplicate claims (everything
else on the path is idempotent — resolve upserts, verify overwrites its verdict, seed reuses).
Until the merge-judge lands, the orchestrator must not blindly re-extract. **[PROPOSAL]** an
all-or-nothing scope rule, one citations query: **no** post in scope cited by a current claim →
extract runs; **every** post cited → skip extract (a pure re-pass run: resolve + verify + render);
**partially** cited → the extract stage refuses, recorded as an error in the summary, unless
`extract: :force`. Partial coverage is precisely the dangerous state (a crashed extract, a
retracted claim's posts falling back out of citation) and should be loud, not silently patched;
recovery is manual — retract the partials, then force — until the merge-judge lands. Per-post
skipping was considered and rejected: it re-feeds no-claim posts on every run (a
non-deterministic-model ratchet toward minting claims from noise v5 correctly dropped), it turns
`{{material}}` into partial batches the v5 prompt was never proven on, and it resurrects
deliberately retracted accounts.

### E. The gates — record, not pause
The run finalizes with `persons_pending_review`, `places_proposed`, `claims_not_supported` queues
(counts + ids) in its summary. Nothing blocks; the review UI (deferred) will service the same
statuses off the resources themselves — the run's queues are a snapshot for the operator's
inspection, not the source of truth. Re-verification is a snapshot too: the MoE judge can flip a
verdict between runs, so an old receipt may honestly disagree with current claim state.
**[PROPOSAL]** a `verify: :skip_verdicted` option for cost/churn control; default re-verifies all
current claims. The one *blocking* gate remains future spend (Sagents HumanInTheLoop at the
acquisition tool boundary, next rungs).

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
display receipt. The orchestrator (`Wekui.Pipelines.Orchestrator`) is a plain infra module like
Extract/Verify; `Wekui.Pipelines` becomes the Ash domain holding Run (fork 5), added to
`ash_domains` in config.

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
- **0b — the live re-extract IS the orchestrator's first real run.** Once the Run receipt +
  orchestrator are green on `Req.Test`, you run one command with `DEEPINFRA_API_KEY` in the real
  env; extraction re-proves on the *real* tree and the whole session's deliverable lands in one
  auditable receipt. Pennies; N-run variance is the known MoE reality — the gates + your review
  are the backstop.

Path (i) (re-seed onto `eb8ec55b`) stays rejected: `Seed` keys idempotency on
`{folded name, type, parent}`, so the stub `Tanaguarena (sector)` ≠ real `barrio` and
`OPP 25` ≠ `Edificio OPP 25` → duplicate nodes + wrong ClaimPlace links, and `Place` has no
destroy action by design. **[OPEN]** the fresh event's name (reuse `litoral-central-2026` and
retire the old event as backlog cleanup, or a distinct name?).

## The forks — batched, a recommendation each

1. **How much Sage, now — SETTLED BY THE SOURCE READ, pending your confirmation.** The corrected
   options: **(a′)** hand the four stages to a Sagents agent as tools and let the model sequence
   them (or write a custom execution Mode that bypasses the model and, with it, everything Sagents
   provides); **(b)** plain deterministic orchestrator + Run receipt now, Sagents introduced in
   this same session's third rung as the *agentic layer* — a thin agent whose tools are
   `run_pipeline` / `get_run` / `render_beat`, deciding *whether and with what scope* to run,
   never the internal stage order (the thin-agent boundary). **Recommend (b), firmly:** (a′) puts
   an LLM over a sequence with no decisions in it — the doctrine violation — and buys nothing:
   Sagents' pause/resume gates tool calls, and this iteration pauses at nothing (the gates are
   recorded statuses; the spend gate guards a tool that doesn't exist yet). The chosen runtime is
   unchanged — Sagents + LangChain remains the agent layer; the correction is only about *what*
   Sagents is (an agent loop, not a saga engine).
2. **Run — vocabulary or machinery? Recommend vocabulary** (a `run` concept page, draft above).
   It is operator-facing persisted state with a lifecycle, and under the agent-as-product pivot
   the run receipt is the product's audit surface — the thing you inspect. The op-log precedent
   (machinery) fit a projection artifact; a run is a first-class thing you list, open, and reason
   about. kickstart-runs deferred this fork and the concept resurfaced on its own — evidence it's
   vocabulary.
3. **Gate points — recommend record now, pause later** (scenario E). Pausing arrives with the
   review UI (content gates) and with acquisition (the spend gate, via Sagents HumanInTheLoop).
4. **Model call path — recommend split.** The deterministic pipeline keeps the Worker behaviour
   (settled, `Req.Test`-proven, `retry: false` caller-owned). The agentic layer necessarily goes
   through LangChain — a Sagents agent's model *is* a LangChain ChatModel struct — pointed at the
   same DeepInfra config (`ChatOpenAI` with `endpoint:` + `api_key:` from `:wekui, :deepinfra`).
   Two call paths, one config, each with its own `Req.Test` seam.
5. **Domain placement — recommend `Wekui.Pipelines` as the new Ash domain** holding `Run`, with
   the orchestrator as a plain infra module beside the existing `Wekui.Pipelines.Extract`/`Verify`
   (no `lib/wekui/pipelines.ex` exists today; Extract/Verify are plain modules, so no collision —
   the namespace already says pipeline; one home for stages, orchestrator, and receipt).
   Alternative: `Wekui.Runs`.
6. **Scope of the first run — recommend read-path only** (extract → resolve → verify → render on
   the seeded corpus). The beat LLM-polish stays the next rung, as an explicit separate step over
   the structured `clauses` — never an LLM over the renderer.
