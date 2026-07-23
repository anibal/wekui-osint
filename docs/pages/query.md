title:: Query
type:: concept
status:: built

- A **Query** is one exact question actually asked of X: **one Place, one slice, one exact request**. It is the atom of collection.
- A [[search]] is worked out into many Queries — see [[decomposition]] — and every post we hold arrived through one of them.
- A Query is both the plan and the record of what happened, in one place:
  - **Query text** — the exact request as sent — see [[query-text]].
  - **Slice** — the stretch of time it asks about, from its **slice start** up to but not including its **slice end**.
  - **Place** — the one [[place]] it asks about.
  - **Intent** — a plain sentence saying what this particular question is for. Together with the Search's Intent it lets us compare what we meant to find with what we found.
  - **Posts found** and **posts new** — how many posts the Query returned, and how many of those we had not already seen.
    - A Query that ran before we started counting has neither: something unknown is never written down as zero.
  - **Status note** — a sentence saying why the Query is where it is right now. When we give up on a Query, this is where we say why.
- Rules
  - One Search never asks the same question twice: within a Search, the Query text is unique.
- The state of a Query — a Query is always in exactly one of these:
  - **In plan review** — its Search is still draft, so it is a proposal, not yet a question we intend to ask.
  - **Queued** — approved and waiting to be asked.
  - **Running or interrupted** — we started asking and have not finished.
  - **Completed** — we finished asking. What it returned is what it returned.
  - **Discarded** — we gave up on it, and the status note says why.
  - Whether this state should also be written down, rather than read from timestamps and the Search's step, is open — see [[open-query-state]].
- Which names and terms a Query carried
  - A Query records exactly which Place Names it emitted and which Search Terms it carried — see [[place-name]] and [[search-term]].
  - This is how we can later say *this name variant brought in those posts, that one brought in none* and curate on evidence rather than opinion.
- What a Query found lands as Appearances — see [[appearance]].
