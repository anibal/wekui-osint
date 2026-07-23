title:: Place Name
type:: concept
status:: built

- A **Place Name** is one string that people actually use for a [[place]]. A Place usually has several, because people rarely agree on one name.
- Each Place Name is described on two separate axes, and neither axis tells us anything about the other:
  - **Kind** — what the string *is*: official, colloquial, alias, acronym, abbreviation, spelling variant, historical, or error.
  - **Emission** — how we are allowed to *use* the string when we go looking for posts:
    - **raw** — we can search for it on its own;
    - **anchored** — we can only search for it next to the names of the Places above it, because on its own it is too common to be useful;
    - **recognition only** — we understand it when we read it, but we never search for it.
- A Place Name also carries a **normalized** form: the same string in lowercase, without accents, with extra spaces removed.
  - We use it to recognise a name when we meet it somewhere else.
  - We always work it out ourselves from the name; it is never supplied from outside.
- Rules
  - Every Place Name must have a name, a kind, and an emission, and must belong to a Place.
  - One Place may carry the same string more than once — for example as both its official and its colloquial name — and each remains a separate Place Name, so that we can tell which one produced which results.
- A Place has a Type; a Place Name has a Kind. They are different things and we never swap the words.
- How names are emitted into requests is defined by [[query-text]]; which names a [[query]] actually carried is recorded on the Query.
