title:: Index
type:: hub

- The map of everything documented about this system. Each category has a hub of its own; this page only names them, slowest-changing first.
- [[first-principles]] — the values the system obeys; mined from where they already operate, and the slowest layer to change.
- [[ubiquitous-language]] — the shared vocabulary: concepts and policies; what things are.
- [[search-strategy]] — doctrine for collecting: how we choose what to ask, over which windows, in which order.
- [[architecture]] — stances on the system's shape: tools, storage, structure.
- [[decision-log]] — settled by observation; dated, append-only, every entry cites its evidence.
- [[open-questions]] — what we cannot answer yet; each unknown carries its age.
- [[research]] — the measurements and evidence the decisions cite.
- Conventions
  - Every page carries `type::` — `concept`, `policy`, `principle`, `strategy`, `architecture`, `decision`, `open-question`, `research`, or `hub` — and belongs to exactly one category hub. The triple never disagrees: slug prefix, `type::`, and hub membership say the same thing.
  - Record pages are born at a moment and carry their date in the name — `decision-YYYY-MM-DD-…`, `research-YYYY-MM-DD-…` — plus a `decided::` / `measured::` property. Living pages never carry dates in their names; open questions carry `opened::`, doctrine carries `revised::` when it changes.
  - `status:: planned` marks agreed vocabulary the code has not caught up with yet; a single planned piece inside a built page is tagged #planned.
  - Pages are outl outlines: one bullet per line (never hard-wrap inside a bullet), wiki-links between pages. Long-form prose lives at `docs/` root, outside the outline — for example the [clustering spike](../clustering-spike.md).
