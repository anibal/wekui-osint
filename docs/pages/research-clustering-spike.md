title:: Clustering spike — telling Posts apart
type:: research
status:: reference

- A spike on telling Posts apart, and telling when they say the same thing. The [full write-up](../clustering-spike.md), with tables and the technical findings, is prose at `docs/` root.
- It informs [[open-when-two-posts-say-the-same-thing]]. Nothing in it is committed to; it is what we measured so the decision, when it is made, is made on evidence.
- Headline findings, measured against [[research-old-app-corpus]]:
  - Exact match on the plain fold catches 189 Posts (1.4%); stripping `t.co` links raises that to 637 (4.8%); stripping links, mentions and hashtags raises it to 876 (6.7%).
  - Stripping `t.co` links is the single biggest lever — 3.6× over the plain fold on its own; the old "first 120 characters" trick was an accidental, badly-calibrated URL stripper, not a similarity heuristic.
  - Around 18% of Posts have a lexical near-twin (Jaccard ≥ 0.5); 58% have no lexical neighbour at all (≥ 0.15) and are simply one person's one report.
  - The missing-person trap: 981 Posts (7.4%) share the same boilerplate and differ only in the missing person's name; lexical scoring does not separate them — bm25 ranks different missing people inside the genuine-duplicate range — so telling them apart needs reading *who* the Post is about, which is judging, not matching.
  - No stored fold is needed: FTS5 `unicode61` with `remove_diacritics 2` folds case and accents at index time; an index built from the raw Payload's text returns byte-identical results to one built over a stored normalized text.
  - If dedup is ever built: clean the text, FTS5 trigram blocking (top-60 by bm25 gives 98.3% recall of true ≥0.5 near-dup edges), then a word-shingle Jaccard rescore; bm25 alone is not a usable threshold.
  - Vector search is deferred: embeddings answer the *other* question (same happening) and are not a better dedup key for near-duplicate surface text.
- Fed [[decision-no-folded-text]].
