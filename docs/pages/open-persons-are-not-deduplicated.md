opened:: 2026-07-29
status:: open
title:: Nothing finds the same person recorded twice
type:: open-question

- A [[place]] recorded twice is found by `Wekui.Gazetteer.Duplicates`. A [[claim]] told twice is found by `Wekui.Narrative.Duplicates`. **A [[person]] recorded twice is found by nothing at all** — and a person is the only one of the three who is a human being in a memorial.
- **It is not hypothetical.** Looking for something else, one woman was found holding **four Person rows**: `belkys josefina barreto garcia`, `belkis josefina barreto garcia`, `belkys barreto`, `belkis barreto`. The event holds 668 Person rows and **zero exact name collisions**, which is exactly why nothing has noticed: every duplicate here is a near-match, and the only check that exists is exact.
- **What it costs.** A person counted twice is counted twice everywhere downstream — in whatever the record eventually says about how many were missing, and in the [[beat]] a reader meets. It also weakens [[decision-2026-07-29-the-record-knows-who]], which uses Person identity to keep two claims apart: two rows for one woman make her two women to any rule that trusts the rows.
- **The shape of the answer is probably already built twice.** `Wekui.Gazetteer.Duplicates` proposes and never merges, stopping at a judgement no string can make; `Wekui.Curation` records the person's ruling. The name comparison the claim finder needed — **recall over the shorter name's own words**, threshold 0.92 — was calibrated against exactly this data and separates `belkys barreto`/`belkis josefina barreto garcia` (0.944) from `jose luis perez`/`jose luis ramirez` (0.892).
- **What is genuinely unsettled, and why this is a question and not a task.**
  - A merge of two Persons is a heavier act than a merge of two Places: it silently changes who the record says was missing. What the [[curation]] act must carry, and whether it may ever be proposed to a reader rather than only to the operator, is not decided.
  - A handle is derived from the full name, so two rows for one woman can carry two different public handles that have already been shown. Whether merging retires a handle, and what a reader who saw the old one is owed, is not decided.
  - Names in this corpus arrive from posts written by frightened relatives, with spellings that disagree. There is no external authority to check them against, and Person rows are exactly where being wrong is least acceptable.
- Related: [[person]], [[curation]], [[decision-2026-07-29-the-record-knows-who]], [[research-2026-07-29-duplicate-claims-at-scale]], and `docs/mechanisms.md` for the ladder such a question falls down before it reaches a human.
