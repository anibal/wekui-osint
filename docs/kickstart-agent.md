# Kickstart: the in-app agent — orchestrate the proven spine into a *run*

The deterministic spine of the "agent as product" is **built and proven end-to-end** on the 9
real Caraballeda claims: **posts → extract (claims) → resolve places (gazetteer) → verify
(support) → render (beats)**. Each stage is its own module; nothing yet *ties them together*.
This session turns those capabilities into the **in-app research agent** — one orchestrated,
auditable, gated pipeline **run** — and lays the **Sage (sagents) + Elixir LangChain** foundation
the operator chose for it.

Read the hub [`docs/pages/ubiquitous-language.md`](pages/ubiquitous-language.md), then
[`claim`](pages/claim.md), [`beat`](pages/beat.md), [`person`](pages/person.md),
[`place`](pages/place.md), and the two live design docs
[`docs/beat-scenarios.md`](beat-scenarios.md) and
[`docs/place-mapping-scenarios.md`](place-mapping-scenarios.md) (operator-annotated — they are the
validated behaviour). Skim [`docs/agent-architecture.md`](agent-architecture.md) and
[`docs/narrative-teardown.md`](narrative-teardown.md) for the pivot's reasoning.

**Do not write orchestration code until I have approved fork 1 (how much Sage, now) and a short
orchestration-scenarios doc.** The load-bearing decision here is not a schema — it is **how much of
the agentic runtime to stand up now versus a plain deterministic run first**. Settle that, then lean
on the settled patterns for the record-keeping parts.

---

## Priors — settled, do not relitigate

**The pivot (why we are here).** The in-app agent *is* the product; the **June 2026 Venezuela (La
Guaira / Caraballeda / Vargas) earthquake** is the eval harness. `wekui-new` is canonical; the old
Ecto `wekui` is a reference to mine and retire. Build by **vertical slice** (Caraballeda, first
days, **seed-first** from the old corpus). The deliverable is a **cited answer + a dignity-safe
narrative** for a public, donations-facing memorial. This reframed the port: the narrative layer got
a **Claim-first-class** redesign ([`docs/narrative-teardown.md`](narrative-teardown.md)).

**Already built and green — 460 tests, `mix precommit`, no migration drift.**
- `Wekui.Narrative` — **Claim** (open `kind` string, `subject` by role, `magnitude`, `place_mention`,
  `status`, `nuance`, `confidence`, `support`), **ClaimCitation** (evidence, immutable upsert),
  **ClaimPerson** (immutable), **ClaimPlace** (a claim spans *several* places — mutable upsert,
  `how_resolved` + `confidence`), **Person** (`display_handle` "Aaron C.", `kind` private/public,
  `status` pending_review/approved/withheld), **Handle** (`derive/1`), **PrivateNames** (the F54
  gate), **Merge** (executes a fold — the *judge* is NOT built), **PlaceResolver** (mention →
  gazetteer, deterministic), **BeatRenderer** (claims → Spanish prose).
- `Wekui.Clients.Worker` — inference **behaviour** + `Worker.Live` (Req POST to DeepInfra,
  OpenAI-compatible) + `ready?/0`; tested through a **`Req.Test` plug**. `complete(prompt, opts) ::
  {:ok, %{content}} | {:error, _}`.
- `Wekui.Pipelines.Extract` (posts → claims, gates every write) and `Wekui.Pipelines.Verify` (the
  support gate — records a verdict).
- `Wekui.Gazetteer.Seed` — loads `priv/gazetteer/caraballeda.json` (296 places, 683 names,
  cross-checked from old app + `gazetteer.db` + Tavily) into an event's tree; idempotent.
- Prompts: `prompts/extraction.v5.txt` (locked) + `prompts/support.v1.txt`.
- **The spine is PROVEN on real data:** 9 posts → 9 claims (0 name leaks, minors held, deaths
  caught, noise dropped) → resolved to the seeded gazetteer (9/10, honest UNRESOLVED for the one
  relational mention) → verify caught a deliberately-overstated control → a cited, dignity-safe
  Caraballeda **beat** in Spanish.

**The runtime decision — SETTLED.** **Sage (`sagents ~> 0.9`) + Elixir LangChain (`langchain ~>
0.9`)**, NOT `ash_ai`. Reason (researched, reversed an initial ash_ai lean): ash_ai speaks ReqLLM
and *cannot feed a Sage saga*; Sage is far ahead of ash_ai on orchestration. **Both deps are
installed; nothing is wired.** ash_ai is not a dependency and must not be added.

**Inference.** **DeepSeek-V4-Flash via DeepInfra** (OpenAI-compatible `/chat/completions`, bearer
auth), called with plain **`Req`**. Config: `:worker_client`, `:deepinfra` (`base_url` +
`api_key` from `DEEPINFRA_API_KEY` at runtime); tests swap in `Req.Test`. Inference is **pennies** —
the whole Caraballeda corpus is a few dollars. *Judging is cheap; the money is acquisition.*

**Gazetteer sourcing — DECIDED, build deferred** ([`decision-2026-07-26-gazetteer-from-osm`](pages/decision-2026-07-26-gazetteer-from-osm.md),
evidence [`docs/osm-gazetteer-research.md`](osm-gazetteer-research.md)). Future events self-seed from
**OpenStreetMap by bounding box** (Nominatim's model), **ODbL-licensed output** (sharing accepted).
**Not this session** — the pilot runs on `caraballeda.json`. Do not build the OSM importer here.

**Git — LEAN.** Solo, no PRs. **Commit each sub-concept straight to `main`** the moment it is green,
with the `Co-Authored-By` + `Claude-Session` trailers. Never a mega-commit.

**Two ash_sqlite realities (still bite anything persisted this session).**
1. **An identity's `where` is NOT a partial index.** "One current X per slot" is a `custom_indexes`
   partial unique (`unique: true, where: "superseded_at IS NULL"`), never an Ash identity. Compile
   with `--warnings-as-errors` *before* `mix ash.codegen`.
2. **ash_sqlite cannot run Ash-managed transactions** (`transaction? true` is a no-op). Multi-step
   atomic work uses an explicit `Wekui.Repo.transaction/1` (as `Merge.do_merge` does).

**Conventions locked in.** `uuid_primary_key :id`; FKs `on_delete: :restrict`; no multitenancy
(plain `belongs_to :event` + `Wekui.Validations.Reference` / `Wekui.Capture.Validations.SameEvent`);
immutable facts = `upsert? true` + `upsert_identity` + `upsert_fields []`; **a mutable link
(ClaimPlace) upserts its changing fields**; opaque blobs are `:map`; code interfaces via `define` on
the domain block.

---

## Standing constraints this layer inherits (read once, do not re-derive)

- **Deterministic first, the LLM last — and never over another LLM.** The operator's doctrine,
  earned this arc: *squeeze the deterministic pass as far as it goes (~90%), and leave preprocessed
  options for the LLM.* Extraction and support are LLM (unavoidable — reading open text). Place
  **resolution** and beat **rendering** are **deterministic** and must stay so; the agent orchestrates
  them, it does not re-LLM their output. The BeatRenderer already emits the structured `clauses`
  *for* a future LLM polish rung — build that rung as an explicit, separate step, not by wrapping the
  renderer in a model.
- **HITL is a *status*, not a blocker — "not a cop, not a blocker, continuous refinement."** The gates
  already exist as flags the pipeline sets: Person `pending_review`/`approved`/`withheld`, Claim
  `support` verdict, Place `:proposed`→`:active`. The orchestrator *surfaces* them; a future review
  UI *services* them (deferred, a different branch — do not build UI here). **This iteration does NOT
  gate beats by approval** (renders everything, dignity held by handle/role) — the review/public
  split is a noted future rung.
- **The money is X acquisition — that is the only spend gate.** Inference is pennies; Tavily is cents.
  Live collection burns **TwitterAPI.io** credits — the one thing an HITL **spend gate** must guard.
  The pilot runs on the **seeded corpus → $0 today**; a spend gate only bites when live acquisition
  lands (a later rung, gated).
- **The dignity red line is mechanical (F54), never a prompt.** `NoPrivateName` refuses a private
  name in a Claim `subject` (strict — not even an allowlisted public figure), checked against the
  event's **`:active`** gazetteer + the public-figure allowlist. The **beat inherits it**. A
  machine-proposed place is `:proposed` and **cannot widen the gate** until a human promotes it. Do
  not loosen this.
- **Credentials are env-only, and the Bash subprocess does NOT inherit `!`-set vars.** The operator
  has DeepInfra / TwitterAPI.io / Tavily keys, but setting them via `! set -x …` in the prompt does
  **not** reach the Bash tool's fresh subprocess, and grepping them out of the transcript is
  **correctly classifier-blocked**. So a live run needs the key in the **real env the app boots
  with** (or the operator runs it). **Design so the test suite never needs a key** (`Req.Test`);
  offer the operator a `! DEEPINFRA_API_KEY=… mix run …` line for any live check.

---

## Fundamental principles — non-negotiable

1. **Doc-first, scenarios-first.** New vocabulary (a **Run** receipt if it becomes a concept; the
   agent/saga terms) goes into `docs/pages/` **planned**, reviewed whole. For a new *behaviour* (like
   the orchestration graph and its gates), write a **scenarios doc at `docs/` root** with real
   examples and `[PROPOSAL]`/`[OPEN]` markers, get it annotated, *then* build. This is the pattern
   that worked for extraction, naming, place-mapping, and beats.
2. **Deterministic ~90%, LLM for the last ~10% — no LLM over the LLM.**
3. **Ash-first** for persisted concepts (`mix ash.gen.*` then refine); the orchestrator, clients, and
   renderer are plain infra modules (like `Tree`/`Normalize`).
4. **Warnings in our code are errors. The network is never in the suite** — every client is driven by
   `Req.Test` / an injected stub.
5. **The dignity gate is mechanical, checked against the `:active` gazetteer — never a prompt.**
6. **No new dependencies.** `sagents`, `langchain`, and `Req` cover this layer; `date_time_parser` is
   the only other pre-approval. **Never** `:ash_ai`, `:httpoison`, `:tesla`, `:httpc`, `Oban`. If you
   reach for one, STOP and ask.
7. **Measure, never assert. Commit each concept the moment it is green — straight to `main`.**
8. **Instill judgment, not rules or hardcoded categories** (the prompt doctrine — see Heuristics).
9. **Done means congruent** — doc, code, and database say the same thing in the same words. A concept
   page's `status::` must track whether its code ships (this exact gap left two stale `planned` pages
   — see the backlog).

---

## Heuristics — earned the hard way this arc

- **Iterate prompts by *removing*, not adding.** v5 beat v1–v4 by deleting conditionals and hardcoded
  categories and instilling *judgment* ("a discrete event at a moment"); the open `kind` string
  caught individual deaths a closed enum dropped.
- **Test a prompt on the *production* model, N≥3.** DeepSeek-Flash is a non-deterministic MoE; a
  Sonnet eval is a hypothesis, not the result. Single-pass drops vary — the gates + human are the
  backstop (the thin-agent thesis).
- **Pin the inputs against hallucination.** v4 invented posts/names/ids because a `{{material}}`
  block was dropped — always anchor "never invent a post/name/place/number/id," and feed the real
  material verbatim.
- **Squeeze deterministic first; escalate to the LLM only where the deterministic pass genuinely
  can't.** The resolver (fuzzy + ancestors) and renderer (per-kind templates) needed no model.
- **Order keyword dispatch by specificity.** The renderer's "rescatistas" bug: a body found *entre
  rescatistas* is a death, not a rescue — match `rescat[ae]`, not bare `rescat`, and check the
  specific kinds first. Choose **gender-neutral Spanish** so a deterministic pass never guesses
  agreement.
- **Cross-check a data source against another.** The gazetteer's confidence came from *agreement*
  across old-app + `gazetteer.db` + Tavily; *disagreement* is the highest-value signal (it caught
  Tanaguarena's `guess_low` and the Vargas↔La Guaira rename).
- **The classifier is right to block secret-extraction** (transcript-grep, compound `$KEY` checks).
  Do not route around it — ask the operator to set the key in the real env, or to run the live step.
- **Recover a crashed workflow from its journal.** The deep-research synthesis agent died on output
  serialization, but 105/106 agents' verified results sat in `journal.jsonl` — synthesize from it,
  don't re-run 105 agents. (`type:"result"` entries carry each agent's return value.)
- **Suppress SQL debug in demo scripts** (`2>/dev/null` then `grep` the marker lines) — dev logs
  every query and drowns the output.
- **`advisor` at the real forks and before declaring done**, deliverable already durable. It earned
  its keep this arc: it caught the ClaimPlace `upsert_fields` (a link is mutable, unlike a citation),
  the merge must **union** places, and the `:active`-gate-widening dignity risk — all before they
  shipped. Give its findings real weight; check the primary source.
- **Measure, reproduce-before-fixing, check-builtins-first, verify-the-RETURN, never coin a word not
  in the doc.**

---

## Strategy — the streamlined loop (move faster where patterns are settled)

1. **Read once, in parallel.** The built spine (`pipelines/extract.ex`, `pipelines/verify.ex`,
   `narrative/place_resolver.ex`, `narrative/beat_renderer.ex`, `narrative/merge.ex`,
   `clients/worker.ex` + `worker/live.ex`, `gazetteer/seed.ex`), the `Narrative` domain
   (`narrative.ex`) and its resources, and the prompts. **And the two runtime deps** — read
   `sagents` and `langchain` on hexdocs / in `deps/` (how a Sage saga is defined, how LangChain
   drives an LLM + tools, whether its OpenAI ChatModel can point at DeepInfra's `base_url`). A
   subagent fan-out is justified for the deps + spine read.
2. **Settle fork 1 first — a real stop-and-wait, in prose.** How much Sage now: (a) wire the
   deterministic read-path pipeline **as a Sage saga** (native pause/resume for HITL, proves the
   chosen runtime, no spend, no agentic decisions yet), or (b) a **plain deterministic orchestrator +
   Run receipt** now, with Sage layered on later for the agentic/spend-gated parts. Then batch the
   rest (Run = vocabulary or machinery, the run's shape, the gate points, LangChain-vs-Worker for the
   model call, domain placement) with a recommendation each.
3. **Write an orchestration-scenarios doc at `docs/` root** — the step graph on the real pilot
   (event + Caraballeda × window → seed? → extract → resolve → verify → render → the beat), where the
   HITL gates and the spend gate sit, and the Run-receipt shape — `[PROPOSAL]`/`[OPEN]` markers, for
   the operator to annotate. New vocabulary also goes into `docs/pages/` (load the
   `ubiquitous-language` skill).
4. **Build sub-concept by sub-concept, committing each green** (cleanest → riskiest): the **Run
   receipt** (the auditable record of a pipeline run — born running, finalized with a summary) → the
   **deterministic orchestrator** (one function/saga: the built steps in order, producing a beat +
   a receipt, on the seeded corpus, no spend) → the **Sage/LangChain wiring** (the agentic layer +
   HITL pause) → *(later rungs)* the **beat LLM-polish**, the **merge-judge**, **acquisition**
   (spend-gated). For each: generate/refine → `mix ash.codegen` (if persisted) → migrate dev+test →
   comprehensive tests (network via `Req.Test`) → `advisor` + self-trace of novel logic →
   `mix precommit` clean → commit + push.
5. **Verify hard where novel.** `advisor` before committing to the orchestration approach and before
   done; a rigorous self-trace of any failure/resume/gate logic; the network never in the suite.
6. **Update memory + docs** as each piece lands (evaluation-matrix.md, the concept pages).

---

## Tactics — the tools to orchestrate, and repo facts

**The built capabilities are the agent's tools (signatures to wire):**
```
Wekui.Pipelines.Extract.run(event, agent, posts, opts) :: {:ok, %{claims, drafted, skipped, skips}}
Wekui.Narrative.PlaceResolver.resolve(claim, actor_id: id, post_id: id) :: {:ok, summary}
Wekui.Pipelines.Verify.run(claim, opts) :: {:ok, claim}          # records support verdict
Wekui.Narrative.BeatRenderer.render(place_id, from, to) :: %{prose, clauses, sources}
Wekui.Gazetteer.Seed.caraballeda(event_id) :: %{created, reused, names}
Wekui.Narrative.Merge.merge(a, b) :: {:ok, canonical}            # executes a fold; the JUDGE is unbuilt
Wekui.Clients.Worker.complete(prompt, opts) :: {:ok, %{content}} # behaviour; Live = DeepInfra via Req
```

- **Sage + LangChain.** `sagents` = the saga/agent orchestration (steps, compensation, pause/resume);
  `langchain` = Elixir LangChain (an LLM chain + tool-calling). Read both before designing. The
  Worker client is plain `Req` to DeepInfra (OpenAI-compatible); LangChain's OpenAI-compatible
  ChatModel can likely target `config :wekui, :deepinfra, :base_url` — decide (fork) whether the
  agentic layer calls the model through LangChain while the deterministic pipeline keeps using
  Worker, or everything routes through one. Keep the **behaviour + `Req.Test`** discipline either way.
- **Config keys.** `config :wekui, :worker_client` (impl), `:deepinfra` (`base_url` +
  `api_key` from `DEEPINFRA_API_KEY`), `:public_figures` (F54 allowlist). Tests: `Req.Test` plug +
  `api_key: "test-key"` (`config/test.exs`).
- **A Run receipt (if built)** mirrors the never-executed `kickstart-runs` shape: a two-state record
  (`create :start` born `:running`, `update :finalize` sets `summary`/`finished_at`/`:completed`),
  `options`/`summary` as `:map`, `belongs_to :event`/`:actor`. No state machine for two states. `mix
  ash.gen.resource … --extend sqlite`, then `mix compile --warnings-as-errors` **before** codegen.
- **The migrate dance** (if a resource lands): `mix ash.codegen <name>`; if regenerating an unshipped
  migration, delete the file **and** its `priv/resource_snapshots/repo/<table>/` snapshots, then drop
  **both** DBs before `mix ash.setup`. `mix ecto.migrate` + `MIX_ENV=test mix ecto.migrate`.
- **The pilot event** (`wekui_dev.db`, id `eb8ec55b-…`) has the 9 real claims + a *stub* Caraballeda
  gazetteer + resolved ClaimPlaces + a renderable beat. The dev DB has **demo clutter** (several
  throwaway events from this arc's live runs) — filter by a real `kind` (e.g. `=~ "rescate"`) or by
  the event id; a cleanup is a backlog item.
- **A live check** needs `DEEPINFRA_API_KEY` in the real env; hand the operator
  `! DEEPINFRA_API_KEY=… mix run <script>` rather than trying to source it yourself.
- **`claims.place_id` is dead but physically present** — the `add_claim_place` migration commented
  out the column drop (SQLite FK on a populated table); it is always null and the Claim resource
  ignores it (a claim's places are `ClaimPlace` links). Do not mistake it for live state.
  `mix ash.codegen --check` is **clean** (verified — no migration drift).

---

## Tooling & environment protocol (repo-specific — this trips people up)

**The docs are an outl workspace with a live desktop app.**
- `docs/pages/*.md` are outl outlines: **ONE physical line per bullet** (never hard-wrap), two-space
  indent, `key:: value` props at the top then a blank line, `[[slug]]` links. **Prose** (headings,
  code, tables — like THIS file, the `kickstart-*`, and the `*-scenarios` docs) lives at **`docs/`
  root only**; outl bulletizes anything under `docs/pages/`. A root prose doc gets **no `.outl`
  sidecar**. Load the **`ubiquitous-language` skill** before authoring/creating any page.
- Lint a page: `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )' docs/pages/<p>.md` → no output; every `[[slug]]`
  must resolve to a file. `mix precommit` runs a docs check.
- **The `outl-desktop` app is RUNNING** (`pgrep -lf outl-desktop`). It adopts existing-page edits
  live and reprojects `.outl` sidecars — **NEVER start a second outl process**. Editing an existing
  page needs nothing. A NEW page's sidecar is regenerated by the app (the committed pre-commit hook,
  `core.hooksPath .githooks`, defers to the GUI and only warns).
- **STAGING — the landmine.** `.outl` sidecars reconcile **separately** from the `.md`. **Stage
  explicit paths; never `git add -A` / `commit -am`.** Run `git status --short` + `git diff --cached
  --name-only` before every commit and exclude `.outl` + unrelated live-app/journal churn. (There are
  pre-existing uncommitted `.outl` + journal changes NOT ours — leave them.)
- **`CLAUDE.md` is a symlink to `AGENTS.md` — edit `AGENTS.md`.** A standing decision written to the
  wrong file is silently lost.

---

## Anti-goals

- Do not write orchestration code before I approve fork 1 (how much Sage) and the orchestration
  scenarios.
- **Do not build the review console / any UI** — deferred, a different branch. HITL stays a *status*
  the pipeline sets; a UI services it later.
- **Do not build the OSM importer** — decided but deferred; the pilot uses `caraballeda.json`.
- **Do not gate beats by approval** this iteration (render everything; dignity by handle/role). The
  review/public split is a noted future rung.
- **Do not wrap the deterministic resolver or renderer in an LLM.** The LLM polish is a *separate*
  step over the structured `clauses`; no LLM over the LLM.
- **Do not put the network in the suite.** Every client through `Req.Test`.
- **Do not add a dependency.** Never `:ash_ai` (it can't feed Sage — that's why we're on
  sagents+langchain), never `:httpoison`/`:tesla`/`Oban`.
- **Do not spend X credits** without the HITL spend gate + my explicit approval; the pilot is seeded.
- Do not relitigate the settled decisions: Sage-not-ash_ai, OSM-sourcing (deferred), the
  operator-validated beat iteration (no approval gate now, current status, group-by-place, day
  grain, attribute-unsupported).
- Do not build one mega-commit; do not re-introduce branches/PRs.

---

## State snapshot (where we are now)

- **Built & green:** Core, Acquisition, Capture, Taxonomy, Judgment, **and the Narrative spine**
  (Claim cluster + Person + Merge-execute + PlaceResolver + BeatRenderer) + Worker client + Extract/
  Verify pipelines + Gazetteer.Seed. **460 tests, `mix precommit` clean, no drift.**
- **The deterministic spine is proven** on the 9 real Caraballeda claims — dignity-safe and cited —
  but **across two different events**: extract + verify + the beat ran on the pilot event
  (`eb8ec55b`) against a **5-place STUB gazetteer whose tree is known-wrong** (no Vargas municipio
  level; Tanaguarena typed `sector` not the real `barrio`; "OPP 25" not the canonical "Edificio OPP
  25"), while the real **296-node** gazetteer was seeded into a *separate, claim-less* demo event.
  **⚠ No single event yet holds BOTH the real gazetteer and the real claims** — so the read-path run
  has no valid target until that is fixed. **This is task 0, and it blocks orchestration.**
- **Git:** all on `main`. Recent: `cc3a70e` place mapping (ClaimPlace + resolver), `956a52b` gazetteer
  seed (cross-checked), `7abeaa6` OSM research, `c93a4ee` OSM decision, `8efdc26` beat rendering.
  Work directly on `main`; stage explicit paths (exclude `.outl`/journal churn).
- **NOT built (this session's frontier + backlog):** the orchestration/agent, a Run receipt, the beat
  LLM-polish rung, the **merge-judge** (which two claims are one happening — needs inference), the
  **support-gate iteration** (v1 answers in English), **live acquisition** (no TwitterAPI.io client
  yet), the OSM importer (deferred), the review UI (deferred).
- **Evidence base:** [`docs/evaluation-matrix.md`](evaluation-matrix.md) (honest layer-by-layer
  status), the two `*-scenarios` docs (operator-annotated), `docs/osm-gazetteer-research.md`,
  `priv/gazetteer/caraballeda.json`.

---

## This session's task: orchestrate the spine into the in-app agent

Tie the built, proven capabilities into **one auditable, gated pipeline run** — the agent's spine —
and stand up the **Sage + LangChain** foundation. Target the **read path first** (event + a place ×
window → extract → resolve → verify → render, on the **seeded** corpus, **no spend**); acquisition is
a later, spend-gated rung.

**Task 0 — establish a clean pilot event (do this FIRST; it blocks the read-path run).** No event
holds both the real 296-node gazetteer and the 9 real claims (see the State snapshot). Two paths:
**(i)** re-seed `caraballeda.json` onto pilot `eb8ec55b` — but `Seed` keys idempotency on
`{folded name, type, parent}`, so the stub `Tanaguarena(sector)` and `OPP 25` will NOT match the real
`barrio` / `Edificio OPP 25` → **duplicates + wrong ClaimPlace links to reconcile** (and `Place` has
no destroy action by domain design); or **(ii)** create a fresh event, seed the real gazetteer,
**port the 9 posts, and re-extract** (needs `DEEPINFRA_API_KEY` in the real env — a live extraction,
pennies). **Recommend (ii)** — it re-proves the whole pipeline on the *real* tree cleanly, honours
seed-first, and avoids the stub-reconcile mess; confirm the path with me before building on it.

**The forks I expect — batch with a recommendation each; reserve a real stop-and-wait for #1 and any
genuinely new vocabulary (a Run concept; agent/saga terms).**

1. **How much Sage, now — THE decision.** (a) wire the deterministic read-path pipeline **as a Sage
   saga** (native pause/resume for HITL, proves the chosen runtime, no agentic decisions, no spend);
   or (b) a **plain deterministic orchestrator + Run receipt** now, Sage layered on later for the
   agentic + spend-gated parts. *Lean:* the read path has no agentic decisions, so a plain orchestrator
   + Run receipt is the lowest-risk way to make the process auditable *today* — but the operator chose
   Sage deliberately and wants native HITL, so wiring it as a saga now is defensible. **Bring both,
   recommend one, do not pre-steer.**
2. **Run — vocabulary or machinery?** The first record of the system's *own* execution (what a run
   extracted/resolved/verified/rendered, which gates it hit, any spend). A `docs/pages/` concept page
   (operator-facing persisted state with a lifecycle), or an `architecture` stance + code? Decide
   deliberately (the `kickstart-runs` brief framed the same fork and it was never built).
3. **Where the gate points sit.** Person `pending_review`, Claim `support` verdict, Place `:proposed`
   are already set by the pipeline. Does the orchestrator *pause* at them (Sage), or just *record* that
   they exist for a later UI to service? Recommend: record now, pause when the review UI exists.
4. **The model call path.** Keep the deterministic pipeline on the `Worker` behaviour (Req +
   `Req.Test`), and use **LangChain only for the agentic/tool-calling layer** — or route everything
   through LangChain's DeepInfra-pointed ChatModel? Recommend: keep Worker for the settled pipeline
   calls; introduce LangChain only where the agent genuinely *decides*.
5. **Domain placement.** A new `Wekui.Pipeline` (or `Wekui.Runs`) domain for the Run receipt + the
   orchestrator/agent as infra modules, referencing Narrative/Capture/Core? Recommend a new domain.
6. **Scope of the first run.** Read-path only (seeded → extract → resolve → verify → render), or
   include the beat LLM-polish? Recommend read-path first; polish as the next rung.

**Start by** reading the built spine + both runtime deps' docs, then **bring me fork 1 settled, the
orchestration graph on the real pilot, the remaining forks batched, and any new vocabulary as a
scenarios/`planned`-page draft — not code.**

---

## Loose ends — a prioritized backlog (pick from these; do not lose them)

- ⟶ **The merge-judge** (which two claims are one happening) — the deterministic `Merge` exists; the
  *judge* (specificity rule: a specific subject/magnitude carries identity across noisy places, a
  generic one does not) is not built. Needs inference. Cross-batch duplication recurs at scale until
  this lands. A natural *tool* for the agent.
- ⟶ **The beat LLM-polish rung** — refine the BeatRenderer's structured `clauses` (merge "se buscaba
  a X; se buscaba a Y" → "…a X y a Y"; tighten "el cuerpo de una persona fallecida"). Explicit step
  over the structured output; no LLM over the renderer.
- ⟶ **Support-gate iteration** — `prompts/support.v1.txt` is un-iterated and **answers in English**;
  flag-only (records a verdict, withholds nothing). Iterate the prompt; decide what services the flags.
- **Live acquisition** — no `Wekui.Clients.TwitterApi` yet; when built, mirror the Worker shape
  (behaviour + `.Live` Req + `Req.Test`) and **gate the spend**. This is the only money.
- **The OSM gazetteer importer** — decided ([`decision-2026-07-26-gazetteer-from-osm`](pages/decision-2026-07-26-gazetteer-from-osm.md)),
  build when generalizing past Caraballeda.
- **Extraction/data gaps surfaced by the beat:** Aaron's "106 horas" landed in the `subject`, not
  `magnitude` (extraction gap); "Residencias Caribe" resolved to a *different* Caribe building via an
  alias (a merge/curation call); a bare "Caraballeda" scores 0.5 (parroquia vs populated_place — a
  cheap disambiguation heuristic to add).
- **Dev DB cleanup** — several throwaway demo events from this arc's live runs clutter `wekui_dev.db`;
  a re-seed onto a clean pilot event (or a small purge) would tidy it.
- **The review UI / human console** — deferred to a different branch; the gates are already the clean
  queues it will service.
- **Stale `status:: planned` pages** — `claim.md` and `beat.md` carry `status:: planned` while their
  code ships and is committed. Per CLAUDE.md that marker means "the code hasn't caught up," so it now
  reads backwards. Propose flipping them to `built` — the operator curates `status` in the outl app,
  so surface it rather than editing the prop yourself.

---

## What worked this arc — do more of it

- **Scenarios-doc-first, then build.** Real examples with `[PROPOSAL]`/`[OPEN]` markers, operator
  annotates inline, then code — it aligned extraction, naming, place-mapping, and beats before any
  code hardened. The operator prefers **forks batched inline with a recommendation each** over
  click-through `AskUserQuestion`; reserve a real stop for the load-bearing fork.
- **Deterministic-first, LLM-last.** The resolver and renderer needed no model; the structured
  intermediate leaves the LLM a clean 10% to polish. Squeeze this every time.
- **Cross-check sources; prove on real data.** The gazetteer's confidence came from three sources
  agreeing; every layer was proven on the 9 real claims, not asserted. *Measure, never assert.*
- **`advisor` at the forks and before done** — it caught real defects (ClaimPlace mutability, the
  merge place-union, the `:active` gate-widening) before they shipped. Check the primary source.
- **Recover, don't redo** — a crashed workflow's journal held the verified results; synthesize from it.
- **Commit each concept the moment it is green — straight to `main`**, explicit paths only, excluding
  `.outl`/journal churn.
- **The collaboration style that fits the operator:** decide the obvious and move; batch the genuine
  forks with a recommendation each; instill judgment over hardcoded rules; report faithfully (a null
  magnitude is a data gap — say so); lean process, high quality bar; move faster where patterns are
  settled.
