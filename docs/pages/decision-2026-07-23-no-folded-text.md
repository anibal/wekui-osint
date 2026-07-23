decided:: 2026-07-23
evidence:: [[research-2026-07-23-old-app-corpus]]
status:: settled
title:: A Post carries no folded copy of its own text
type:: decision

- **Decision** — a [[post]] carries no folded copy of its own text, because a folded string cannot tell us that two Posts are saying the same thing.
- The old design kept the folded text and treated it as the way to notice repetition, and reports grouped Posts by its first 120 characters.
- Held against 13,248 real Posts, matching the fold exactly finds 189 of them — 1.4%.
- The prefix trick finds more, but not for the reason anyone intended: in almost every group it produced, the only difference between the members was a trailing link or a block of hashtags.
  - It was never a way of recognising similarity. It was an accidental and badly calibrated way of removing links, and removing them deliberately beats it at every cutoff.
- Whether two Posts say the same thing is its own question, answered where that question is asked — see [[open-when-two-posts-say-the-same-thing]].
- Recognising a [[place-name]] inside a Post is a different job again, a matching one, and the folding it needs is worked out when the match is run, against the Post's text as it stands.
- Neither is a standing property of the Post, so neither is written onto it.
- Full measurements: [[research-2026-07-23-clustering-spike]].
