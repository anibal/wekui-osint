---
paths: ["lib/wekui_web/**", "assets/**"]
---

# Web layer conventions

The rules below are the ones agents demonstrably get wrong without a reminder
(measured in our behavioral A/B), plus this project's design decisions. For
full framework reference, use the `phoenix-liveview` and `phoenix-heex` skills.

## Rules that fail without this file

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>`
  wrapping all inner content.
- Any `phx-hook` element needs a unique DOM `id`; when the hook manages its own
  DOM, **always** also set `phx-update="ignore"`.
- **Never** write raw `<script>` tags in HEEx. Inline scripts must be colocated
  hooks — `<script :type={Phoenix.LiveView.ColocatedHook} name=".MyHook">`,
  names **must** start with a `.` — or live in `assets/js/` and be registered
  with the `LiveSocket` constructor.
- Collections in LiveViews use **streams** (`stream/3` +
  `phx-update="stream"` and a DOM id on the parent), never plain list assigns.
  Streams are not enumerable: to filter or refresh, re-fetch and re-stream with
  `reset: true`. Details and edge cases: `phoenix-liveview` skill.
- Forms use the imported `<.input>` component, driven by a `to_form/2` assign
  (`@form[:field]`, never the changeset in the template). Forms, buttons, and
  other key elements get unique DOM ids — tests select by id.
- Icons: the imported `<.icon name="hero-..."/>` component, **never**
  `Heroicons` modules or inline SVG copies.

## Design decisions

- Hand-written Tailwind components; **no daisyUI**, for a unique design.
- Tailwind v4: keep the `@import "tailwindcss" source(none)` + `@source` block
  in `app.css` as-is; there is no `tailwind.config.js`; **never** use `@apply`.
- Only the `app.js` / `app.css` bundles are served — import vendor deps there;
  no external `src`/`href` script or style tags in layouts.
- Design bar: polished and responsive, clean typography and spacing, subtle
  micro-interactions (hover, transitions, loading states) — premium, not busy.
