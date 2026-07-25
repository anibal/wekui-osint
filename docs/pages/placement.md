status:: built
title:: Placement
type:: concept

- **Placement** is an [[actor]]'s answer to *where is this [[post]] about*: it points a Post at a [[place]]. It is one kind of [[judgment]] — append-only and superseding, carrying its Actor and, for an agent, a confidence.
- The slot is the **Post**: a Post is about one where at a time, so it has at most one current placement. Re-judging supersedes the earlier one.
- The Place judged must be a [[place]] of the same [[event]] as the Post.
- A Post does not store where it is about; its where is always read from its current placement, following one chain:
  - a current placement whose Place is **proposed or active** → that Place;
  - a current placement whose Place has been **deprecated** → the Place's replacement, followed onwards if that Place was itself deprecated — see [[settling-a-collected-place]];
  - a current placement whose Place has been **discarded** with no replacement → **Unplaced**;
  - no current placement but a current **No place** answer → [[no-place]];
  - nothing judged at all → the [[unplaced-place]]: we collected the Post and have not worked out where it is about.
- Settling a Place therefore never rewrites a placement: the Post keeps the placement it was given, and what that placement *means* is resolved when we read it — see [[settling-a-collected-place]].
- **No place (examined-empty)** — an Actor that has examined a Post and concluded it is about nowhere records [[no-place]], the examined-empty answer for where. It is never the same as **Unplaced**: Unplaced is *not yet worked out*, No place is *worked out, and the answer is nowhere*.
  - No place and a real placement are two answers to the same where question, so a Post has at most one of the two current at once: a placement landing closes a current No place, and a No place closes a current placement.
- Placement is what the [[unplaced-place]] was always waiting to hold.
