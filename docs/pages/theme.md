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
  - **Applies when** — operationally, **what a [[post]] must assert** for this Theme to apply. Always required. It is the half a name cannot carry, and the reason a Theme is a record rather than a string: a vocabulary of names alone does not stop a reader, human or machine, from stretching a name over evidence that does not bear it — *colapso* was drawn three times from a post that said *"no es nada confirmado"*. Every consumer reads this one sentence: the extractor deciding whether a post fits, the support gate weighing a [[claim]], and whatever renders it. A Theme with no rule is invisible to all three, so there is no way to make one.
  - **Definition** — one sentence saying what the Theme covers, for the person deciding whether to promote it. Optional: it explains, it does not gate.
  - **Nature** — whether the Theme names a **happening** (something that occurred at a moment a [[claim]] can assert — a building came down, a person was pulled out alive) or a **topic** (something a Post is about that no claim follows from — a plea, an opinion, a standing condition like *still trapped*). A claim may only ever carry a happening. Three independent readers of the same corpus applied this split identically to sixteen of their seventeen shared Themes, so it is the corpus's line rather than ours ([[research-2026-07-27-three-readers-one-taxonomy]]).
  - **Status note** — a sentence saying why the Theme is where it is right now. When a Theme is retired, this is where we say why.
  - **Proposed by** — the [[actor]] that suggested this Theme, and, when it was read out of a [[post]], the Post it was inferred from. Recording it is what lets us later ask *how good are we at reading Themes out of Posts*, per Actor. Both are optional, exactly as for a [[place]].
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
- **A rule may be sharpened; a meaning may never drift.** Correcting an imprecise rule is a [[curation]] act, and the act records what it used to say. What must never happen is a Theme quietly coming to mean something else — *a flood that just happened is not a flood two weeks old*, and a rule that shifts under the claims already resting on it is [[principle-never-rewrite-the-record]] failing quietly. A Theme whose meaning has moved is a **new** Theme, and the old one is deprecated onto it ([[decision-2026-07-24-merge-is-deprecation]]). The tree grows; it does not drift.
- Whether a given Post is about a Theme is a separate judgment, and it does not exist yet: it arrives with the judging vocabulary, the same cluster that will answer *where a Post is about* — see [[open-placement]]. Until then a Theme is vocabulary only.
