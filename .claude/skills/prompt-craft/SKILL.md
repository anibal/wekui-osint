---
name: prompt-craft
description: Use when writing or revising an LLM prompt for wekui (extraction, judgment, rendering, discovery) run on a small model — first principles and heuristics for judgment-based, safety-critical prompts, distilled from the extraction v1→v5 iteration.
---

Worked reference: `prompts/extraction.v1.txt` → `.v5.txt` (v5 is locked). Read v5
for the register to write in — terse, imperative, dense. Generalizes past
extraction to any prompt here (merge-judge, entailment gate, beat-renderer,
discovery), all run on the same small, fast, non-deterministic production model
(DeepSeek-Flash via DeepInfra).

## First principles

- Judgment vs. absolutes is a deliberate split, not one style for both: open
  vocabulary + a judgment test for classification (`kind`, "is this a happening");
  zero-conditional absolutes for safety lines (no name, ever).
- A complex conditional on a safety line IS the leak. "Name a public figure UNLESS
  it identifies a relative" is what produced "el padre de la pianista Gabriela
  Montero." Fix: delete the exception, don't warn about it.
- Judgment is safe only when inputs are pinned. A judgment-heavy prompt without
  its `{{material}}` anchor made the model hallucinate instead of extract — every
  judgment prompt needs, beside its source data: this is the only source; cite
  only these ids; never invent a post/name/place/number/id.
- Open the field where the world is open-ended (`kind` — a closed enum silently
  dropped deaths into "otro"); keep it closed where downstream code branches on it
  (`status` — gates and write-path key off a small fixed set). Same prompt, both
  calls correct.
- Two fields describing adjacent dimensions of one thing (`kind`, `status`) need
  an explicit independence statement plus one worked disambiguating case, or the
  small model collapses them — it read "rescate" in the text and emitted
  `status: rescatado` until told "rescate names the operation, not the outcome."
- A scope/filter parameter (`{{place_scope}}`) must never leak into an extracted
  field. State explicitly: the field holds what the post itself names, even if
  broader or narrower than the batch's scope — never substitute one for the
  other, or the model echoes your query back as data.
- Recall-first extraction, precision via downstream gates: don't tune the prompt
  for 100% precision, it costs recall on the highest-stakes content. Let it
  over-extract marginal cases at low confidence with self-labeling; human review +
  a mechanical write-path gate + a confidence filter buy back precision. The
  mechanical gate is the real backstop, not the prompt.
- Separate identity from display in the schema, not in prose: a shown role field
  vs. a protected raw names array dissolved the naming red-line structurally.
- Small models weight local salience — a rule stated once, far from the field it
  governs, gets dropped. Put each rule beside the thing it governs.
- Non-determinism is a system property, not a bug (MoE routing, same input varies
  run to run). Design for it — self-labeling, confidence, downstream filters —
  don't chase a wording that made one run look clean.

## Heuristics

- Lead with the 2–3 inviolable rules up front, before the schema.
- Discrete confidence ladder tied to concrete evidence shapes (single vague plea =
  0.4 … official or 2+ independent authors = 0.9), not a bare "0 to 1, how sure."
- A *test* beats an enumerated list for a fuzzy category: "what happened, and
  when — if you can't name both, no claim" catches non-events you didn't
  anticipate; a noise-list only catches the ones you listed.
- Carve out legitimate derivation from a "no invention" rule explicitly — "invent
  no number" blocked deriving elapsed-hours from t0 until named as permitted.
- Give plural room with one empty sentinel: an array that's always an array
  (`[]`, never `null`) beats a singular field once reality sometimes gives a pair.
- Define the vague qualifiers you use in-prompt ("strongest first" needs its own
  line: most specific and direct; ties break to earliest time).
- One concrete example of the rare, high-risk shape, not just the common one — a
  happening hidden inside another post's happening; "el padre de Montero → un
  hombre" as the worked safety-line case.
- A safety line is principle + the why + one example, never a mechanical
  conditional — it must survive paraphrase and judgment mode.
- Cue the easy-to-drop edge explicitly ("named only in passing still counts")
  or a secondary person/happening silently vanishes.
- Prune, don't accrete. v3 was shorter than v2 and fixed a red-line v2 missed —
  retire a rule once a simpler, stronger one covers it.
- Spell out output hygiene (one JSON object, no fence, enum values verbatim) and
  don't trust it — the model still fences sometimes and stringifies numeric ids,
  so the parser must be lenient regardless.

## Pre-ship checklist

- [ ] Have a strong model role-play the prompt's role and list weaknesses first —
      cheap, caught 8 issues in one pass — but treat it as a filter, not a
      clearance: it missed the Montero red-line entirely.
- [ ] Then run on the real production model. The strong-model pass will not
      surface failures specific to the small model — those only show up live.
- [ ] Run the identical input N≥3 times and diff the outputs — MoE
      non-determinism means one clean run proves nothing.
- [ ] Grep for every `{{placeholder}}` and confirm each interpolates in the
      harness — a missing `{{material}}` caused the hallucination bug, not wording.
- [ ] Replay every known red-line / adversarial input after every edit, forever —
      regressions on safety lines are otherwise silent.
- [ ] Confirm the parser strips fences even when the model ignores "no fence,"
      and coerces stringified numeric ids.
- [ ] Confirm low-confidence / self-labeled output is actually consumed
      downstream — the escape hatch only works if something reads `confidence`.
- [ ] For every closed enum: a slot for the highest-stakes case? For every
      "invent no X": the legitimate derivations carved out?
- [ ] Diff net length against the prior version. If it only grew, find the rule
      the new one should have replaced.

## Anti-patterns

- The `UNLESS` on a safety line — the exception clause is the leak.
- A closed enum with no slot for the worst case — fails silently on the input you
  most need captured.
- A noise-list standing in for a test — always misses the case you didn't list.
- Two adjacent fields with no independence statement — the model collapses them.
- A scope parameter with no "don't substitute it" rule — it echoes back as data.
- Forcing the prompt to 100% precision — a recall tax on the rarest, highest-
  stakes content; precision is a downstream job.
- A rule stated once, far from its field — a structural bug, not a wording one.
- Judgment expanded without a tightened, adjacent anchor — room to judge becomes
  room to invent.
