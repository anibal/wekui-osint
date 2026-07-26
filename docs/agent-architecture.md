# The In-App Agent — architecture (runtime, tools, gates)

> **⚠ CORRECTION (2026-07-26).** This doc's premise that sagents ("Sage") provides saga-style
> orchestration was a misread: a source read of `deps/sagents` 0.9.0 found an LLM-agent loop on
> LangChain — the model sequences tool calls; pause/resume approves tool calls; there is no step
> graph, compensation, or rollback. The **deterministic pipeline** is orchestrated with
> **Reactor** instead (already an Ash dep) — see
> [`decision-2026-07-26-reactor-not-sagents`](pages/decision-2026-07-26-reactor-not-sagents.md).
> The §1 runtime fork below (Sage-vs-ash_ai) is now historical: ash_ai stays out, and the
> **talking-agent layer's** runtime (where this doc's HITL/subagent/streaming research would
> apply) is an open decision for that later rung. The tool-bridge, spend-gate, and
> location-assist research below remains valid input to that future decision.

**Companion to `narrative-teardown.md`.** That doc redesigns the *narrative*
(Claim/Beat); this one is *how the agent runs*: the runtime, the tools it calls, and
where a human gates it. **Design only — no code until the vocabulary and this shape are
approved.** Markers: **[SETTLED]** · **[PROPOSAL]** · **[FROM RESEARCH]** (verified
against primary sources + this repo's lockfile) · **[OPEN]**.

**Frame [SETTLED]:** the agent is the product; it runs **inside** `wekui-new` (no CLI);
it drives a research request end to end; **spend is gated** (plans/reads free, any
credit-spending action pauses for human approval). The old doctrine's deepest lesson —
*every invariant is a mechanical gate, not a prompt rule* (F54) — means the agent stays
**thin**: the discipline lives in Ash validations/changes + report actions; the agent
owns only the genuinely non-deterministic decisions.

---

## 1. Runtime — the finding that reverses the premise, and the fork it opens

**[FROM RESEARCH] `ash_ai` cannot hand Sage ready-made tools.** Current `ash_ai`
(0.7.3) did a **hard cutover to ReqLLM** (removed LangChain in v0.6.0, 2026-04-09); its
tools are `ReqLLM.Tool`. **Sage** runs on **Elixir LangChain** and its tool contract is
`tools/1 :: [LangChain.Function.t()]`. A `ReqLLM.Tool` does not satisfy it, and the
"pin old `ash_ai`" escape is closed (old `ash_ai` needs `langchain ~> 0.4`; Sage needs
`>= 0.8.11` — mutually exclusive). They **co-install fine** (different LLM clients, both
ultimately on Req/Finch), but **the actions→tools convenience does not transfer to Sage.**

That undercuts the reason ash_ai was in the plan ("convenient for tooling"). So the
runtime is now a genuine fork — **decide this first, like fork-1 in `kickstart-runs`:**

- **[PROPOSAL — recommend] Option 1: Sage + LangChain only; drop `ash_ai`.** One LLM
  stack. The agent loop is Sage; every tool is a hand-written `LangChain.Function` that
  calls an Ash **code-interface** action (§3); the structured LLM steps (claim-extract /
  merge-judge / verify-support / render) are **schema-constrained LangChain calls** — a
  `LangChain.Function` with a `parameters_schema`, validated in-tool by the Ash action it
  wraps, retried via `until_tool_success` (**verified: no capability gap vs ash_ai's
  prompt-backed actions**). Fewest deps, no ReqLLM, no `ash_json_api` /
  `open_api_spex` baggage. Ash stays the domain authority; it just isn't the LLM client.
- **Option 2: Sage (LangChain) for the agent + `ash_ai` (ReqLLM) for the structured
  pipeline actions.** Keep ash_ai's *prompt-backed actions* (return-type = output schema,
  validation as Ash errors) for the Claim steps, and still hand-write the Sage tool
  wrappers. Costs a **second LLM stack** (ReqLLM alongside LangChain) plus ash_ai's
  non-optional `ash_json_api` + `open_api_spex`. Buys Ash-idiomatic structured actions
  and MCP-if-ever-needed. Given the tool bridge is hand-written either way, the extra
  stack mostly buys ergonomics.

**Recommend Option 1 — now verified.** Option 2 buys *nothing for the Sage runtime*:
ash_ai's tools can't cross the ReqLLM↔LangChain boundary into Sage regardless, so you'd
hand-write the `LangChain.Function` wrappers either way, and LangChain reproduces exactly
what ash_ai's prompt-backed actions give at runtime (schema-constrained output +
validation + retry). What Option 1 gives up is only *convenience* — auto-deriving the JSON
schema from Ash types and auto-running the action's own validations as the tool body;
that's boilerplate, not a missing capability. Keep ash_ai only if you separately want its
ReqLLM tooling *outside* Sage. You preferred ash_ai for tooling; the honest finding is that
that convenience doesn't reach Sage — this is the reversal to weigh.

**[FROM RESEARCH] Compatibility (verified against `mix.lock`):**

| | needs | this app | verdict |
|---|---|---|---|
| **Sage** `sagents ~> 0.9` | `langchain >= 0.8.11`, `ecto ~> 3.11`, `phoenix_pubsub ~> 2.1`, `phoenix ~> 1.8` (opt), `horde ~> 0.10` (opt), `elixir ~> 1.17` | ecto 3.13, pubsub 2.x, phoenix 1.8.9 | ✅ (target 0.9.x; Horde only if clustered) |
| **ash_ai** `~> 0.7` (Option 2 only) | `ash >= 3.7.1`, `req_llm ~> 1.7` (→ Req, ✅), `elixir ~> 1.17`; pulls `ash_json_api` + `open_api_spex` (non-optional); `vectorize` needs pgvector → **skip on SQLite** | ash 3.29.3, req 0.6.3 | ✅ with baggage |
| **Elixir floor** | both need `~> 1.17` | runtime **1.20.1** (OTP 27); `mix.exs` declares `~> 1.15` | ✅ runtime fine; bump the declaration to `~> 1.17` when deps land |

**First action on approval (either option): a throwaway `mix deps.get` + hello-world
Sage agent that calls one trivial Ash action, to confirm the tree resolves before
anything real is built.** That spike also confirms the two field-name details a fetch outage left unread —
`LLMChain.run(mode: :until_success)` semantics and whether `Sagents.Extract` coerces vs
returns raw tool args — neither of which flips the Option-1 verdict. No new dep goes in
`mix.exs` until you say so.

**Model choice:** pick current Claude ids per the `claude-api` skill / provider catalog
(Sonnet-class for judgment steps — merge adjudication, rendering; Haiku-class for cheap
mechanical steps), not the `*-4-5` ids in the research snippets. Key via env
(`ANTHROPIC_API_KEY`), never printed.

---

## 2. Tools — the bridge (hand-written, both options)

Since ash_ai can't feed Sage, tools are **thin `LangChain.Function` wrappers in a Sage
middleware**, each calling an Ash code-interface action — Ash remains the domain/tool
*implementation*, LangChain is just the wire shape:

```elixir
def tools(_config) do
  [ LangChain.Function.new!(%{
      name: "run_acquisition",                 # THIS string is the HITL key — must be byte-identical in §4
      description: "Collect posts for a frozen Search (spends X credits)",
      parameters_schema: %{type: "object", properties: %{search_id: %{type: "string"}},
                           required: ["search_id"]},
      function: fn %{"search_id" => id}, _ctx ->
        case Wekui.Runs.run_search(%{search_id: id}) do   # Ash code interface
          {:ok, r} -> {:ok, Jason.encode!(r)}
          {:error, e} -> {:error, Exception.message(e)}
        end
      end }) ]
end
```

Tool groups by whether they spend: **free** (orient/read: event brief, coverage, run
history, Claim/Beat reads, the Coverage/Density/Richness reports — the statistician's
toolkit as *computed reads*, not agent arithmetic); **cheap inference — the Claim loop**
(extract-claims, propose-merge, verify-support, render-beat; each opens a Run receipt;
no credit gate in the seeded pilot); **spends money — GATED** (live acquisition, large
judge runs — *deferred past the pilot*).

---

## 3. Gated spend — the HITL mechanism [FROM RESEARCH]

Sage's `HumanInTheLoop` middleware intercepts a tool call *before execution* and emits an
interrupt. **The interrupt key is the tool's `name:` string** — the paid tool's name and
the `interrupt_on` key must match exactly or the gate silently never fires.

```elixir
Agent.new(%{ middleware: [
  {Sagents.Middleware.HumanInTheLoop,
   [interrupt_on: %{"run_acquisition" => true}]}  # true => decisions [:approve, :edit, :reject]
]})
```

On a gated call the agent goes to `:interrupted` and emits `{:status_changed,
:interrupted, %{action_requests: [...], hitl_tool_call_ids: [...]}}`; a human decision
(`:approve` | `:edit` args | `:reject`) is collected in the LiveView and returned via
`AgentServer.resume(agent_id, decisions)` (decisions are **positional**, count-validated;
non-gated calls in the same batch auto-approve). 0.8+ has **restorable interrupts** — a
pause survives a process restart if persistence is configured. This *is* the "inspect
before spend" gate, enforced in the runtime rather than the prompt.

**Gate the gate (F54 applies to us).** The byte-identical match between a tool's `name:`
and its `interrupt_on` key is itself a money invariant enforced by a string. Derive both
from **one source** — a module attribute listing the gated tool names, used to build the
`Function.new!` names *and* the `interrupt_on` map — and **assert at startup** that every
gated name is present in the agent's tool list. A gated tool whose name drifts from its
key must fail to boot, never silently spend.

---

## 4. Subagents, structured finish, streaming, persistence [FROM RESEARCH]

- **SubAgents** (`SubAgent` middleware): a `task` tool delegates to a child with
  **isolated context** (own message history) that reports back a summary — keeps the
  parent's context clean (the multi-context-window discipline). **HITL escalates**: a
  child's interrupt propagates to the parent, carrying the child's request
  (`%{type: :subagent_hitl, ...}`), so one top-level approval dialog covers paid tools a
  subagent proposes.
- **Structured finish** (`until_tool: "deliver_answer"` on the synchronous
  `Agent.execute/3`): the agent loops until it calls the named tool, returning a clean
  `{:ok, state, %ToolResult{}}` — the idiomatic "force a cited, structured final answer."
  (Reachable on the sync path; for the async server path drive `Agent.execute/3` inside a
  Task.)
- **Streaming to LiveView:** agent events are delivered **point-to-point** to subscriber
  pids (via `Sagents.Subscriber`), **not** over a Phoenix.PubSub topic (PubSub is only
  presence). Events: `{:agent, {:llm_deltas, …}}` (token stream), `{:llm_message, …}`,
  `{:tool_execution_started/completed, …}`, `{:status_changed, …}`, `{:todos_updated, …}`.
- **Persistence/resume:** optional behaviours (`AgentPersistence`,
  `DisplayMessagePersistence`) you implement **against `ash_sqlite`** — fits cleanly
  (persistence is our store, not a competing DB). With Factory/Session get-or-start-by-id,
  a LiveView reconnect re-attaches instead of spawning a duplicate.

---

## 5. Location-assist tools [FROM RESEARCH — complete]

Two separate tools feeding one **proposal** a human then acts on. Both **plain `Req`, no
new dependency, effectively free.**

- **`web_place_lookup(name, fixed_context)` → Tavily.** `POST api.tavily.com/search`,
  `auth: {:bearer, …}`, `search_depth: "advanced"` (≈$0.016), `country: "venezuela"`,
  `include_answer: false`. Free tier 1,000 credits/mo. Job: *ambiguous name → referent +
  sourced context.* Fallback: Brave. (Google Programmable Search is closed to new
  customers, ends 2027-01-01 — avoid.)
- **`geocode_place(name)` → Nominatim/OSM.** `GET .../search?format=jsonv2&countrycodes=ve
  &addressdetails=1`, a real identifying `User-Agent` (policy), **≤1 req/s**, **cached**
  (cache = audit snapshot). Free. Job: *formal name → coords + admin address.*
- **Chain:** web-lookup disambiguates the colloquial string first, then geocode the
  resolved formal name.
- **The Vargas→La Guaira trap:** estado was *Vargas* until 2019; query both and **verify
  `address.state` is La Guaira *or* Vargas in code** (`viewbox` is a soft boost, not a
  filter). In the model this is a [[place-name]] of Kind `historical`.
- **Honesty:** web/geocoder sources are **secondary provenance**, tagged and
  **structurally separate** from Post evidence — they justify the gazetteer *mapping*,
  never the *event*. Tavily `answer` disabled. Below a state-verified confidence floor the
  tool returns **zero candidates** (`principle-a-wrong-answer-is-worse-than-none`).
- **Writes via the human gate:** output is a proposal → a person **proposes a [[place]]**
  (`proposed`, promoted to `active` only by a human) and **anchors a [[place-name]]**
  (`Emission: anchored`). A Place carries no confidence — that number informs the human
  and the eventual [[placement]].

---

## 6. The thin-agent boundary [PROPOSAL]

- **Deterministic Ash (substrate):** query planning; the Claim merge pre-filter;
  Coverage/Density/Richness computations; the person gate; the support-gate wiring; the
  Beat rendering write-path; Run receipts.
- **Agent judgment (non-deterministic):** request→scope; "what to fetch next" under
  budget; reading the statistician's outputs to decide saturate / steer / stop;
  adjudicating merge proposals; orchestrating extract→merge→verify→render; deciding when
  to escalate to the human.

---

## 7. Open decisions

1. **[FORK — yours; I recommend Option 1, now verified] Runtime: Sage + LangChain only
   (drop ash_ai) vs keep ash_ai/ReqLLM for structured actions.** §1 — Option 2 buys nothing
   for the Sage runtime; ash_ai's tools can't feed Sage either way.
2. **[FROM RESEARCH — needs a human call] Web-derived place provenance.** `Place.proposed_by`
   records an Actor + *optionally the Post it was inferred from* — a web-assisted proposal
   has **no Post**. Options: an `open-web-derived-place-provenance` page (`opened::
   2026-07-25`) or a `status:: planned` `resolution-provenance` structure. **Do not invent
   a field silently.**
3. **[resolved]** Elixir runtime is **1.20.1 (OTP 27)** — above the `~> 1.17` floor. Only
   the `mix.exs` declaration (`~> 1.15`) bumps to `~> 1.17` when the deps land; no
   environment blocker.
4. **[OPEN]** How much of the statistician's toolkit is a computed Ash read vs agent-side
   calculation (Good–Turing, capture–recapture, λ, saturation).
