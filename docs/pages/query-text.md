title:: Query Text
type:: concept
status:: built

- The **Query text** is the exact request as sent to X, written in one settled way so that the same coordinates always produce the same request, character for character.
- It is built from:
  - the **location group** — the [[place]]'s emittable names, any one of which will do.
    - A name that is *anchored* instead appears next to the names of the Places above it, so that a common word is never asked about on its own — see [[place-name]].
  - the **event group** — the [[search]]'s Terms, any one of which will do. A base sweep has no event group.
  - the **slice** it covers and the **result mode** it asks for.
- X limits how many pieces one request may contain. When a Place has more names than will fit alongside the Terms, its names are split across several Queries rather than quietly dropped: we would rather ask twice than lose a name.
- Country names never serve as qualifiers.
  - *Palmar, in Venezuela* matches almost any post that happens to mention both, whereas *Palmar, in Caraballeda* means what it says.
  - So an anchored name is qualified by its state, municipality and parish, and never by its country.
  - If the country is all it has, it emits nothing at all — asking a question we cannot trust the answer to is worse than not asking.
