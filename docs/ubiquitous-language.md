# Ubiquitous Language

This document defines the shared words we use to talk about this system. Each
term means the same thing in conversations, in the code, and in the database.
When we name something here, we use that exact name everywhere.

Words marked **(planned)** are agreed vocabulary that the code has not caught up
with yet. The mark is removed as soon as it is built.

This document describes *what things are*, not how they are stored or computed.
Where a distinction matters to the meaning, it is here; where it is only a
matter of technique, it belongs in the code.

## Event

An **Event** is a single real-world happening that we are studying, such as a
protest, a blackout, or another major occurrence. It is the top-level thing in
the system: every other piece of information belongs to exactly one Event, and
information is never shared between Events.

An Event has:

- **Name** — a short label that identifies the Event. No two Events can have
  the same name.
- **Time zero** — the moment the Event began. We use it as the reference point
  in time for everything we collect about the Event.
- **Goal** — a plain sentence describing what we want to learn or achieve by
  studying this Event.
- **Timezone** — the local timezone of the Event. We store it so that, later,
  we can show times the way people in that place would read them.

Rules:

- Every Event must have a name, a time zero, and a goal.
- Each Event's name is unique across the whole system.
- If no timezone is given, it defaults to `America/Caracas`.

## Actor **(planned)**

An **Actor** is whoever or whatever performed a deliberate act: a **person** or
an **agent**. An agent is a machine worker driven by a model and a prompt.

Wherever this document says that something was approved, proposed, judged or
retired, an Actor did it, and we record which one. We treat people and agents
the same way on purpose: it is the only way to ask, later, *how good is this
agent at this job compared to a person*, and to answer it with evidence rather
than impression.

## Place

A **Place** is a location that matters to one Event: a country, a state, a
town, a neighbourhood, a building. Every Place belongs to exactly one Event.

Places are arranged in a tree. Each Place may have one **parent**, which is the
larger Place that contains it, and any number of **children**. A Place with no
parent is a **root**. Two ways of reading the tree have names of their own:

- a Place's **ancestors** are its parent, its parent's parent, and so on up to
  the root — always listed nearest first;
- a Place's **subtree** is the Place itself together with everything below it.

A Place has:

- **Type** — the Place's Type says what kind of location it is: `pais`,
  `estado`, `municipio`, `parroquia`, `edificio`, and so on. We can invent new
  labels as we need them. Labels are stored lowercase and without accents, so
  one label never turns into two. (A Place has a Type; a Place Name has a Kind.
  They are different things and we never swap the words.)
- **Canonical name** — the name we ourselves use for the Place when we write
  about it.
- **Status note** — a sentence saying why the Place is where it is right now.
  When a Place is retired, this is where we say why.
- **Proposed by** **(planned)** — the Actor that suggested this Place, and,
  when it was inferred from a Post, the Post it was inferred from.

  Places do not only come from people typing them in. A Place can be read out
  of a Post — someone mentions a building, a bridge, a stretch of road that is
  not in our tree yet — and that suggestion becomes a proposed Place. Recording
  who proposed it and what they read it from is what lets us later ask *how
  good are we at reading Places out of Posts*, per Actor, and improve the
  prompt on evidence.

### Lifecycle

A Place moves through named steps, and each step is a deliberate decision by an
Actor:

- **Proposed** — someone or something has suggested this Place, and nobody has
  ruled on it yet. A Search may still collect on it, as long as it names the
  Place explicitly: we do not have to settle whether a Place is real before
  looking to see what people say about it. What we collect under a proposed
  Place is **provisional** — it stands only as long as the Place does.
- **Active** — an Actor has approved it. It is part of the Event's settled
  geography, which is what a Search sweeps when it names no Places at all.
- **Deprecated** — the Place has been retired in favour of another Place, which
  we call its **replacement**.
- **Discarded** — the Place has been retired with no replacement, because it
  was a mistake. A status note is always required.

Rules:

- A Place starts as proposed unless a person creates it active on purpose.
- Only a proposed Place can be promoted to active.
- Only an active Place can be deprecated, and its replacement must be an active
  Place of the same Event, never the Place itself.
- Only a proposed or active Place can be discarded. Deprecated and discarded
  are final.
- A Place's parent must belong to the same Event.
- A Place can never be moved underneath itself or underneath one of its own
  descendants, because that would detach it from the tree.

### Settling a Place we have already collected on **(planned)**

Collecting on a proposed Place is allowed, so the question of what becomes of
that collection has to be answered. Whichever way the Place is settled, no Post
is ever left pointing at a Place that is no longer part of the Event:

- **Promoted** — the Place was real. Everything collected under it stands as it
  is, and nothing needs moving.
- **Deprecated** — the Place turned out to be another Place under a different
  name. Its Posts follow the replacement.
- **Discarded** — the Place was not real. There is no replacement to send its
  Posts to, so the Actor either relocates them to a Place that is real, or they
  return to **Unplaced**: we know we collected them, and we no longer know
  where they are about.

### The Unplaced Place

Every Event has exactly one **Unplaced** Place: the Place where a Post waits
while we still do not know where it is about.

The Event points at its own Unplaced Place directly. That pointer is what makes
it the Unplaced Place — not its name, and not its Type. Anyone can rename a
Place or invent a Type, so a rule that mattered this much could not be left
resting on a word.

The Unplaced Place is never searched on and never counted as part of the
Event's settled geography. It is a waiting room, not a location.

### No place **(planned)**

**Unplaced** and **No place** are two different answers, and we never let one
stand in for the other.

- **Unplaced** — we have not worked out where this Post is about. The question
  is still open and the placement work should carry on.
- **No place** — we looked, and there is no Place this Post is about. The
  question is closed. It is an answer, not an absence of one.

The distinction is the whole point: an Actor that has examined a Post and
genuinely concluded "this is about nowhere" must be able to say so, instead of
being pushed into **Unplaced** because that is the only word available. If the
two collapse into one, we can never tell *not yet examined* from *examined and
empty*, and we cannot measure how well any Actor does the placing.

**No place** is not a Place. It is a recorded answer about a Post, and it is
defined properly alongside the rest of the judging vocabulary.

## Place Name

A **Place Name** is one string that people actually use for a Place. A Place
usually has several, because people rarely agree on one name.

Each Place Name is described on two separate axes, and neither axis tells us
anything about the other:

- **Kind** — what the string *is*: official, colloquial, alias, acronym,
  abbreviation, spelling variant, historical, or error.
- **Emission** — how we are allowed to *use* the string when we go looking for
  posts:
  - **raw** — we can search for it on its own;
  - **anchored** — we can only search for it next to the names of the Places
    above it, because on its own it is too common to be useful;
  - **recognition only** — we understand it when we read it, but we never
    search for it.

A Place Name also carries a **normalized** form: the same string in lowercase,
without accents, with extra spaces removed. We use it to recognise a name when
we meet it somewhere else. We always work it out ourselves from the name; it is
never supplied from outside.

Rules:

- Every Place Name must have a name, a kind, and an emission, and must belong
  to a Place.
- One Place may carry the same string more than once — for example as both its
  official and its colloquial name — and each remains a separate Place Name, so
  that we can tell which one produced which results.

## Search

A **Search** is one Actor's stated intention to go and collect posts: *these
Places, over this stretch of time, optionally about these words.* It belongs to
exactly one Event.

A Search is not itself a request to X. It is the plan from which many small,
exact requests are worked out. Those requests are Queries.

A Search has:

- **Name** — a short label. No two Searches of the same Event share a name. We
  do not create a second Search to change our mind about the first; we extend
  the one we have.
- **Intent** — a plain sentence saying what we are trying to collect and why.
  We write it down so that later we can hold the intention up against what
  actually came back.
- **Window** — the stretch of time we want to cover, from its **window start**
  to its **window end**. A Search with no window end is **open**: it keeps
  covering time as time passes.
- **Slice length** — a long window cannot be asked for in one request, because
  X returns only so much at a time. So we cut the window into consecutive
  **slices** of this length and ask about one slice at a time. The slice length
  is remembered on the Search, so that working the plan out again produces
  exactly the same Queries. If none is given, it is ten minutes.

  Slices are always whole, which means the last one reaches a little past the
  window end when the window is not a whole number of slices long. This is
  deliberate: it keeps the slices anchored to a grid that never moves, so
  pushing the window end out later only ever *adds* slices. A slice we have
  already asked about never turns into a different, longer one, and no two
  Queries ever ask about overlapping stretches of time.
- **Result mode** — how we want X to choose what to return:
  - **latest** — everything it has for that slice, newest first. Only this mode
    can be treated as complete coverage of the slice.
  - **top** — a selection X considers most relevant. Useful for sampling, never
    counted as complete.
- **Scope** — the Places this Search covers.

  Naming Places explicitly says *collect on exactly these*, and they may be
  proposed as well as active: collecting is often how we find out whether a
  proposed Place was real. An **empty** Scope says *collect on the Event's
  settled geography* — every active Place, decided at the moment the plan is
  worked out, and never anything merely proposed.

  Either way the Unplaced Place is never searched, and a Place that has been
  deprecated or discarded is never searched.
- **Terms** — the words the Search is about. See **Search Term** below. A
  Search with no Terms is a **base sweep**: it asks about the Places alone.
- **Status note** — a sentence saying why the Search is where it is right now.

### Lifecycle

- **Draft** — being written. This is the only step in which the plan can be
  changed, because Queries in draft have never been asked and can be thrown
  away and worked out again freely.
- **Ready** — an Actor has approved the plan. It is now fixed.
- **Active** — collecting. This is the only step in which Queries are actually
  asked of X.
- **Paused** — deliberately held, and resumable.
- **Closed** — finished. This is final.

Rules:

- A Search starts as draft.
- Only a draft Search can be edited, and only a draft Search's plan can be
  worked out again.
- Only a ready or paused Search can be made active. We remember when it first
  became active, and when it was closed.
- Only an active Search can be paused.
- Any Search that is not already closed can be closed. Closed is final.

### Extending

Once a Search has left draft its plan is fixed, but the world is not. To grow a
Search we **extend** it, along one dimension at a time: add a Place, add a
Term, or push the window end further out. Extending only ever *adds* Queries;
it never rewrites or removes the ones already there, so nothing we have already
collected is put in doubt.

**Open, to be settled by observation:** whether **latest** simply extends
**top** — that is, whether asking in latest mode over a window returns
everything asking in top mode would have. A first measurement over two real
windows found latest returned 97.5% and 99.3% of what top returned, and a great
deal besides — but not quite all of it, and the two runs did not use the same
slice length, so this is a first indication and not a rule. The reciprocal is
clearly false: top misses most of what latest finds. Until we know better, we
treat the two modes as complementary and count coverage only from latest.

## Search Term

A **Search Term** is one word or phrase that a Search asks about, together with
the **language** it is written in. A Search may carry several, or none at all.

Terms narrow a Search from *everything said about these Places* to *what was
said about these Places concerning these words*.

## Query

A **Query** is one exact question actually asked of X: **one Place, one slice,
one exact request**. It is the atom of collection. A Search is worked out into
many Queries; every post we hold arrived through one of them.

A Query is both the plan and the record of what happened, in one place:

- **Query text** — the exact request as sent. See below.
- **Slice** — the stretch of time it asks about, from its **slice start** up to
  but not including its **slice end**.
- **Place** — the one Place it asks about.
- **Intent** — a plain sentence saying what this particular question is for.
  Together with the Search's Intent it lets us compare what we meant to find
  with what we found.
- **Posts found** and **posts new** — how many posts the Query returned, and
  how many of those we had not already seen. A Query that ran before we started
  counting has neither: something unknown is never written down as zero.
- **Status note** — a sentence saying why the Query is where it is right now.
  When we give up on a Query, this is where we say why.

Rules:

- One Search never asks the same question twice: within a Search, the Query
  text is unique.

### The state of a Query

A Query is always in exactly one of these:

- **In plan review** — its Search is still draft, so it is a proposal, not yet
  a question we intend to ask.
- **Queued** — approved and waiting to be asked.
- **Running or interrupted** — we started asking and have not finished.
- **Completed** — we finished asking. What it returned is what it returned.
- **Discarded** — we gave up on it, and the status note says why.

### Which names and terms a Query carried

A Query records exactly which **Place Names** it emitted and which **Search
Terms** it carried. This is how we can later say *this name variant brought in
those posts, that one brought in none* and curate on evidence rather than
opinion.

## Query Text

The **Query text** is the exact request as sent to X, written in one settled
way so that the same coordinates always produce the same request, character for
character.

It is built from:

- the **location group** — the Place's emittable names, any one of which will
  do. A name that is *anchored* instead appears next to the names of the Places
  above it, so that a common word is never asked about on its own.
- the **event group** — the Search's Terms, any one of which will do. A base
  sweep has no event group.
- the **slice** it covers and the **result mode** it asks for.

X limits how many pieces one request may contain. When a Place has more names
than will fit alongside the Terms, its names are split across several Queries
rather than quietly dropped: we would rather ask twice than lose a name.

Country names never serve as qualifiers. *Palmar, in Venezuela* matches almost
any post that happens to mention both, whereas *Palmar, in Caraballeda* means
what it says. So an anchored name is qualified by its state, municipality and
parish, and never by its country. If the country is all it has, it emits
nothing at all — asking a question we cannot trust the answer to is worse than
not asking.

## Decomposition

**Decomposition** is the act of working a Search out into its Queries: take the
Scope, cut the window into slices, and for each Place and each slice build the
Query text and the record of which names and terms it carried.

It is a calculation, not a decision: given the same Search it always produces
the same Queries, character for character. That is what makes a draft plan
disposable — we can throw it away and work it out again, and get the same plan
back.

## Coverage

**Coverage** answers *what have we actually asked?* A slice of a Place is
covered when a Query for it completed in **latest** mode. A Query that was
asked in top mode, or discarded, or never finished, covers nothing.

## Post

A **Post** is one message published on X that we have collected. It belongs to
exactly one Event: the same message collected while studying two different
Events is two Posts, because nothing is ever shared between Events.

A Post is a record of what we found, not an opinion about it. It says what
someone published and what we saw when we first collected it. We never edit it
and we never throw it away.

A Post has:

- **X id** — the identifier X itself gives the message. It is what makes a Post
  the same Post.
- **Text** — what the message says.
- **Posted at** — the moment X says the message was published.
- **Author** — the account that published it.
- **Payload** — everything X told us about the message, kept exactly as it
  arrived. Everything above is read out of it. We keep it whole because we can
  never ask for it again: a message we collected last week cannot be fetched
  again as it was last week. Keeping it is what lets us read something new out
  of a Post later without going back to X.

Rules:

- Every Post belongs to exactly one Event, and so does its Author.
- Within an Event, no two Posts share an X id.
- Every Post has an Author. A message on X always comes from an account; there
  is no such thing as one without.
- A Post is never edited and never deleted.

A Post does not say where it is about. Working that out is a judgment, and it
arrives with the judging vocabulary — see **Still open**.

## Author

An **Author** is the account that published a Post. It belongs to exactly one
Event: the same account seen while studying two Events is two Authors.

An Author has:

- **X id** — the identifier X gives the account. It is what makes an Author the
  same Author.
- **Handle** — the name people type to reach the account, the one that starts
  with an @.
- **Display name** — the name the account shows.

Rules:

- Every Author belongs to exactly one Event.
- Within an Event, no two Authors share an X id.
- We record an account as it was the first time we saw it. If someone renames
  themselves afterwards we do not chase the change: the Posts we already hold
  should keep saying what the account was called when they were published.

How many followers an account has, and whether it is verified, are deliberately
not here — see **Settled by observation**.

## Appearance

An **Appearance** records that one Query found one Post. It is how a Query's
results land, and it is our only account of *which question brought us what*.

Most Posts are found once. Many are found again — a later Query covering an
overlapping stretch of time, or a Query about a different Place whose names the
same message happens to mention, returns something we already hold. That second
finding is not a second Post. It is a second Appearance of the same Post, and
recording it is how we can later say *this question found nothing we did not
already have*.

A Post's **first** Appearance is the Query that first found it. We do not write
that down anywhere else; the first Appearance is the answer.

Rules:

- An Appearance belongs to exactly one Post and one Query, and both belong to
  the same Event.
- One Query never records the same Post twice. Asking a Query again finds the
  same Posts and changes nothing.
- Every Post has at least one Appearance: a Post exists because a Query found
  it.

---

## Settled by observation

**A Search Term has no off-switch.** The old design let a Term be marked
unusable so a noisy word could be silenced without deleting it and losing the
explanation for what it had already brought in. It was never needed: across
twelve real Searches, 556 Queries and 13,248 posts in the old app, not a single
Search Term was ever created — every real Search was a base sweep. With no
Terms there are no noisy Terms. A Term we no longer want is removed while the
Search is still a draft. If a real Term ever earns an off-switch, it can have
one then.

**An Appearance carries no engagement of its own.** The old design recorded the
likes and reposts seen *at each finding*, so that every re-finding of a Post
would be a measurement of how that message was gaining traction. Across 20,611
real Appearances of 13,248 Posts it did not pay for itself: of the findings
after the first, 83.5% held numbers identical to the Post's own and 4.7% held
nothing at all, so only 4.2% of all Appearances carried anything new — by an
average of a tenth of a like, and never by more than 24. An Appearance says
which Query found the Post, and that is all it says. If watching engagement move
ever becomes a goal, it has to be collected on purpose rather than hoped for as
a side effect of re-finding.

**A folded string cannot tell us that two Posts are saying the same thing.** The
old design kept the folded text and treated it as the way to notice repetition,
and reports grouped Posts by its first 120 characters. Held against 13,248 real
Posts, matching the fold exactly finds 189 of them — 1.4%. The prefix trick
finds more, but not for the reason anyone intended: in almost every group it
produced, the only difference between the members was a trailing link or a block
of hashtags. It was never a way of recognising similarity. It was an accidental
and badly calibrated way of removing links, and removing them deliberately beats
it at every cutoff. So a Post carries no folded copy of its own text. Whether
two Posts say the same thing is its own question, answered where that question
is asked — see **Still open**. Recognising a Place Name inside a Post is a
different job again, a matching one, and the folding it needs is worked out when
the match is run, against the Post's text as it stands. Neither is a standing
property of the Post, so neither is written onto it.

**Engagement stays in the Payload.** The old design lifted the like and repost
counts out onto the Post so that reports could read them without opening the
Payload. Exactly two readers ever used them — the timeline and the evidence
report — and both did the same thing: add the two numbers together into a single
score, in memory, after the rows had already come back. Neither ever filtered or
sorted on them in the database, and both fetched the Payload in the very same
query, so the lifted-out copies saved no work whatsoever. Views, replies, quotes
and bookmarks were never lifted out at all, and were never missed. How much
attention a message got stays where it arrives, and earns a name of its own on
the day something needs to rank or filter by it in the database.

**How many followers an account has is not a fact about the account.** The old
design kept a follower count on the Author, taken the first time we saw them and
never refreshed afterwards. Held against the number X supplied with each
individual Post, it disagreed on 34.8% of 13,248 Posts, by an average of 84
followers and by as much as 26,825. A number that moves every day is a fact
about a moment, not about an account, so it stays in the Payload where each Post
carries the number that was true when we collected it. Whether an account is
verified was kept the same way, and is left out for the same reason.

**The Query that first found a Post is not written down.** The old design kept a
pointer from every Post to the Query that discovered it. In 13,248 Posts out of
13,248 it was exactly the Query of that Post's first Appearance. Two names for
one fact is one name too many.

**A Post is always the message itself.** Not one of 13,248 collected messages
was a bare repost of another one. X resolves reposts before we ever see them, so
there is no wrapper to see through and nothing to strip out.

**The default slice length is ten minutes.** Worth remembering what actually
ran, though: the twelve real Searches used one hour, two hours, four hours, one
day and one week. Ten minutes is six times finer than the finest slice ever
used, so it produces roughly six times as many Queries for the same window.
Every Search may set its own, and this is only what happens when none is given.

## Still open

1. **Actor** is vocabulary so far, not a thing in the system. It is wired when
   we reach the judging concepts, where agents become real and there is
   something to compare.
2. **Placement** — the answer to *where is this Post about* — does not exist
   yet. Working it out is a judgment, so it arrives with the judging
   vocabulary, and until then a Post points at no Place at all. **No place**,
   **Proposed by**, and what becomes of the Posts collected under a Place that
   is later settled all wait on it: they are three answers to a question we
   cannot yet ask. The **Unplaced** Place is built and still waiting for
   something to hold.
3. **Whether a Query's state should also be written down.** It is read from the
   timestamps and the Search's step, which is the meaning; keeping a copy for
   speed is a separate, later decision that changes nothing here.
4. **Which further facts should be lifted out of the Payload.** A Post's
   language, whether it is a reply, whether it quotes another message, whether
   it carries pictures or video, and how much attention it got are all in the
   Payload already, and nothing reads any of them yet. Each earns a name of its
   own on the day something needs to ask about it in bulk, and not before.
5. **When two Posts are saying the same thing.** There is no word for this yet,
   and we should not invent one before we know what it has to mean. What we do
   have is the shape of the problem, measured across 13,248 real Posts. Cleaning
   a Post's text of links, mentions and hashtags before comparing finds 876
   Posts repeated word for word — 6.7%, nearly five times what the plain fold
   finds. Past that the ground softens: around 18% of Posts have a near-twin
   sharing most of their wording, and 58% have no lexical neighbour at all and
   are simply one person's one report.

   Two questions are hiding inside this one. *Is this the same message posted
   twice* is a matter of cleaning text and comparing it. *Are these two people
   telling us about the same happening* is not, and no amount of string work
   reaches it. They want separate names and separate answers, and they get them
   when something needs them.

   Whatever we build has to survive one thing we already know about this corpus:
   981 Posts, 7.4% of them, share the same missing-person wording and differ
   only in the name of the person who is missing. They read as near-identical
   and they mean opposite things. A rule that quietly merges them is worse than
   no rule at all.
