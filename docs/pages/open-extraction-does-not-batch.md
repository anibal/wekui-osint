opened:: 2026-07-27
status:: open
title:: Extraction reads the whole corpus in one prompt
type:: open-question

- `Wekui.Pipelines.Extract.run/4` renders **every [[post]] it is given into a single `{{material}}` block** and makes one call. The [[run]]'s preflight hands it `Capture.list_posts!(event_id)` — the event's *entire* corpus, deliberately, so that "the beat's own interval does the scoping" and no claim is lost for falling outside a render window.
- That was right for nine posts. It does not survive a real corpus: the Caraballeda subtree of the old app holds **6,982** posts, and asking one model call to read all of them and answer in one JSON object is neither payable nor trustworthy.
- So the bound sits in the wrong place today — in `priv/scripts/port_corpus.exs`, which ports a window rather than the corpus. That is a stopgap and it is written down as one: the record is being kept small to fit the pipeline, which is backwards.
- What has to be decided before the rest of the corpus crosses:
  - **How a batch is chosen.** By time is the obvious axis and matches how the beat already reads; by place is the other. Neither is free — a happening told across a batch boundary becomes two [[claim]]s, which is the merge question ([[open-when-two-posts-say-the-same-thing]]) arriving through the back door.
  - **What `{{prior}}` carries between batches.** The prompt already has the slot. Feeding batch *n*'s claims into batch *n+1* is what would stop the boundary from splitting a happening — and is untested.
  - **Which posts a batch may contain.** [[decision-2026-07-26-extract-once-per-event]] made the re-run rule binary on *has this event any claim*, having measured that citation coverage mis-fires. A growing corpus needs a third answer — *these posts have never been read* — and the receipt is the only honest place that could live, because a post the extractor read and correctly dropped must never be re-read.
- Until then the read path can still be aimed by hand: `posts:` overrides the scope and `extract: :force` overrides the skip, so a deliberate, named batch is expressible. Nothing automatic is.
- Related: [[decision-2026-07-27-the-corpus-crosses-whole]], [[run]], [[claim]].
