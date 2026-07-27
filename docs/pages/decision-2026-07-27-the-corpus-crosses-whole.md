decided:: 2026-07-27
status:: settled
title:: Decision — the corpus crosses whole, and the rehearsal nine stand
type:: decision

- Porting the old app's [[post]]s into this record carries the **payload X sent, unaltered**, and reads `text` out of it. The old app's `normalized_text` — lowercased and accent-folded for matching — is never the text of a Post, and its `place_judgments` are never carried at all: they choose *which* posts to bring, and nothing more. Placement here is a [[claim]]'s property, resolved fresh from what the posts say.
- **What the port found, and this decision settles.** The nine posts the record has been standing on since 2026-07-25 are a **rehearsal corpus, not collected posts**: their `x_id` is the old app's row id (`"129"`), not the X post id (`"2070003831404908894"`), and their text is a cleaned rendering — no emoji, no `|` separator, no `t.co` URL, line breaks flattened. Every measurement of extraction so far was taken on tidied prose.
- **They stay as they are.** A Post is never edited and never deleted, and eight [[claim]]s and nineteen [[curation]] acts already rest on them. The port therefore SKIPS a post the record holds under its row id, so the nine are not doubled, and the real corpus arrives beside them under true X ids. The wart is real and named: a future live acquisition would collect those same nine messages again, under their true ids, as new Posts.
- **What this makes measurable.** The extraction prompt was tuned on the clean nine; the corpus is not clean. Whether v5 survives emoji, separators, trailing URLs and line breaks is now an experiment the record can run rather than a hope — and it is the first thing that reaches the prompts, which no ruling had touched until now.
- Evidence: `priv/scripts/port_corpus.exs`, and the 98 posts it brought into the 2026-06-25 04:00–05:00 hour beside the 2 rehearsal posts it skipped.
- Related: [[open-extraction-does-not-batch]], which bounds how much of the corpus can cross at once.
