title:: Post
type:: concept
status:: built

- A **Post** is one message published on X that we have collected.
- It belongs to exactly one [[event]]: the same message collected while studying two different Events is two Posts, because nothing is ever shared between Events.
- A Post is a record of what we found, not an opinion about it. It says what someone published and what we saw when we first collected it. We never edit it and we never throw it away.
- A Post has:
  - **X id** — the identifier X itself gives the message. It is what makes a Post the same Post.
  - **Text** — what the message says.
  - **Posted at** — the moment X says the message was published.
  - **Author** — the account that published it — see [[author]].
  - **Payload** — everything X told us about the message, kept exactly as it arrived. Everything above is read out of it.
    - We keep it whole because we can never ask for it again: a message we collected last week cannot be fetched again as it was last week.
    - Keeping it is what lets us read something new out of a Post later without going back to X.
- Rules
  - Every Post belongs to exactly one Event, and so does its Author.
  - Within an Event, no two Posts share an X id.
  - Every Post has an Author. A message on X always comes from an account; there is no such thing as one without.
  - A Post is never edited and never deleted.
- A Post does not say where it is about. Working that out is a judgment, and it arrives with the judging vocabulary — see [[open-placement]].
- A Post exists because a Query found it; every finding is recorded as an [[appearance]].
- What a Post deliberately does not carry:
  - no folded copy of its own text — see [[decision-no-folded-text]];
  - no engagement lifted out of the Payload — see [[decision-engagement-in-payload]];
  - no pointer to the Query that first found it — see [[decision-first-query]];
  - no repost wrapper to see through — see [[decision-post-is-the-message]].
