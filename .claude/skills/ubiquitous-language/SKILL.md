---
name: ubiquitous-language
description: "Use when adding or changing any docs/pages/ outline page — domain concepts, principles, strategy, architecture stances, decisions, open questions, research — or when querying the outline (backlinks, planned/open status, journals). Covers the outl dialect, page categories, dated slugs, renames, and the adopt-and-verify protocol."
---

# The docs/ outline

`docs/` is an outl workspace (outl.app). Knowledge is one page per topic under
`docs/pages/`, mapped from the master hub `docs/pages/index.md` (category hubs:
`ubiquitous-language`, `first-principles`, `search-strategy`, `architecture`,
`decision-log`, `open-questions`, `research`). Claude drafts directly on the
files; Aníbal curates in the outl TUI. Markdown + git are the durable record;
`docs/ops/` and `docs/.outl/` are gitignored machinery.

outl sees only FLAT files in `pages/` — subdirectories are silently ignored.
Categories are therefore virtual, declared three redundant ways that must never
disagree: slug prefix, `type::` property, and membership in the category hub.

## Dialect — violations can corrupt pages

- Every bullet is ONE physical line. Never hard-wrap inside a bullet: a
  continuation line becomes a separate block.
- Two-space indentation per outline level. Bullets (`- `) only — no headings,
  paragraphs, or tables inside `docs/pages/`.
- Page properties are `key:: value` lines at the very top, then one blank
  line, then bullets. outl rewrites properties in alphabetical order whenever
  it touches a page — a props-only reorder in a git diff is normal, not damage.
- Link pages with `[[slug]]` (slug = filename without `.md`). Never use
  `((blk-...))` block refs in committed content.
- Prose documents live at `docs/` root and are NEVER moved into `docs/pages/`
  (outl would bulletize them line by line).
- Never run more than one outl process on the workspace at a time.

## Page categories

| `type::`        | slug shape                | dating                     | holds                                                        |
|-----------------|---------------------------|----------------------------|--------------------------------------------------------------|
| `concept`       | bare (`place`)            | never                      | one domain thing: definition + attributes + lifecycle + rules |
| `policy`        | descriptive               | never                      | a rule spanning several concepts                             |
| `principle`     | `principle-*`             | never                      | a value the system obeys, mined with verbatim quotes + links to where it bites |
| `strategy`      | under `search-strategy`   | `revised::` prop           | collection doctrine; changes as we learn                     |
| `architecture`  | under `architecture`      | `revised::` prop           | system-shape stances                                         |
| `decision`      | `decision-YYYY-MM-DD-*`   | date in slug + `decided::` | Settled-by-observation entry; `evidence:: [[research-…]]`; `status:: settled` |
| `open-question` | `open-*`                  | `opened::` prop            | a question we cannot answer yet; `status:: open`             |
| `research`      | `research-YYYY-MM-DD-*`   | date in slug + `measured::`| measurements the decision log cites; `status:: reference`    |
| `hub`           | category name / `index`   | never                      | one line per member page                                     |

Record pages (decision, research) are born at a moment: date in the slug, never
renamed to "update" them — a reversal is a NEW dated entry. Living pages never
carry dates in their names. `status:: planned` + `#planned` mark vocabulary the
code has not caught up with. When an open question gets answered, write the
dated decision page and shrink the open page to a pointer — never delete it.

## Changing pages (same change as the code)

1. Edit or create the page. A new page also gets its one-line entry in ITS
   category hub (index.md only lists hubs, not pages).
2. Renaming a slug: `outl -w docs page rename <old> <new>` (moves file, sidecar
   and op-log identity but NOT references), then rewrite every `[[old]]` and
   `pages/old.md` across `docs/` yourself and verify none remain. No outl
   process may be running during CLI writes.
3. Lint before committing:
   - `grep -nEv '^(\s*- |\s*$|[a-z-]+:: )' docs/pages/<page>.md` → no output.
   - every `[[slug]]` used must have a `docs/pages/<slug>.md`.
4. NEW pages only — sidecar adoption (edits to existing pages need nothing;
   outl reconciles them on its next run):
   - commit the `.md` first — git is the safety net;
   - `pgrep -lf outl`: if a TUI/serve is already running, stop here — it
     adopts the file live; NEVER start a second process;
   - otherwise: `outl -w docs serve &` … sleep ~8s … kill it, then
     `outl -w docs doctor` (expect "parses cleanly", no orphans) and
     `git diff -- docs/pages` (committed .md must be untouched);
   - commit the new `.outl` sidecar.
5. `mix precommit` as usual.

## Reading and querying

Read the files directly — hub first, then the pages the task touches; Grep
works fine. For graph questions use the CLI (no MCP needed):

- `outl -w docs backlinks page <slug>` — every block referencing a concept
- `outl -w docs query --prop type=open-question` — any prop; also `status=planned`
- `outl -w docs query --tag planned` — planned pieces inside built pages
- `outl -w docs search "<text>"` — full-text across the workspace
- `outl -w docs query --kind journal --since 7d` — Aníbal's recent journal
  notes; check them when asked "what's new" or before proposing priorities
