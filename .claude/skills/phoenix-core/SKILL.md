---
name: phoenix-core
description: "Use when working on the Phoenix router, controllers, plugs, raw Ecto, or general Elixir and Mix questions outside the Ash domain layer."
---

Read the file matching your task — these are the rules for the exact versions
this project has installed:

- `deps/phoenix/usage-rules/phoenix.md` — router scopes/aliases, controllers.
- `deps/phoenix/usage-rules/elixir.md` — Elixir language gotchas, OTP
  primitives, Mix task habits.
- `deps/phoenix/usage-rules/ecto.md` — raw Ecto. Rarely needed here: domain
  data goes through Ash (see the `ash-framework` skill); reach for this only
  for repo internals, seeds, or reading generated migrations.

To search docs:

```sh
mix usage_rules.search_docs "search term" -p phoenix -p ecto -p ecto_sql
```
