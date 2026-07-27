measured:: 2026-07-27
status:: settled
title:: Research — extraction on real posts, and the two things it invents
type:: research

- The extractor had only ever read the nine rehearsal posts ([[decision-2026-07-27-the-corpus-crosses-whole]]). On 2026-07-27 it read real ones for the first time — three batches from the same hour of 2026-06-25, one per prompt version, each judged by the support gate.
- **v5 asserted things the posts do not say, in 12 of 26 claims.** Two failure modes, both from the same root: the corpus is mostly relatives ASKING, and v5 read every question as a report.
  - *A plea became a confirmed disappearance.* "Se solicita información sobre María Fernanda Rey Rujano… se encontraba en los edificios Costa Brava" became `búsqueda / una persona / desaparecido`. So did "¿Saben algo de ella?" and — with no person named anywhere in the post — "alguien tiene información sobre residencias albatros".
  - *Hearsay the post itself disowned became two collapses.* "algunas publicaciones que dicen que… **no es nada confirmado!** Un edificio roca azul que se cayó y las residencias caribe dicen lo mismo" became two separate `colapso` claims.
  - This is the dangerous class: the memorial would have manufactured missing persons and fallen buildings out of families asking after them.
- **v6 wrote the two rules and both held.** A question is not a report; unconfirmed is not confirmed. Every plea came back with `status: null`, and no collapse was drawn from disowned hearsay again. But v6 also drafted 13 claims from 22 posts against v5's 26 from 26 — it went quiet rather than wrong, and the gate still refused 5, on a new and sharper ground: the extractor called a plea `búsqueda`, and the judge answered that **asking is not searching**.
- **v7 settled that by naming the happening for what the post DID, not for what it hopes for.** A family posting a plea is `una solicitud de información`, not `una búsqueda` — a búsqueda is rescuers searching, and nobody said that was under way. Claim volume came back and the refusals collapsed.

- The three readings, each on its own batch from the hour of 2026-06-25 04:00:
  - **v5** — 26 posts, 26 claims: 13 supported, 12 unsupported, 1 overstated. **46% refused**, 0.50 supported claims per post.
  - **v6** — 22 posts, 13 claims: 8 supported, 5 unsupported. 38% refused, 0.36 supported claims per post — quieter, not better.
  - **v7** — 22 posts, 20 claims: 17 supported, 3 unsupported. **15% refused**, **0.77** supported claims per post.

- **The honest caveat:** three different batches of posts, not one batch three times. Same hour, same corpus, same character — but this measures the prompts on comparable material, not on identical material. A controlled re-read of one batch would need the first reading retracted, which is a person's call.
- **What v7 invented, and what it puts to the operator.** Given permission to name the plea, the model produced a family of kinds on its own: `solicitud de información sobre desaparecidos`, `sobre edificio`, `sobre familiares`, `sobre persona`, and `solicitud de equipos de rescate y maquinaria`. The gate accepted almost all of them. **The most common happening in this corpus is a family asking, and until now the vocabulary had no word for it** — [[claim]] still calls `kind` "vocabulary still to settle". That word is the operator's to settle, and the evidence for it is now on the record rather than in an argument.
- **The residue v7 leaves**, three claims: one genuine over-read (photos of a building became a damage report), one wrong place (a hotel's name read as Caraballeda), and one refusal the judge itself is inconsistent about — it accepted three `solicitud de información sobre edificio` claims and refused a fourth on the ground that seeking information is not a claim.
- **The support gate earned its keep.** It had never refused anything on the rehearsal corpus — 8 of 8 supported. On real posts it caught every one of v5's inventions and named the reason in a sentence. Every prompt rule above was written from its notes.
- Evidence: runs `197d3c28` (v5), `633b4bd9` (v6), `58aaa47d` (v7); `prompts/extraction.v{5,6,7}.txt`; `priv/scripts/read_path_batch.exs`.
- Related: [[open-extraction-does-not-batch]] — the first attempt fed all 98 posts in one call and the worker timed out at 180 seconds, which is that page's claim measured rather than argued.
