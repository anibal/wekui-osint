status:: built
title:: Place
type:: concept

- A **Place** is a location that matters to one [[event]]: a country, a state, a town, a neighbourhood, a building. Every Place belongs to exactly one Event.
- Places are arranged in a tree. Each Place may have one **parent**, which is the larger Place that contains it, and any number of **children**. A Place with no parent is a **root**.
- Two ways of reading the tree have names of their own:
  - a Place's **ancestors** are its parent, its parent's parent, and so on up to the root — always listed nearest first;
  - a Place's **subtree** is the Place itself together with everything below it.
- A Place has:
  - **Type** — the Place's Type says what kind of location it is: `pais`, `estado`, `municipio`, `parroquia`, `edificio`, and so on. We can invent new labels as we need them. Labels are stored lowercase and without accents, so one label never turns into two.
    - A Place has a Type; a [[place-name]] has a Kind. They are different things and we never swap the words.
  - **Canonical name** — the name we ourselves use for the Place when we write about it.
  - **Status note** — a sentence saying why the Place is where it is right now. When a Place is retired, this is where we say why.
  - **Proposed by** #planned — the [[actor]] that suggested this Place, and, when it was inferred from a [[post]], the Post it was inferred from.
    - Places do not only come from people typing them in. A Place can be read out of a Post — someone mentions a building, a bridge, a stretch of road that is not in our tree yet — and that suggestion becomes a proposed Place.
    - Recording who proposed it and what they read it from is what lets us later ask *how good are we at reading Places out of Posts*, per Actor, and improve the prompt on evidence.
- Lifecycle — a Place moves through named steps, and each step is a deliberate decision by an [[actor]]:
  - **Proposed** — someone or something has suggested this Place, and nobody has ruled on it yet.
    - A [[search]] may still collect on it, as long as it names the Place explicitly: we do not have to settle whether a Place is real before looking to see what people say about it.
    - What we collect under a proposed Place is **provisional** — it stands only as long as the Place does.
  - **Active** — an Actor has approved it. It is part of the Event's settled geography, which is what a [[search]] sweeps when it names no Places at all.
  - **Deprecated** — the Place has been retired in favour of another Place, which we call its **replacement**.
  - **Discarded** — the Place has been retired with no replacement, because it was a mistake. A status note is always required.
- Rules
  - A Place starts as proposed unless a person creates it active on purpose.
  - Only a proposed Place can be promoted to active.
  - Only an active Place can be deprecated, and its replacement must be an active Place of the same Event, never the Place itself.
  - Only a proposed or active Place can be discarded. Deprecated and discarded are final.
  - A Place's parent must belong to the same Event.
  - A Place can never be moved underneath itself or underneath one of its own descendants, because that would detach it from the tree.
- What becomes of the Posts collected under a Place that is later settled: [[settling-a-collected-place]] #planned
- Every Event has one special Place that is not part of its geography: [[unplaced-place]].
- **Unplaced** is not the same answer as **No place** — see [[no-place]].
