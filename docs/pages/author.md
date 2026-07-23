title:: Author
type:: concept
status:: built

- An **Author** is the account that published a [[post]]. It belongs to exactly one [[event]]: the same account seen while studying two Events is two Authors.
- An Author has:
  - **X id** — the identifier X gives the account. It is what makes an Author the same Author.
  - **Handle** — the name people type to reach the account, the one that starts with an @.
  - **Display name** — the name the account shows.
- Rules
  - Every Author belongs to exactly one Event.
  - Within an Event, no two Authors share an X id.
  - We record an account as it was the first time we saw it. If someone renames themselves afterwards we do not chase the change: the Posts we already hold should keep saying what the account was called when they were published.
- How many followers an account has, and whether it is verified, are deliberately not here — see [[decision-follower-count]].
