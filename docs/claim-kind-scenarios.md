# The kind of happening — a vocabulary the record holds, not three private guesses

*Written 2026-07-27, after the extractor read real posts for the first time and
asserted things they do not say in 12 of 26 claims.*

Markers: **[PROPOSAL]** = my recommendation, overrule in a word. **[OPEN]** = I need
your answer. **[MEASURED]** = counted, not argued.

---

## 1. The defect is not rigidity. It is that the vocabulary does not exist.

The operator's reading was that a Claim has a vocabulary that is *too rigid*, so posts
get fitted into it for want of an alternative. The conclusion is right. The mechanism is
the opposite, and the opposite matters.

`Claim.kind` is `attribute :kind, :string` with **no constraint of any sort**. Any string
is a valid kind. Nothing in the system can refuse one.

What exists instead is **three private, mutually inconsistent guesses** at a vocabulary,
one inside each thing that consumes it:

| consumer | its private vocabulary | what it does with a kind outside it |
|---|---|---|
| `prompts/extraction.v*.txt` | 7 examples in a sentence, "there is no fixed list" | writes any string; nothing refuses it |
| `prompts/support.v1.txt` | **none at all** | refuses kinds that are perfectly valid |
| `Narrative.BeatRenderer` | 5 regex families (`cifra`, `colaps`, `búsqueda`, `fallec`, `rescat`) | `"#{kind}: #{subject}"` — a debug dump, into the memorial |

**And here is the inversion.** An open free-text field makes *"this does not fit"*
inexpressible. If every string is a valid kind, the model can never answer "none of these
applies", because there is no **these**. So it does the only thing available: it names what
it saw with the nearest word from the examples. `búsqueda` is the nearest word to a family
asking after someone. Having committed to a search, it then fills `status: desaparecido`,
because a search implies someone missing.

*Closing the vocabulary is what creates the possibility of refusal.* The field is not too
tight. It is too loose to fail.

## 2. [MEASURED] What the free string has already cost

**Twenty of the twenty-one support-gate refusals are type errors.** Not one is a magnitude
error. One is a place error. The gate has been reporting a missing vocabulary in every
sentence, and it was read as a wording problem:

- "The post asks for information about a person, but does not state that a `búsqueda` (search) occurred" — ×16
- "does not state `colapso` as a specific event type … only an unconfirmed report" — ×2
- "only says photos were sent of the building, not that there is a report of structural damage" — ×1
- "The evidence does not state that a claim about the building is being made" — ×1, **and this one refused a kind the extractor had just invented correctly.** The judge has no vocabulary either.

**The vocabulary over-splits about two to one.** 17 distinct kinds hold 67 claims:

- one concept written five ways — `solicitud de información sobre` *desaparecidos* / *edificio* / *desaparecida* / *familiares* / *persona* (14 claims)
- one written two ways — `daño estructural` / `reporte de daño estructural`
- a **status leaking into the kind** — `rescate` vs `rescate en curso`; `personas atrapadas` (atrapado is a status)

**The damage reaches the reader.** Because the renderer cannot know what it is rendering,
the memorial's Spanish now contains:

```
solicitud de información sobre edificio: [20][21]
personas atrapadas: personas atrapadas[53]
daño estructural: [50]
los equipos trabajaron para rescatar con vida a [51]
```

That is not prose. It is a field name, a colon, and sometimes nothing at all, in a public
memorial. Every one of those is the `generic_clause` fallback firing on a kind no consumer
was told about.

## 3. The system already holds the answer, at zero rows

`Wekui.Taxonomy.Theme` is a **per-Event controlled vocabulary**: a tree, `proposed → active
→ deprecated → discarded`, a status note, and `proposed_by` naming the Actor and the Post it
was read out of. Promote, deprecate, discard and reparent are all built and green.

There are **zero Themes**. The machinery for a governed vocabulary was built, and the thing
that needed it shipped as a free string.

`docs/pages/claim.md` even flags the seam: *"how a claim's kind relates to the What axis of
themes is a seam still to settle."* It was settled by default, and the corpus has now priced
the default.

A Theme is what a **Post** is about. A kind is what **happened**. Different axes — so this is
a sibling of Theme, borrowing its shape, exactly as Theme borrowed Place's.

## 4. [PROPOSAL] The shape

### 4.1 A kind is a record, with a definition

Not a string, and not a name alone. **A name alone fixes half the defect.** It would not have
stopped `colapso` from hearsay the post itself disowned. A kind carries:

- **name** — the Spanish a beat may say and a claim may carry.
- **what it means** — one sentence.
- **what the evidence must assert for it to apply** — its *precondition*. This is the half that
  fixes the over-assertion class. `colapso`: the post asserts the building came down as fact,
  not as an unconfirmed report. `búsqueda`: the post asserts a search effort is under way.
  `solicitud de información`: the post asks for information about a person or a place.
- **what it must not be confused with** — the nearest kind, and the line between them. Written
  from the pair that got confused.
- **its cases** — real posts, positive and negative. See 4.3.
- **lifecycle** — `proposed → active`, with promotion a [[curation]] act: attributed, reasoned,
  append-only. Already built.

The precondition is the thing the support gate is *already* trying to check, from an empty
vocabulary. Written once, it is read by the extractor, the gate, and the renderer. **One
definition, three consumers, no private guesses.**

### 4.2 A run leaves two things, and every post is accounted for

Extraction returns claims **and a residue**: the posts that fit no active kind, each with a
one-line reason. Then, in code and with no model involved:

```
batch = cited ∪ unfitted ∪ dropped
```

checked, and in the receipt. Today a post that fits nothing is either forced into a claim or
vanishes silently, and neither is auditable. This is pure determinism and it makes the residue
an object instead of a silence.

### 4.3 A proposed kind is born with its tests, and the tests are real posts

The operator's sharpest point, with one correction.

He proposed testing a new kind against "scenarios derived from the posts that didn't fit".
Right instinct — **but scenarios synthesised by a model and judged by a model are a closed
loop that can be confidently wrong.** There are 6,982 real posts. Use them.

A proposed kind arrives with cases drawn from the residue:

- **positive** — posts this kind should claim.
- **negative** — posts that look like it and are not. These are worth more. The negative case
  for `colapso` is the "no es nada confirmado" post; the negative case for `búsqueda` is a
  family asking.

The negatives become fixtures in the test suite. **That is the piece my last three prompt
edits did not have**: a rule that lives only as English inside a prompt is protected by
nothing, and the next reword deletes it silently.

### 4.4 [PROPOSAL] Propose from clusters, never from a single post

One kind proposed per misfit post would industrialise the over-splitting already measured —
five spellings of one request. So the proposal pass runs over the **accumulated residue**,
clusters it first, and proposes a kind per cluster. A kind proposed by one post is noise; a
kind the corpus asks for forty times is the corpus telling us something.

Clustering is deterministic and already written: `Gazetteer.Duplicates` and
`Narrative.Duplicates` do folded-string closeness today.

**Not every misfit deserves a kind.** A prayer, an opinion, a joke evidences nothing. The
residue is allowed to stay a residue, and that is a correct outcome, not a backlog.

### 4.5 Where the machine decides, and where the code does

| decision | who | why |
|---|---|---|
| does this post evidence a happening of an **active** kind | LLM | entailment — irreducible |
| **may a claim carry this kind** | **code** | the kind must be `active`; an Ash validation refuses otherwise |
| what happens to a post that fits nothing | **code** | it goes to the residue. Forcing is not expressible |
| is every post in the batch accounted for | **code** | conservation check in the receipt |
| propose a name and a definition for a cluster | LLM | naming — irreducible |
| are two proposed kinds the same kind | **code first** | folded-string closeness, already built |
| does a proposed kind join the vocabulary | **the operator**, as a curation act | already built |
| does a kind's definition still hold after a prompt edit | **code** | its negative cases run in `mix test` |

The model is used exactly twice, and both times as a **proposer**, never as an authority —
the same posture `PlaceResolver` already takes when it proposes a finer place under a known
ancestor rather than guessing one.

### 4.6 [PROPOSAL] Bootstrap from the record, not from an LLM

Do not invent the first vocabulary, and do not ask a model to invent it. **Mine it from the
67 claims already held.** 17 strings, folded and clustered by code that exists, collapse to
roughly seven candidates. Free, deterministic, and drawn from what the corpus has already
shown. The operator blesses a list once — one decision, not sixty-seven.

## 5. What this changes about the queue on the record now

Most of the 21 flagged claims name kinds the record never had. Withdrawing the v5 run is
still right, but for a better reason than "the prompt was bad". And the re-read should wait
until the vocabulary exists, so that what comes back can be gated instead of judged after
the fact.

## 6. [OPEN] What I need answered

1. **Is a kind a sibling of Theme, or is it Theme?** I say sibling: a Theme is what a Post is
   about, a kind is what happened, and one post about rescues can evidence a collapse. If they
   are one thing, the seam in `claim.md` closes differently and the tree is shared.
2. **Where does it live** — `Wekui.Taxonomy` beside Theme and AuthorTag (vocabulary), or
   `Wekui.Narrative` beside Claim (the thing that carries it)? I say Taxonomy.
3. **Does a claim of a non-active kind refuse, or draft as proposed?** I say **refuse**, and
   the post goes to the residue. Drafting against an unblessed kind is the current defect with
   extra steps.
4. **Does the vocabulary have a tree**, as Theme and Place do? `solicitud de información` with
   children `sobre persona` / `sobre edificio` would have collapsed the five-way split by
   construction. I say yes, and a claim carries the finest active kind.
5. **The name.** `ClaimKind`? `Happening`? The docs say "kind" already, and the ubiquitous
   language is the contract.
