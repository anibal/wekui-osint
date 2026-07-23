title:: Search
type:: concept
status:: built

- A **Search** is one [[actor]]'s stated intention to go and collect posts: *these Places, over this stretch of time, optionally about these words.* It belongs to exactly one [[event]].
- A Search is not itself a request to X. It is the plan from which many small, exact requests are worked out. Those requests are Queries — see [[query]].
- A Search has:
  - **Name** — a short label. No two Searches of the same Event share a name. We do not create a second Search to change our mind about the first; we extend the one we have.
  - **Intent** — a plain sentence saying what we are trying to collect and why. We write it down so that later we can hold the intention up against what actually came back.
  - **Window** — the stretch of time we want to cover, from its **window start** to its **window end**. A Search with no window end is **open**: it keeps covering time as time passes.
  - **Slice length** — a long window cannot be asked for in one request, because X returns only so much at a time. So we cut the window into consecutive **slices** of this length and ask about one slice at a time.
    - The slice length is remembered on the Search, so that working the plan out again produces exactly the same Queries. If none is given, it is ten minutes — see [[decision-slice-length]].
    - Slices are always whole, which means the last one reaches a little past the window end when the window is not a whole number of slices long.
    - This is deliberate: it keeps the slices anchored to a grid that never moves, so pushing the window end out later only ever *adds* slices. A slice we have already asked about never turns into a different, longer one, and no two Queries ever ask about overlapping stretches of time.
  - **Result mode** — how we want X to choose what to return:
    - **latest** — everything it has for that slice, newest first. Only this mode can be treated as complete coverage of the slice — see [[coverage]].
    - **top** — a selection X considers most relevant. Useful for sampling, never counted as complete.
    - Whether latest simply extends top is open, to be settled by observation — see [[open-latest-vs-top]].
  - **Scope** — the Places this Search covers.
    - Naming Places explicitly says *collect on exactly these*, and they may be proposed as well as active: collecting is often how we find out whether a proposed [[place]] was real.
    - An **empty** Scope says *collect on the Event's settled geography* — every active Place, decided at the moment the plan is worked out, and never anything merely proposed.
    - Either way the [[unplaced-place]] is never searched, and a Place that has been deprecated or discarded is never searched.
  - **Terms** — the words the Search is about — see [[search-term]]. A Search with no Terms is a **base sweep**: it asks about the Places alone.
  - **Status note** — a sentence saying why the Search is where it is right now.
- Lifecycle
  - **Draft** — being written. This is the only step in which the plan can be changed, because Queries in draft have never been asked and can be thrown away and worked out again freely.
  - **Ready** — an [[actor]] has approved the plan. It is now fixed.
  - **Active** — collecting. This is the only step in which Queries are actually asked of X.
  - **Paused** — deliberately held, and resumable.
  - **Closed** — finished. This is final.
- Rules
  - A Search starts as draft.
  - Only a draft Search can be edited, and only a draft Search's plan can be worked out again.
  - Only a ready or paused Search can be made active. We remember when it first became active, and when it was closed.
  - Only an active Search can be paused.
  - Any Search that is not already closed can be closed. Closed is final.
- Extending
  - Once a Search has left draft its plan is fixed, but the world is not. To grow a Search we **extend** it, along one dimension at a time: add a Place, add a Term, or push the window end further out.
  - Extending only ever *adds* Queries; it never rewrites or removes the ones already there, so nothing we have already collected is put in doubt.
- A Search is worked out into its Queries by [[decomposition]].
