---
name: ubiquitous-language
description: "Use when adding or changing a domain concept, decision, open question, or research note in docs/pages/, or when querying the outline (backlinks, planned/open status, journals). Covers the outl dialect, page types, status transitions, and the adopt-and-verify protocol for new pages."
---

# The ubiquitous-language outline

`docs/` is an outl workspace (outl.app). The vocabulary is one page per concept
under `docs/pages/`; the hub is `docs/pages/ubiquitous-language.md`. Claude
drafts directly on the files; Aníbal curates in the outl TUI. Markdown + git
are the durable record; `docs/ops/` and `docs/.outl/` are gitignored machinery.

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

## Page types and properties

| `type::`        | `status::`            | holds                                                        |
|-----------------|-----------------------|--------------------------------------------------------------|
| `concept`       | `built` \| `planned`  | one domain thing: definition + attributes + lifecycle + rules |
| `policy`        | `built` \| `planned`  | a rule spanning several concepts                             |
| `decision`      | `settled`             | a Settled-by-observation entry; also `evidence:: [[research-…]]` |
| `open-question` | `open`                | a question we cannot answer yet, linked from what it blocks  |
| `research`      | `reference`           | measurements the decision log cites                          |
| `hub`           | —                     | the index: one line per page                                 |

`#planned` tags a single planned piece inside an otherwise built page.

## Changing the vocabulary (same change as the code)

1. Edit or create the page. A new page also gets its one-line entry in the hub.
2. Status transitions, never silent deletion: when planned code ships, drop
   `status:: planned` / the `#planned` tag; when an `open-*` question gets
   answered by evidence, write the `decision-*` page and shrink the open page
   to a pointer (or repurpose it) in the same change.
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
