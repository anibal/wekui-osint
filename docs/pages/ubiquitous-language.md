title:: Ubiquitous Language
type:: hub

- This is the shared vocabulary of the system: each term means the same thing in conversations, in the code, and in the database. When we name something here, we use that exact name everywhere.
- Every concept has a page of its own, holding its definition, its attributes, its lifecycle, and its rules together. This hub only names them.
- These pages describe *what things are*, not how they are stored or computed. Where a distinction matters to the meaning, it is on the page; where it is only a matter of technique, it belongs in the code.
- Concepts
  - [[event]] — a single real-world happening we are studying; the top-level thing, and nothing is ever shared between Events.
  - [[actor]] #planned — whoever or whatever performed a deliberate act: a person or an agent.
  - [[place]] — a location that matters to one Event; Places form a tree and move through proposed → active → deprecated / discarded.
  - [[unplaced-place]] — the one Place per Event where a Post waits while we still do not know where it is about.
  - [[no-place]] #planned — the recorded answer *this Post is about nowhere*; never confused with Unplaced.
  - [[place-name]] — one string people actually use for a Place, described by a Kind and an Emission.
  - [[search]] — one Actor's stated intention to collect: these Places, over this stretch of time, optionally about these words.
  - [[search-term]] — one word or phrase a Search asks about, together with its language.
  - [[query]] — one exact question actually asked of X: one Place, one slice, one exact request; the atom of collection.
  - [[query-text]] — the exact request as sent, written in one settled way.
  - [[decomposition]] — working a Search out into its Queries; a calculation, not a decision.
  - [[coverage]] — what have we actually asked; counted only from completed latest-mode Queries.
  - [[post]] — one message published on X that we have collected; never edited, never deleted.
  - [[author]] — the account that published a Post, recorded as it was when we first saw it.
  - [[appearance]] — the record that one Query found one Post.
  - [[theme]] — a label for what a Post is about; the Event's What axis, a Place-shaped tree without the name layer.
  - [[author-tag]] — a label for what an Author is; the Event's Who axis, flat, open, and multi-label.
- Policies
  - [[settling-a-collected-place]] #planned — what becomes of the Posts collected under a Place that is later settled.
- The rest of the documentation — principles, strategy, architecture, the decision log, open questions, research — is mapped from [[index]].
