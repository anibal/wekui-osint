decided:: 2026-07-23
evidence:: [[research-2026-07-23-old-app-corpus]]
status:: settled
title:: How many followers an account has is not a fact about the account
type:: decision

- **Decision** — an [[author]] carries no follower count and no verified flag; both stay in each [[post]]'s Payload.
- The old design kept a follower count on the Author, taken the first time we saw them and never refreshed afterwards.
- Held against the number X supplied with each individual Post, it disagreed on 34.8% of 13,248 Posts, by an average of 84 followers and by as much as 26,825.
- A number that moves every day is a fact about a moment, not about an account, so it stays in the Payload where each Post carries the number that was true when we collected it.
- Whether an account is verified was kept the same way, and is left out for the same reason.
