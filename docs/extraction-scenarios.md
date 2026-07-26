# The Extractor — scenarios for validation

**The extractor's job:** from a batch of relevance-accepted [[post]]s (a place × window),
produce **[[claim]]s** — structured accounts of state-changes — each citing the Posts that
evidence it. Not one claim per post; **one claim per happening**, told by role and never by
name. This doc proposes the behaviour through **real posts from the old corpus** so you can
validate it line by line before we build the prompt. Markers: **[PROPOSAL]** my
recommendation · **[OPEN]** needs your call.

Each scenario shows the real input (post id + text, lightly trimmed) → the Claim(s) I'd
extract. A Claim is written as `{kind · subject · place · when · magnitude · status ·
confidence · cites}`.

---

## A. One happening, many posts → ONE claim
**Input** (2 of **78** posts about the same rescue):
- `3914` [06-29 08:47] "…continúan con las labores de búsqueda y rescate de **Aaron Levi Cantillo Vargas, de 21 años**, quien permanece atrapado entre los escombros…"
- `3920` [06-29 07:33] "El Presidente **@nayibbukele** indica que los equipos salvadoreños… trabajan para sacar con vida a **Aaron Levi Cantillo Vargas, de 21 años**… en el edificio **OPP 25**…"

**→ Claim** `{ rescate · "un hombre de 21 años" · Edificio OPP 25 (Tanaguarena) · first_seen 06-29 07:33 · {horas: ~106} · rescatado · 0.95 · cites: [3914, 3920, …78] }`

- The name **Aaron Levi Cantillo Vargas** → role `"un hombre de 21 años"`. **@nayibbukele** (head of state, public) *may* be named, but as a claim's `subject` he isn't relevant — he's the source, derivable from the citation. 78 posts, one row.

## B. The specificity trap — same template, DIFFERENT people → separate claims
**Input:**
- `79` [06-25 03:54] "Se solicita información sobre **Julio Josué Freitas Rodríguez**, visto por última vez en las cercanías de Caraballeda…"
- `49` [06-25 03:01] "**Julio Josue Freitas Rodríguez** su última ubicación fue cerca de Caraballeda… vecino… de Valencia…"
- `129` [06-25 04:39] "Se busca a **Damarys Melo**… maestra de la C.E. Corapal… Residía en el piso 9 de **Residencias Caribe**, edificio que colapsó…"
- `76` [06-25 04:02] "También desaparecidas en **Residencias Caribe**… **Yaneth Tejera y Shaznay Mirabal**. Son la suegra y sobrina…"

**→ Claims (THREE, not one, not four):**
- `{ desaparición · "un hombre, vecino de Valencia" · Caraballeda (parroquia) · 06-25 03:01 · — · desaparecido · 0.8 · cites: [49, 79] }` — posts 49 & 79 are the **same person** → one claim.
- `{ desaparición · "una maestra" · Residencias Caribe · 06-25 04:39 · {piso: 9} · desaparecido · 0.75 · cites: [129] }`
- `{ desaparición · "dos mujeres (una suegra y su sobrina)" · Residencias Caribe · 06-25 04:02 · — · desaparecido · 0.7 · cites: [76] }`

- **129 and 76 are both in Residencias Caribe** — place does not separate them; the **attributes** (a teacher on floor 9 vs. a mother-in-law and niece) do. A merge on place or on the shared "desaparecida" wording would be the 981-post error. **[OPEN]** is "dos mujeres" one claim or two? I lean **one** (they're reported together, as a pair) — your call.

## C. Role, never name — even a named child
**Input:** `1568` [06-27 18:13] "…el rescate de **Moisés, un niño de 11 años** que permanecía atrapado entre los escombros en Caraballeda…"
**→ Claim** `{ rescate · "un niño de 11 años" · Caraballeda · 06-27 18:13 · — · rescatado · 0.9 · cites: [1568] }` — **Moisés** → role. Age, outcome, place kept.

## D. A public figure's private relative — the subtle one
**Input:** `1335` [06-27 11:23] "La pianista venezolana **Gabriela Montero**… relató que **su padre** fue rescatado por un amigo… tras quedar atrapado en la zona de Caraballeda…"
**→ Claim** `{ rescate · "un hombre" · Caraballeda · 06-27 11:23 · — · rescatado · 0.75 · cites: [1335] }`
- **[PROPOSAL]** Gabriela Montero is a public figure and *nameable in general* — but here naming her **identifies her father**, a private individual. So the claim **drops the Montero link entirely**. Rule: *a public figure is not named when doing so identifies a private person.* This is a person-gate nuance the extractor must respect and the gate can't catch (Montero is on the allowlist).

## E. One post → MORE than one claim
**Input:** `1526` [06-27 19:17] "Una mujer fue rescatada hoy en Caraballeda… participaron integrantes del equipo **USAR El Salvador**. Aún no hay noticias de **Lucas, el chico de 9 años**, buscado en La Guaira."
**→ Two Claims:**
- `{ rescate · "una mujer" · Caraballeda · 06-27 19:17 · — · rescatada · 0.85 · cites: [1526] }`
- `{ desaparición · "un niño de 9 años" · La Guaira · 06-27 19:17 · — · desaparecido · 0.8 · cites: [1526] }`
- So the extractor emits **0..N claims per post**. **USAR El Salvador** (a brigade) may be named; **Lucas** → role.

## F. Official figures → a cifra claim (no person subject)
**Input:** `4746` [07-01] "🚨 BALANCE AL 1 DE JULIO… El reporte oficial actualizado al 30 de junio registra **1.943 fallecidos y 10.571 heridos**…"
**→ Claim** `{ cifra_oficial · (no subject) · La Guaira (estado) · 07-01 · {fallecidos: 1943, heridos: 10571} · — · 0.9 · cites: [4746] }` — an official toll: no person subject, the magnitude is the fact, place is the state.

## G. Aid / official response
**Input:** `650` [06-25 23:46] "…despliegue total para rescatar, atender y reconstruir tras los sismos 📍 La Guaira. …el ministro del Poder Popular…"
**→ Claim** `{ ayuda · "el gobierno nacional" · La Guaira · 06-25 23:46 · — · en curso · 0.6 · cites: [650] }` — officials/institutions acting publicly may be named. **[OPEN]** how much of this generic "response" chatter is worth a claim at all vs. noise — a threshold question.

## H. Uncorroborated plea → a claim of its source, low confidence
**Input:** `13074` "Todavia tenemos esperanzas! Ayúdennos a regar la voz! **Edif RocaPark**, La Guaira."
**→ Claim** `{ reporte_vecinal · "posibles sobrevivientes reportados por vecinos" · Edificio RocaPark · … · — · en curso · 0.4 · cites: [13074] }` — a single-source plea: stated **as a report, not as fact**, low confidence. More independent authors would raise it.

## I. Noise → NO claim
**Input:** `4745` "@danigfk2 Creo que era mas o menos Media alta, habían edificios con su piscina y con vista al mar espectacular… la parte de clase alta…"
**→ nothing.** Real-estate chatter carries no state-change. *Null is the correct answer.* (This is the post that leaked into the old narrative as a fabricated "affected zones" list — the redesign's whole point.)

---

## J. Person naming — DECIDED (a public-posts memorial, built for human connection)

**Decision (operator).** These are **public X posts**, and the whole point is a story people
can **connect** with. An opaque hash/UUID is the *worst* option — cold, rejected by real
readers, gutting the value of the effort. A person is shown by **first name + last-name
initial + role, subject to availability** — a heuristic ladder with an **escape hatch**.
Aaron → **"Aaron C., un hombre de 21 años."** This **supersedes** the "no name, ever" line in
`claim.md` and the current person gate; both evolve to it (below). The schemes, exercised on
Aaron:

| # | Scheme | Aaron's subject (displayed) | Reads | Disambiguates? | Dignity / safety |
|---|---|---|---|---|---|
| V0 | Role only | "un hombre de 21 años" | sober | no — many clash | safest |
| V1 | First name | "Aaron, un hombre de 21 años" | informal | weakly | leaks a given name |
| V2 | First + initial | "Aaron C., un hombre de 21 años" | odd | better | leaks name **and** a surname initial — *more* identifying than V1 |
| V3 | Initials | "A.C.V., un hombre de 21 años" | cold | some | identifying with age + place |
| V4 | **Role display + opaque handle** | "un hombre de 21 años" (internal identity `person⟨a7f3⟩`, never shown) | sober | **yes, fully** | **safest — no name ships** |

**Chosen: first name + surname initial + role (V2-style), for connection.** The "safest" V4
(hash/handle) is rejected — a memorial that refers to the dead and missing by codes is one no
one connects with; the source is public and the goal is human connection, so we show a name,
carefully, behind a gate. (V3 initials and V1 bare-first-name remain the ladder's *fallbacks*
when a full name isn't available.)

**The availability ladder** — the extractor derives a *display handle*; uncertain → escape hatch:

| What the posts give | Display handle | Example |
|---|---|---|
| First name + ≥1 surname | **first name + surname initial** | "Aaron Levi Cantillo Vargas" → **"Aaron C."** |
| First name only | first name (flagged lower-confidence) | "Aaron" → **"Aaron"** |
| Surname / title only | — → **escape hatch** | "Sr. Freitas" → role only + flag |
| Nickname / mononym / @handle | — → **escape hatch** | "El Catire" → role only + flag |
| No name | role only | → **"un hombre de 21 años"** |
| Ambiguous parse (compound given names, particles "de la…", foreign) | — → **escape hatch** | role only + flag |

Display form: `"<handle>, <role>"` — "Aaron C., un hombre de 21 años"; role-only when there is
no handle.

**The escape hatch (you asked for it).** Any case the ladder can't confidently resolve ships
**role-only + a `pending-person-review` flag**; a human assigns/confirms the handle through
the gate. The pipeline never *guesses* a name — uncertain defaults to role + flag. F54's
discipline survives: a mechanical gate plus a human backstop, now with a richer allowed target
(approved handles), not "no name ever."

**Identity & the arc.** The underlying **full name** (folded) is the match key and lives on a
**Person**, stored **behind the human gate** — so we *store* the name (not hash-only), because
we both display a name-derived form and match on it. Posts naming the same person → same
Person → their claims **link** into an arc (your decision-2 lean, agreed): *"Aaron C., un
hombre de 21 años, quedó atrapado en el OPP 25; 106 horas después fue rescatado con vida."*

**Do-the-right-thing safeguards (kept — your own framing).** A Person carries a **publish /
withhold** state (operator-owned) and a **mandatory human gate**: no person-status claim
(trapped / rescued / missing / dead) is public until a human approves the Person. That is what
lets us show names *and* do right by them.

**What this puts in scope (all doc-first, your review):**
- `claim.md`'s "named by no claim, ever" → **"by an approved display handle, through the human
  gate."**
- The person gate (`NoPrivateName`) → **allows an approved Person handle**, still refuses a
  raw / unapproved name.
- The deferred **Person write-path** (`open-actor` / the vision's "blocked person entities") is
  now the design we are doing — with the gate + withhold the vision required.
- **Kids → still always role**, no handle even internally. [your call]

---

## The cross-cutting decisions I need your guidance on

1. **[OPEN] Dedup boundary — within-batch vs. the merge-judge.** [PROPOSAL] the extractor
   dedups **within its batch** (one claim per happening it sees, as in A); the separate
   **merge-judge** reconciles **across** batches/place-scopes (the 78 OPP-25 posts span many
   batches). So extraction is "one batch → deduped claims," merge is "claims → fewer claims."
   Note from Operator: Agreed. Merge is as little claims as possible, but enough to accommodate the posts.
   
2. **[OPEN] Status threading — disappearance → outcome.** Julio is `desaparecido` on day 1.
   If later rescued/found dead, is that a **status transition on the same claim** (my lean —
   the person's fate is one claim, `desaparecido → hallado/fallecido`) or a **new linked
   claim**? The first is truer to the model but harder to match; worth deciding before we
   build, because it shapes the merge-judge.
   Note from Operator: This is a really interesting and powerful take,a narrative arc for named entities. I tend to think in terms of linked, connected claims.
   
3. **[OPEN] Place mapping.** A claim's `place` is a gazetteer id. [PROPOSAL] map to the most
   specific **existing active** Place; an unmatched or ambiguous mention → **Unplaced** plus a
   human-gated place proposal (this is where **Tavily** location-assist earns its keep).
   Note from Operator: Agreed and I think this will be particularly useful and justified for edifications and landmarks.
   
4. **[OPEN] Confidence & corroboration.** [PROPOSAL] confidence rises with **independent
   authors** corroborating within the batch; a single source is phrased as a report
   ("vecinos reportan…", scenario H) and scored low. Copy-paste of one text counts as one
   source, not many.
   Note from Operator: Agreed. Scoring/confidence is not trivial.
   
6. **[OPEN] The `kind` vocabulary.** These scenarios used `rescate · desaparición · colapso ·
   cifra_oficial · ayuda · reporte_vecinal`. Is that the right starting set? (It's a plain
   string today — easy to change; worth settling before the prompt hard-codes examples.)
   Note from Operator: Yes, totally, you are o the right track

**How to give feedback:** mark up any scenario (a wrong claim shape, a missed/extra claim, a
naming call), and answer the five decisions. Then I'll draft the extraction prompt from the
*validated* behaviour — designed against these, not ported from `extraction.v2`.
