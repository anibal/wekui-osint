# Spike: telling Posts apart, and telling when they say the same thing

**Status:** research, not built. This informs the deferred work in
[`ubiquitous-language.md`](ubiquitous-language.md) → **Still open #5** ("When two
Posts are saying the same thing"). Nothing here is committed to; it is what we
measured so the decision, when it is made, is made on evidence.

**Evidence base:** the old app's real database — one Event, 13,248 Posts, 6,239
Authors, 20,611 Appearances. Measured on a disposable copy; the original was
never touched.

---

## The question

A Post's text is not a reliable key for "we have seen this before". The old app
stored a folded `normalized_text` (lowercase, accent-stripped, whitespace-
collapsed) and treated it as the way to notice repetition. It does not work, and
"the same thing" turns out to be two different questions that want two different
answers.

## What duplication actually looks like

| Method | Posts caught | Share |
|---|---|---|
| Exact match on the plain fold (what was stored) | 189 | 1.4% |
| Exact match after stripping `t.co` links | 637 | 4.8% |
| Exact match after stripping links + @mentions + #hashtags | 876 | 6.7% |
| Has a lexical near-twin at Jaccard ≥ 0.5 | ~2,374 | ~18% |
| Has **no** lexical neighbour at all (≥ 0.15) | ~7,641 | 58% |

Two findings settle the shape of it:

- **Stripping `t.co` links is the single biggest lever** — 3.6× over the plain
  fold on its own. The old app's "cluster on the first 120 characters" trick was
  not a similarity heuristic at all; in almost every group it produced, the only
  difference between members was a trailing link or hashtag block. It was an
  accidental, badly-calibrated URL stripper. Do the stripping deliberately.
- **58% of Posts are genuinely unique** — one person's one report, no near-twin
  by any lexical measure. No technique changes that.

## Two questions, not one

- **Is this the same message posted twice?** A matter of cleaning text and
  comparing it. Reachable deterministically, to about 6.7% exact / ~18% near.
- **Are these two people telling us about the same happening?** Not reachable by
  string work at all. This is event clustering, and it belongs with the judging
  vocabulary, not with dedup.

Conflating them is the mistake `normalized_text` already made.

## The trap any rule must survive

**981 Posts (7.4%) share the missing-person boilerplate** — `🚨 [name] se
encuentra desaparecid@ se busca informacion…` — differing only in the name of
the missing person. They read as near-identical and mean opposite things. The
FTS5 spike confirmed **lexical scoring does not separate them**: bm25 ranks
different missing people as near-duplicates, inside the genuine-duplicate range.
A word-shingle Jaccard escape exists but is razor-thin (different-person max
0.43 vs the 0.5 cut) and content-dependent — a warning, not a safety net.
Telling these apart needs reading *who* the Post is about (entity extraction),
which is judging, not matching. A rule that quietly merges them is worse than no
rule at all.

---

## Technical findings (for whoever builds this)

Measured on the app's real engine where it mattered: **exqlite's bundled SQLite
3.53.3, FTS5 + trigram compiled in.** (Bulk analysis ran on Python's sqlite3
3.50.4; core behaviours were spot-checked on exqlite and agreed.)

1. **No stored fold is needed.** An FTS5 index built from
   `json_extract(raw_payload,'$.text')` returns byte-identical results to one
   built over the stored `normalized_text` — Jaccard 1.000 across 20
   accented/mixed-case/ñ queries. FTS5's `unicode61` tokenizer with
   `remove_diacritics 2` folds case and accents *at index time*, so a query for
   `maiquetia` finds `Maiquetía`. This is why **Post carries no normalized
   text**: the fold is produced by the matcher, not stored on the row.

2. **Dedup mechanism, if/when we build it:** FTS5 trigram as a blocking step
   (top-60 by bm25 gives 98.3% recall of the true ≥0.5 near-dup edges), then a
   word-shingle Jaccard rescore to get precision back to ~1.0. **bm25 is not a
   usable threshold on its own** — genuine-dup and non-dup score ranges overlap.

3. **Place-name recognition works straight off the JSON**, no fold column:
   phrase `MATCH` over the JSON-sourced text found `Los Corales`, `Maiquetía`,
   `Macuto`, `Palmar` with high precision. Morphological variants
   (`Tanaguarena` vs `Tanaguarenas`) need a prefix query or gazetteer-side
   handling; common words (`Caribe` → `mar Caribe`) carry a few semantic false
   positives.

4. **UUID primary-key gotcha (concrete):** an external-content FTS5 table with
   `content_rowid='id'` over a `:uuid` (TEXT) PK **builds silently but coerces
   every uuid to integer 0**, destroying the rowid↔row map. The working pattern
   is a standalone FTS5 table carrying the uuid as an `UNINDEXED` column
   (`fts5(post_id UNINDEXED, txt, tokenize="unicode61 remove_diacritics 2")`),
   kept in sync by triggers or an Ash write-through — ecto_sqlite3 will not
   manage the virtual table. Budget ≈ 11 MB (fold) / 16 MB (trigram) for 13k
   Posts.

5. **Loading extensions from Elixir is real** (verified from vendored source):
   exqlite exposes `:load_extensions` per connection, ecto_sqlite3 forwards it
   as a Repo option, ash_sqlite is transparent. So a vector extension is
   reachable in ~a day if we ever want one.

## Vector search: deferred, and not for this

`sqlite-vec` (Apache-2.0) is loadable and, at our scale, brute force is
sub-10ms — no ANN needed. But **embeddings are not a better dedup key.** They
answer the *other* question (same happening), and they would cheerfully group
the 1,515 "about Maiquetía airport" Posts that say entirely different things.
The literature agrees for near-duplicate surface text (MinHash beats neural
embeddings). Trigger conditions for revisiting: a genuine need for *semantic*
grouping, or open-ended semantic search — not deduplication. `sqlite-vector`
(sqliteai) is Elastic-licensed and only free for OSI open-source projects, so
adopting it would be a licensing decision, not a dependency bump.

## Recommendation

1. Ship nothing now — this is deferred by design.
2. When dedup is needed: clean the text (drop URLs/@/#), FTS5 trigram blocking +
   shingle rescore, no stored fold column. Re-measure catch rate on our own data
   before adding anything heavier.
3. Keep "same happening" and the missing-person trap out of the lexical layer
   entirely — they are entity/judging problems.
4. Defer vectors until the need is semantic, not duplicative.
