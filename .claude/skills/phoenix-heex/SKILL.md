---
name: phoenix-heex
description: "Use when writing or changing HEEx templates or function components: interpolation syntax, class lists, conditionals, comments, forms and inputs."
---

Read `deps/phoenix/usage-rules/html.md` — the HEEx/template rules for the
exact version this project has installed — and follow it. It covers `{...}`
vs `<%= %>` interpolation, class list syntax, `phx-no-curly-interpolation`,
comprehensions, comments, and building forms with `to_form/2` + `<.input>`.

To search Phoenix.Component / HTML docs:

```sh
mix usage_rules.search_docs "search term" -p phoenix_html -p phoenix_live_view
```
