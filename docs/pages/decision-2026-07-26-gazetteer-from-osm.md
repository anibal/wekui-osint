decided:: 2026-07-26
status:: settled
title:: Decision — seed the gazetteer from OpenStreetMap, algorithmically
type:: decision

- The [[place]] tree is sourced from **OpenStreetMap**, pulled by bounding box per [[event]] and mapped onto the estado→municipio→parroquia→sector→edificio hierarchy — future events self-seed from a bbox rather than ad-hoc per-event curation. Settled by the 2026-07-26 deep-research report (`docs/osm-gazetteer-research.md`: 24 sources, 70 claims verified, 5 refuted).
- **Licensing accepted (2026-07-26):** a persistent OSM-derived gazetteer that is publicly used is an ODbL *Derivative Database*, so it is published under the ODbL with "© OpenStreetMap contributors" attribution — Aníbal confirmed sharing is fine. The adversarial pass caught the trap: the OSMF geocoding-guideline "store permanently" allowance does NOT cover a systematic gazetteer, and deduping curated data against OSM makes the merged database ODbL.
- **Architecture (Nominatim's model):** `boundary=administrative` + `place=*` form the parent tree and buildings attach as leaf nodes; Venezuela's `admin_level` maps to our types via a country-configurable table; place nodes reconcile onto boundaries by label-member / wikidata / folded name. Overpass for a live per-event pull (fits `Req`), Geofabrik + `osmium` for the bulk path.
- **Deferred, not blocking:** the OSM importer is not built yet. The pilot runs on the committed, cross-checked `priv/gazetteer/caraballeda.json` seed (old app + `gazetteer.db` + Tavily), which is enough to unblock downstream work; the old app and `gazetteer.db` become cross-check sources once the OSM importer lands.
