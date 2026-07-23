title:: Architecture
type:: hub
revised:: 2026-07-23

- Stances on the system's shape: tools, storage, structure. Seeded with what is already decided elsewhere — to be grown here as stances earn write-ups:
  - Domain-first in Ash on SQLite: behavior lives in resources and actions, database changes go through codegen (standing decisions in AGENTS.md).
  - Full-text matching without stored folds: FTS5 `unicode61` with `remove_diacritics 2` folds at index time, straight off the Payload's text — see [[research-2026-07-23-clustering-spike]] and [[decision-2026-07-23-no-folded-text]].
  - The documentation itself: `docs/` is an outl workspace; markdown plus git are the record, the op-log is machinery.
