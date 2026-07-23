status:: built
title:: Theme
type:: concept

- A **Theme** is a label for what a [[post]] is about — a subject that matters to one [[event]]. Themes are the Event's **What axis**. Every Theme belongs to exactly one Event.
- A Theme borrows the shape of a [[place]] — the same tree, the same lifecycle, the same status note — but drops the name layer and the Type: a Theme is only ever a display label, never a string we emit to X or match against a Post, so it has no [[place-name]] beneath it.
- Themes are arranged in a tree. Each Theme may have one **parent**, the broader Theme that contains it, and any number of **children**. A Theme with no parent is a **root**.
  - a Theme's **ancestors** are its parent, its parent's parent, and so on up to the root — always listed nearest first;
  - a Theme's **subtree** is the Theme itself together with everything below it.
- A Theme has:
  - **Name** — the display label people read: never folded, never emitted, never matched.
  - **Status note** — a sentence saying why the Theme is where it is right now. When a Theme is retired, this is where we say why.
  - **Proposed by** #planned — the [[actor]] that suggested this Theme, and, when it was read out of a [[post]], the Post it was inferred from. Recording it is what lets us later ask *how good are we at reading Themes out of Posts*, per Actor. Deferred exactly as it is for a [[place]].
- Lifecycle — a Theme moves through the same named steps as a [[place]], and each step is a deliberate decision by an [[actor]]:
  - **Proposed** — someone or something has suggested this Theme, and nobody has ruled on it yet.
  - **Active** — an Actor has approved it. It is part of the Event's settled What axis: the labels a Post can be judged to be about.
  - **Deprecated** — the Theme has been retired in favour of another Theme, which we call its **replacement**.
  - **Discarded** — the Theme has been retired with no replacement, because it was a mistake. A status note is always required.
- Rules
  - A Theme starts as proposed unless a person creates it active on purpose.
  - Only a proposed Theme can be promoted to active.
  - Only an active Theme can be deprecated, and its replacement must be an active Theme of the same Event, never the Theme itself.
  - Only a proposed or active Theme can be discarded. Deprecated and discarded are final.
  - A Theme's parent must belong to the same Event.
  - A Theme can never be moved underneath itself or one of its own descendants.
- Whether a given Post is about a Theme is a separate judgment, and it does not exist yet: it arrives with the judging vocabulary, the same cluster that will answer *where a Post is about* — see [[open-placement]]. Until then a Theme is vocabulary only.
