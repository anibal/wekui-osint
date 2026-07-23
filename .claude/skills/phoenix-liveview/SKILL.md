---
name: phoenix-liveview
description: "Use when writing or changing Phoenix LiveView modules: mount/handle_event, streams, JS hooks and interop, navigation, forms in LiveViews, or LiveView tests."
---

Read `deps/phoenix/usage-rules/liveview.md` — the LiveView rules for the
exact version this project has installed — and follow it. It covers streams,
colocated vs. external JS hooks, navigation, form handling, and testing with
`Phoenix.LiveViewTest`/`LazyHTML`.

The non-negotiable project rules (Layouts.app wrapper, hooks, streams, no raw
scripts) are in `.claude/rules/web.md`; this reference explains the mechanics.

To search LiveView docs:

```sh
mix usage_rules.search_docs "search term" -p phoenix_live_view
```
