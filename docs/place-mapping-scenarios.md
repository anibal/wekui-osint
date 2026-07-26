# Place Mapping — scenarios for validation

**The job:** turn a claim's `place_mention` (the place as a post named it — "edificio OPP 25,
sector Tanaguarena, Caraballeda") into a gazetteer **[[place]]** (a `place_id` in the
state→municipio→parroquia→sector→edificio tree), *cheaply and honestly*. Proposed for your
feedback before any code — real examples, first principles, the design forks. Markers:
**[PROPOSAL]** my recommendation · **[OPEN]** your call.

## First principles

1. **Use what the record already knows before you spend.** Two free, high-signal sources: the
   **query** that found the post (its *swept place* — provenance) and the **post text** (the
   place it names). **Search (Tavily) is a paid, *secondary* source** — it is the fallback for
   the ambiguous and the unknown, never the first move.
2. **The explicit mention beats the sweep.** If the text names a place, that is where the claim
   is about — even if the post was collected under a query for somewhere else. A sweep is
   *provenance*, not *attribution*.
3. **Most-specific wins, anchored by its parents.** A hierarchical mention resolves to the
   *finest* gazetteer place that exists; the parent chain disambiguates a generic finest name
   ("Los Cocos" → the one in Caraballeda, not the one in Zulia).
4. **A sweep attributes at whatever granularity it swept — buildings included — weighted by the
   name's `emission`.** *(Corrected 2026-07-25 — the earlier "parish-or-coarser" cutoff confused
   the operator and was too crude.)* A building-level sweep is natural and will be common as the
   tree grows. With no mention, default to the query's swept place *at any level*; a `:raw`
   (self-anchoring) name attributes confidently, an `:anchored` (only-with-its-ancestors) name
   attributes weakly. `PlaceName.emission` already models exactly what the old F50 cutoff
   crudely proxied: distinctive names carry attribution, generic ones do not — so use the axis,
   not a granularity rule.
5. **A claim can be about *several* places.** *(New 2026-07-25 — from the operator's finding in
   the old data.)* One happening often spans adjacent buildings or zones ("OPP 22, 24 y 25",
   "Caribe y Los Corales"). A claim therefore links to *one or more* places through a
   **`ClaimPlace`** join — never a single `place_id` — exactly as it links to several posts
   (`ClaimCitation`) and several persons (`ClaimPerson`). Each link records how it was resolved
   and how confident we are.
6. **The gazetteer grows by proposal, never by guess.** An unmatched-but-identified place is
   created `:proposed` (a queue a human later promotes — the "human layer" that stays trivial);
   it is never silently made `:active`, and — because only `:active` names widen the F54 person
   gate — a machine proposal can never explain-away a private name on its own.
7. **Search is secondary provenance.** When Tavily/Nominatim resolve an unknown place, the result
   is a *proposal carrying its web sources*, never evidence of the event itself — and the
   **Vargas↔La Guaira (2019) rename** is a live trap every lookup must absorb.

---

## Scenarios (real `place_mention`s from the 9 extracted claims, + a few illustrative)

### A. Full hierarchy, finest exists → the building
`"edificio OPP 25, sector Tanaguarena, parroquia Caraballeda, La Guaira"` → parse to
`[OPP 25 · Tanaguarena · Caraballeda · La Guaira]`; the finest that exists in the gazetteer is
**OPP 25** (a building under Tanaguarena under Caraballeda) → map there. The parent chain
*confirms* the match (and disambiguates if two "OPP 25" exist). **Deterministic, no search.**

### B. Finest not in gazetteer, a parent is → map to the parent, propose the finer
`"edificio OPP 25, Tanaguarena, ..."` but OPP 25 isn't in the tree, Tanaguarena (sector) is →
map the claim to **Tanaguarena**, and **propose** "OPP 25" as a `proposed` building under it. The
parent anchors it and the name is specific, so **no search** — the human later promotes the proposal.

### C. Generic name — anchored by hierarchy or the query; alone → ambiguous
`"Los Cocos, Caraballeda"` → the parent "Caraballeda" anchors it to **Los Cocos de Caraballeda**
(not any other Los Cocos). `"Los Cocos"` **alone** → ambiguous; fall to the **query's place** (a
post swept for Caraballeda → the Caraballeda one), and only if *still* unresolved, **search**.
This is the genericity lesson: distinctive names self-anchor, generic ones need context.

### D. Coarse mention → the parish or the state
`"Caraballeda"` → the **parroquia**. `"La Guaira"` / `"estado La Guaira"` → the **estado**.
Distinctive and top-level → deterministic.

### E. Vague / relational → the named anchor, lower confidence
`"cerca de Caraballeda-La Guaira"` (Julio) → **Caraballeda parroquia** (the named anchor), flagged
approximate — there is no finer place, and "near" is not "in".

### F. Cross-parish — the mention beats the sweep
A post swept under a *Caraballeda* query but naming `"Punta Brisas, Macuto"` → map to **Macuto**
(a different parroquia), not Caraballeda. The explicit text wins; the sweep was just how we found it.

### G. No mention → the swept place, weighted by the name's `emission`
`place_mention` is null. Default to the query's swept place *at whatever level it queried* — a
**building** sweep included, since those are natural. A `:raw`-emission name (self-anchoring,
"Tanaguarena") attributes confidently; an `:anchored` name (generic, "Los Cocos", "Caribe")
attributes weakly and is flagged for review. `emission` replaces the old parish-or-coarser cutoff.
*(The pilot's posts are seeded with no query, so this waits for live acquisition — but it belongs
in the design now.)*

### H. Unknown place → search to identify + place, then propose  *(live-validated 2026-07-25)*
`"Residencias Karina"` — not in the gazetteer, no parent match in the text → a **Tavily** lookup
`"Residencias Karina" (La Guaira OR Vargas) Venezuela` returned, top result, *"Residencias Karina,
Parroquia Caraballeda, Municipio Vargas, La Guaira"* — an exact tree position. **Propose** it under
Caraballeda with its web source attached, born `:proposed`. This is the one place search earns its
cost; if it can't resolve either → **Unplaced** + a flag (never a guess). See the experiments below.

---

## The cross-cutting decisions I need your feedback on

1. **[PROPOSAL] Signal order:** explicit mention → (if generic/ambiguous) the query's swept place →
   (if still unresolved) search → else Unplaced. Mention always beats sweep. Right ordering?
2. **[PROPOSAL] Search fires only when the free signals fail** — an unknown place, or a generic name
   with no anchoring parent or query. Never for a clean match. (Cost: ~$0.016/lookup, one-time per
   new place.) Agree on the trigger?
3. **[OPEN] Matching mechanics** — the mention is matched against the gazetteer's `place_names`
   (canonical + aliases, folded), most-specific-first, parent-consistent. Is a fuzzy match allowed
   (e.g. "OPP 25" vs "Opppe 25 G"), or exact-folded only, with fuzzy left to search?
4. **[OPEN] Parsing the mention** — split on commas + type words (edificio/sector/parroquia/estado)
   into a hierarchy. Is that enough, or should an LLM parse the mention into `{name, type, parents}`?
5. **[PROPOSAL] New places are born `proposed`** (the human-promotes queue), anchored under the
   coarsest confident parent; a claim may point at a proposed place. Agree?
6. **[OPEN] Confidence** — should a claim carry a place-mapping confidence (exact match high,
   query-default medium, search-derived lower, relational lower), the way it carries claim confidence?

**How to give feedback:** mark up any scenario or decision, and I'll design the mapping process
against the *validated* behaviour — deterministic-first, search only where it earns its keep.

---

## Search experiments — live Tavily, 2026-07-25

Five real buildings, two query variants each (context vs OR-anchor). The event is real (Venezuela
24-jun-2026, Mw 7.2/7.5) and the web covers it densely, so the search layer is **viable, not a
last resort** — but it stays *secondary* (the gazetteer answers first; search is for the unknown).

**What resolved:**
- **Residencias Karina** → *"Parroquia Caraballeda, Municipio Vargas, La Guaira"* (0.85) + *"urb.
  Caribe"* — exact chain.
- **OPP 25** → *"sector Tanaguarenas … edificios OPP 25"* (OR-anchor 0.63); the context query
  drifted to a different building (OPPE 26).
- **Roca Park** → *"Edificio Rocapark, Parroquia Caraballeda, Municipio Vargas"* (OR-anchor 0.87
  vs context 0.74).
- **Residencias Caribe** → *"Torre C de Residencias Caribe … La Guaira"*, neighbours Los Corales.
- **Los Cocos** → *"sector Los Cocos de Caraballeda"* (0.80) — generic name pinned to its sector.

**Settled search design (the methodical part the operator asked for):**
1. **Query:** `"<name>" (La Guaira OR Vargas) Venezuela` — the OR-anchor beat the context query on
   the two hardest cases, does **not** presuppose the parish (the thing we're resolving *for*),
   and absorbs the **Vargas↔La Guaira** rename the sources use interchangeably.
2. **Success criterion:** a *result whose content* names a `Parroquia` / `sector` /
   `urbanización` — parse the chain from the sourced text, ranked by score.
3. **Ignore the `answer` field for facts** — it drifted (conflated OPP 25 with OPPE 26, invented a
   date). A disambiguation hint at most; never citable (matches the earlier Tavily research).
4. **A near-canonical source exists** — *"Mapa de edificios afectados por el terremoto"* emits
   clean `<Building>, <Avenue>, Parroquia <X>, Municipio <Y>, La Guaira` rows. Later, the gazetteer
   could be **bootstrapped** from it rather than proposed one building at a time.

**Status:** the query *shape* is validated on 5 buildings; the *parse-the-chain-and-propose* code
is not built or measured yet. Marked accordingly on the build.
