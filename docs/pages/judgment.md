status:: built
title:: Judgment
type:: concept

- A **judgment** is an [[actor]]'s answer about a [[post]] or an [[author]]. Wherever this vocabulary says a Post was placed or classified, or an Author was tagged, a judgment recorded it — and it always names the Actor who made it.
- Every judgment belongs to one [[event]], like everything else: the Post or Author it is about, the label or [[place]] it points at, and the Actor who made it all belong to the same Event, and a judgment reaching across Events is the same mistake as any other crossing.
- Judgments are append-only. We never edit an answer and we never delete one; the whole record of what was answered, by whom, stays.
- Re-judging **supersedes**: when a new answer is given where one already stood, the earlier answer is closed and the new one takes its place. At most one answer is **current** at a time for the same question about the same thing, and the closed answers remain as its history.
  - What counts as "the same question about the same thing" — the **slot** — depends on the judgment. A Post has at most one current [[placement]]; a Post may carry any number of current [[theme-judgment]]s at once, but at most one for each [[theme]].
- **Retraction** closes an answer with no successor: the Actor withdraws it and the question goes back to unanswered. It is how we say "that no longer holds" without asserting anything new in its place.
- A judgment carries its **provenance** — the Actor who made it — and, when that Actor is an **agent**, a **confidence**: how sure the agent is, from 0 to 1.
  - A **person**'s judgment carries no confidence; a person does not report a probability. Confidence belongs to agents alone — an agent judgment always has one, a person judgment never does.
  - Recording provenance is what lets us ask, within an Event, how well an agent answers a question compared to a person, and to answer it with evidence.
- **Examined-empty** — a judgment can answer *nothing*. An Actor that has looked and found no answer records that it looked and the answer is empty, which is a different fact from never having asked. We call such an answer a **none-judgment**.
  - A none-judgment supersedes and is superseded like any other, against the real answer to the same question: a real answer landing closes the current none-judgment, and a none-judgment closes the current real answer. The two are never both current.
  - Its named case is [[no-place]] (examined for where, the answer is nowhere); the examined-empty answers for [[theme-judgment]] and [[author-tag-judgment]] carry no proper name of their own.
- Being collected is not a judgment: a Post we hold carries no answer about it, and an Author none, until an Actor makes one. Absence of a judgment is handled by each judgment on its own page — for where it is the [[unplaced-place]], for themes it is unclassified.
- The judgments we make: [[theme-judgment]] (what a Post is about), [[author-tag-judgment]] (what an Author is), and [[placement]] (where a Post is about).
- A judgment obeys two of the system's principles: [[principle-never-rewrite-the-record]] — we supersede and retract, we never edit an answer — and [[principle-unknown-is-never-zero]] — examined-empty is not the same as never asked.
