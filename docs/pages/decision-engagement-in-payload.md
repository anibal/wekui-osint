title:: Engagement stays in the Payload
type:: decision
status:: settled
evidence:: [[research-old-app-corpus]]

- **Decision** — how much attention a message got stays in the [[post]]'s Payload, where it arrives; nothing is lifted out onto the Post.
- The old design lifted the like and repost counts out onto the Post so that reports could read them without opening the Payload.
- Exactly two readers ever used them — the timeline and the evidence report — and both did the same thing: add the two numbers together into a single score, in memory, after the rows had already come back.
- Neither ever filtered or sorted on them in the database, and both fetched the Payload in the very same query, so the lifted-out copies saved no work whatsoever.
- Views, replies, quotes and bookmarks were never lifted out at all, and were never missed.
- Engagement earns a name of its own on the day something needs to rank or filter by it in the database — see [[open-payload-facts]].
