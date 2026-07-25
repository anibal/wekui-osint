# Ubiquitous-language ↔ code ↔ tests fidelity audit

_Dated 2026-07-24. A point-in-time cross-check that the vocabulary in
`docs/pages/` (concepts, policies, principles, behaviour-asserting decisions)
still means, in the code and the test suite, exactly what the pages say._

## Method

For each of the **22** concept/policy pages (21 concepts + 1 policy), the page
was read against the Ash resource(s) that realize it and the test(s) that
exercise it — comparing attributes, lifecycle, rules, relationships, and
identities. The check ran in **both directions**:

- **doc → code**: every rule and attribute a page states is enforced in code;
- **code → doc**: every registered resource and behaviour-bearing helper maps to
  a documented concept or is documented technique — no undocumented vocabulary.

Tests were checked **per-rule**, not per-file: for each documented rule, a test
asserts it. All 22 pages are `status:: built` (none `planned`), so any divergence
is a genuine finding rather than an intended gap.

Suite at time of audit: `mix test` → **372 passed (2 doctests, 370 tests), 0
failures**.

## Result

**One genuine finding, one observation. Everything else is aligned.**

### FINDING-1 — placement.md where-read chain omitted the `proposed` branch (fixed)

`placement.md`'s where-resolution chain enumerated the read by exact lifecycle
but listed only `active → that Place`, while the code resolves **proposed or
active → that Place** — a real, tested path, since placing on a proposed Place is
allowed:

- `lib/wekui/judgment/where.ex` — `live when live in [:proposed, :active] -> {:place, place}`
- `lib/wekui/judgment/placement.ex` moduledoc — "an active or proposed Place reads as itself"
- `test/wekui/judgment/placement_test.exs` — "a proposed Place reads as itself" (passing)

The contract page was behind both the code and its own resource moduledocs.
Corrected in the same change as this audit: the bullet now reads "proposed or
active → that Place".

### OBS-1 — an Appearance Rule with no enforcing mechanism yet (not a contradiction)

`appearance.md` lists under **Rules**: "Every Post has at least one Appearance."
Nothing at the resource layer enforces this — `Post.collect` and
`Appearance.record` are independent actions, and a Post can be created without an
Appearance. It is a collection-*flow* invariant that the not-yet-built collection
runner (Runs/Narrative) will guarantee. No code claims otherwise. Left as-is; a
future note could point out that enforcement lives in the runner.

## Alignment detail (the 22 pages)

| Concept | Realized by | Exercised by |
|---|---|---|
| event | `Core.Event` + `CreateUnplacedPlace` | `event_test` |
| actor | `Core.Actor` + `ContentHash` | `actor_test` |
| place | `Core.Place` (state machine) | `place_test`, `proposed_by_test` |
| place-name | `Core.PlaceName` + `Fold` | `place_name_test` |
| search | `Acquisition.Search` (state machine) | `search_test`, `decompose_test` |
| search-term | `Acquisition.SearchTerm` | `search_test`, `decompose_test` |
| query | `Acquisition.Query` | `query_test` |
| query-text | `Acquisition.QueryText` | `query_text_test`, `decomposition_test` |
| decomposition | `Acquisition.Decomposition` + `Plan` | `decomposition_test`, `decompose_test` |
| coverage | `Query.covering` read + `ResultMode` calc | `query_test` |
| post | `Capture.Post` + `SameEvent` | `post_test` |
| author | `Capture.Author` | `author_test` |
| appearance | `Capture.Appearance` + `SameEvent` | `appearance_test` |
| theme | `Taxonomy.Theme` (state machine) | `theme_test`, `proposed_by_test` |
| author-tag | `Taxonomy.AuthorTag` (state machine) | `author_tag_test`, `proposed_by_test` |
| judgment | judgment helpers (`Slot`, `Supersede`, `CloseCurrent`, `Retract`, `Provenance`) | all judgment tests |
| theme-judgment | `Judgment.ThemeJudgment` + `ThemeNone` + `SetReplacement` | `theme_judgment_test` |
| author-tag-judgment | `Judgment.AuthorTagJudgment` + `AuthorTagNone` | `author_tag_judgment_test` |
| placement | `Judgment.Placement` + `Where` + `NoPlace` + `NotUnplaced` | `placement_test` |
| no-place | `Judgment.NoPlace` | `placement_test` |
| unplaced-place | `Event.unplaced_place_id` + `CreateUnplacedPlace` | `event_test`, `decompose_test` |
| settling-a-collected-place | `Judgment.Where.follow` | `placement_test` (`Where.of`) |

## Cross-cutting passes

**Behaviour-asserting decision pages — all still obeyed:** slice-length (600s
default), term-off-switch (no flag), no-folded-text, engagement-in-payload,
appearance-engagement, first-query (no pointer; first Appearance is the answer),
post-is-the-message (no repost wrapper), follower-count (absent from Author),
merge-is-deprecation (no merge concept anywhere; deprecate + where-read is the
mechanism).

**Principles — every cited embodiment verified:** never-rewrite-the-record
(Post/Author immutability, append-only judgments, fixed slice grid);
unknown-is-never-zero (nullable Query counts, examined-empty none-judgments,
Unplaced ≠ No place); one-name-per-fact (no first-query/follower/engagement/fold
copies, calculated Query state); rather-ask-twice-than-lose-a-name (name-splitting,
whole slices); evidence-over-impression (Actor person/agent parity, attribution
bridges); a-wrong-answer-is-worse-than-none (country emits nothing, coverage
latest-only).

**Code → doc, no orphans:** `SearchPlace` (Scope join) and `QueryName`/`QueryTerm`
(attribution bridges) are documented technique; `ThemeNone`/`AuthorTagNone` are the
examined-empty answers the vocabulary explicitly says "carry no proper name of
their own." Every behaviour-bearing helper traces to a documented rule.
