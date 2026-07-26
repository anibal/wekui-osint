# Sourcing the gazetteer from OpenStreetMap — deep research (2026-07-26)

**Question:** can OSM (or an affordable alternative) seed the place tree *algorithmically*
by bounding box, so future events don't need ad-hoc per-event seeding?

**Provenance:** a `/deep-research` fan-out — 5 search angles → 24 fetched sources → adversarial
verification (2-of-3 refutes to kill). **70 claims confirmed, 5 refuted** — and all five refuted
claims were the *same licensing overreach* (§2). The final synthesis agent crashed on output
serialization; this report is reconstructed from the verified journal, so treat it as the workflow's
findings, not a hand-wave.

---

## TL;DR — the answer is yes, and there's a production-proven recipe

1. **Seed from OSM by bbox.** Overpass API for a live per-event pull (fits Elixir/Req, JSON out);
   Geofabrik `.osm.pbf` + `osmium extract` for the bulk/offline path. This is what our
   `gazetteer.db` already did for the admin skeleton — the new part is the **buildings** layer.
2. **Licensing is the real decision, not a blocker.** A persistent OSM-derived gazetteer that is
   *publicly used* is a **Derivative Database → it must be published under ODbL** (share-alike) with
   attribution. For an open public memorial that's *acceptable* — but it's a genuine obligation, and
   there's a trap (§2) the verification caught.
3. **"Affordable alternatives" are mostly hosted OSM.** Geoapify / LocationIQ / OpenCage are
   Nominatim-under-the-hood → same ODbL. The *independent* commercial APIs (Google, HERE, Mapbox,
   TomTom) **forbid persistent storage or redistribution** → unusable for a durable gazetteer.
4. **Adopt Nominatim's model** (§5): boundaries + place nodes are the parent tree, buildings are
   leaves; map Venezuela's `admin_level` → our types via a *country-configurable* table.

---

## §1 — Access: how to pull building-level data by bbox

- **Overpass API** — query by bbox (order: `[bbox:S-lat,W-lon,N-lat,E-lon]`), Overpass QL/XML in,
  `json`/`xml`/`csv`/`geojson` out, endpoint `overpass-api.de/api/interpreter`. Header
  `[out:json][timeout:25];`. **Hard caps:** default 180 s timeout, 512 MB memory (raisable inline to
  ~1 GiB), queries over 2 GB aborted. **Fair use:** under **10,000 queries/day and 1 GB/day** on the
  main instance; must send a `User-Agent`/`Referer`. Free servers are rate-limited and *not* for
  high-volume production. *(OSM Wiki: Overpass API / Overpass QL — primary.)*
- **Geofabrik** — daily `.osm.pbf` extracts by continent/country/region, pre-cleaned of user/changeset
  metadata. The wiki explicitly says: for country-sized or near-complete regions, **use planet/Geofabrik
  mirrors, not Overpass** — Overpass is for *selective* queries. *(primary.)*
- **`osmium extract`** — cuts a `.osm.pbf` to an arbitrary bbox/polygon **offline, no network**; reads
  PBF/XML/OPL, accepts a GeoJSON polygon boundary, **never clips objects at the edge** (whole building
  footprints + admin relations survive), and a `--config` file cuts many named regions in one pass —
  i.e. *one entry per future event*. Use the `complete_ways`/`smart` strategy so edge relations resolve.
- **`osm2pgsql`** — loads OSM into PostGIS; the standard importer (and Nominatim's, §5).

**Fit for us:** Overpass for a bounded event bbox (Caraballeda is small — well inside the caps),
straight into `Req`. Geofabrik + osmium if a region grows past Overpass's practical size.

## §2 — Licensing (the crux) — a Derivative Database triggers ODbL share-alike

ODbL permits **any** use, including commercial/governmental, so a donations-facing memorial is fine
*(OSMF, primary)*. The decisive distinction:

- **Produced Work** (displaying place labels on the memorial page) — does **not** create a Derivative
  Database, does **not** trigger share-alike; it only needs an **attribution notice**. *(ODbL §4.5(b).)*
- **Derivative Database** (our stored, transformed place tree) — if **Publicly Used**, **must be
  licensed only under ODbL** (or a compatible/later license), *and* you must **offer recipients a
  machine-readable copy of the Derivative Database or of the alterations/algorithm**. *(ODbL §4.4, §4.6.)*
- **Purely internal use triggers nothing** — "if you do not make Public Use of the data, you do not
  have to share anything." *(OSMF, primary.)*

**⚠ The trap the verification caught (5 refuted claims).** Several sources claimed the OSMF *Geocoding
Guideline* lets you "store results permanently, so a persistent gazetteer is permitted." **This is an
overreach, refuted against the primary text:** the guideline permits storing results *only "together
with the external data used for querying"* — coupled to the specific record that drove each query — and
share-alike is avoided **only if** the data isn't modified beyond trivial transformation **and** isn't
"aggregated into a new database reproducing the whole or a substantial part of OSM." **A systematic
gazetteer of a region's places is exactly such an aggregation → it is a Derivative Database → ODbL
applies.** Don't rely on the geocoding-guideline exemption to keep a gazetteer proprietary.

**The Collective-Database subtlety — and a second trap for *us* specifically.** Combining OSM with a
non-OSM dataset can stay a **Collective Database** (share-alike confined to the OSM layer) *only if* the
OSM-derived layer remains **separately identifiable** and each data type is all-OSM or all-non-OSM within
a regional cut. **But** the OSMF guideline is explicit: *complementing a proprietary/curated list with OSM
data **and removing duplicates in the process** produces a Derivative Database* — so **deduping our
existing curated gazetteer against OSM makes the whole merged thing ODbL-encumbered** once published.
That bears directly on our planned "reconcile against the existing gazetteer" step.

**Attribution:** "© OpenStreetMap contributors" or "Map data from OpenStreetMap", hyperlinked to
`openstreetmap.org/copyright`, making clear the data is under ODbL. *(OSM Wiki, primary.)*

**Verdict for the memorial:** OSM is usable and the ODbL obligation is *tolerable* — publish the place
tree under ODbL + attribute. That's aligned with an open public-good record, not a cost. The only real
decision is whether to (a) accept ODbL for the whole gazetteer, or (b) keep the OSM layer separately
identifiable (Collective Database) to leave our curated/non-OSM data unencumbered — **and (b) is lost
the moment we dedup across the two layers.**

## §3 — Commercial alternatives: caching/redistribution is where they die

Ranked by fitness for a *persistent, redistributable* gazetteer:

| Provider | Store results? | Redistribute? | Notes |
|---|---|---|---|
| **Geoapify** | ✅ cache+store+**redistribute** allowed | ✅ | Built on OSM/GeoNames/OpenAddresses → ODbL attribution; free tier, no card. **Best terms.** |
| **Geocodio** | ✅ unrestricted, incl. derivative datasets | ✅ | Rare permissive commercial; but US/Canada-focused — VE coverage unverified. |
| **LocationIQ** | ⚠ paid tiers: store forever; free: 48 h only | ⚠ | Hosted Nominatim/OSM; Developer $100/mo, 25K/day. |
| **OpenCage** | (hosted Nominatim/OSM) | attribution, no resale | Same OSM data underneath. |
| **Mapbox** | ⚠ permanent tier only (`permanent=true`) | ❌ no redistribution; must display on Mapbox maps | permanent tier costs more. |
| **Google** | ❌ >30 days (Place IDs exempt, not data) | ❌ Google logo, no non-Google map | Deleted at contract end. |
| **HERE** | ❌ >30 days | ❌ | audit/testing exception only. |
| **TomTom** | ❌ no derivative databases | ❌ | cache per response headers only. |

**Key insight:** the *affordable* options that permit a persistent gazetteer (Geoapify, LocationIQ,
OpenCage) are **hosted OSM/Nominatim** — they don't escape ODbL, they just save us running the stack.
The genuinely-independent APIs (Google/HERE/Mapbox/TomTom) forbid the persistence or redistribution a
durable, public gazetteer needs. **There is no cheap commercial escape from ODbL** — the data that
covers Venezuela buildings *is* OSM.

## §4 — Overture Maps & open building footprints

- **Overture Buildings theme** — **ODbL** (because it includes OSM). 2.3 B+ footprints conflating
  OSM (top priority) + Google Open Buildings + Esri + Microsoft; the **Google Open Buildings addition
  filled Latin America coverage** (directly relevant to Venezuela). Global. Each building carries a
  stable **GERS ID** (useful for dedup). **But**: distributed as **GeoParquet on S3/Azure**, not a
  live API → needs DuckDB/Python, awkward for Elixir; and it's **footprint polygons** (centroid handling).
- **Overture Places theme (POI)** — **CDLA Permissive 2.0 + Apache 2.0, no OSM data, no share-alike.**
  ~75 M POI points (name/category/address/confidence/GERS). Tempting *because it avoids ODbL* — but
  Overture itself warns it has **duplicates, a high junk rate, and low completeness**, it's *points not
  footprints*, and **joining it to OSM re-triggers ODbL** on the combined DB. Probably not worth the
  awkwardness over OSM for our case.

## §5 — Architecture: Nominatim is the reference recipe

The production OSM-to-gazetteer pipeline, directly reusable:

- **Import:** `osm2pgsql` with a **flex Lua style** that filters/converts tags. Scope is preset-selectable:
  the **`admin` style imports only `boundary=administrative` + `place=*`** (the admin skeleton — *exactly
  what `gazetteer.db` did*), while `address`/`full` add buildings.
- **Tag roles (the tag→tree map):** every OSM tag is classified as a **main** tag (place type), a **name**
  tag (primary/searchable vs auxiliary `ref`s), an **address** tag (`addr:`/`is_in:` stripped), or an
  **extra** tag.
- **Address rank 4–30 (the hierarchy):** country 4, state 5–9, county 10–12, city 13–16, suburb 17–21,
  neighbourhood 22–24, locality 25, street 26–27, **POI/building always 30 (leaves)**. Our
  estado→municipio→parroquia→sector→edificio maps straight onto this.
- **`admin_level` → rank is country-configurable** — *do not* assume a universal table; a **Venezuela
  config** must declare which `admin_level` is estado / municipio / parroquia / sector.
- **Reconcile place nodes onto boundaries** by: the place node being a **`label` member** of the boundary
  relation, **same `wikidata` tag**, or (restricted) **same name**. Boundaries get ranks first, then place
  nodes attach; a place node inside a same-rank boundary is **demoted** (villages-absorbed-into-a-city →
  suburb). That's a concrete dedup rule against a pre-existing tree.
- **Pelias alternative:** assign the admin hierarchy by **point-in-polygon** (lat/lon → containing admin
  polygons, from open *Who's on First* data, MIT — no ODbL on the polygons). Decouples admin assignment
  from tag-parsing; buildings handled in a separate pipeline.

## §6 — Recommendation for wekui-new

**Adopt OSM-algorithmic, bbox-driven seeding — it replaces ad-hoc seeding and it's production-proven.**
Concretely:

1. **Per-event bbox → Overpass** pulls (a) `boundary=administrative` + `place=*` for the skeleton and
   (b) `building=*` with `name`/`addr:*` for leaves — into `Req`, JSON out.
2. **Map tags → our tree** with a small Nominatim-style classifier: main→`type`, name→`PlaceName`
   (primary `:raw`/`:official`, `ref`→`:recognition_only`), address→ancestor hints. Use a **Venezuela
   `admin_level` table** (estado=4, municipio=6, parroquia=8… to confirm) rather than hardcoding.
3. **Reconcile onto the existing tree** by label-member / wikidata / folded-name — the same
   most-specific-first matching the resolver already does.
4. **License:** publish the seeded gazetteer under **ODbL** with "© OpenStreetMap contributors"
   attribution; keep any purely-curated, non-OSM layer *separately identifiable* if we ever want to
   avoid copyleft on it (and accept that deduping across the layers forecloses that).
5. **This reframes our sources:** `gazetteer.db` (already a partial OSM admin import) and the old app
   become **bootstrap + cross-check**, not the primary. OSM-live becomes the primary, self-seeding source;
   Overture Buildings is a coverage *supplement* where OSM buildings are sparse.

**Net:** the operator's instinct is right — we were rebuilding by hand what OSM already holds (the
screenshot's OPPE 26 / Residencias Caribe / Palma Real are *in OSM*). The move is a bbox-driven OSM
importer modeled on Nominatim, ODbL-licensed output, with the old app + gazetteer.db as cross-checks.
