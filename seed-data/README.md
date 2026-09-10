# Location master data

Country → State/Province → City reference data for Nenjam Matrimony.

These three files are the **only** source the database seeder reads. GeoNames is
a build-time input, downloaded by hand and never called at runtime — the API
serves locations from our own tables, so a GeoNames outage or licence change
cannot affect registration.

| File | Records | Purpose |
|---|---|---|
| `iso-3166-1-countries.json` | 8 | Countries |
| `iso-3166-2-subdivisions.json` | 384 | States / provinces / regions |
| `cities.csv` | 9,308 | Cities |

**Version:** 1.0 — built 2026-09-10 from GeoNames dumps of that date.

---

## Sources and licences

| Source | Version | Licence | Used for |
|---|---|---|---|
| [GeoNames](https://www.geonames.org/) `cities15000.txt` | 2026-09-10 dump | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | City names and populations |
| GeoNames `admin1CodesASCII.txt` | 2026-09-10 dump | CC BY 4.0 | Subdivision names, to join cities to ISO codes |
| GeoNames `countryInfo.txt` | 2026-09-10 dump | CC BY 4.0 | ISO 3166-1 country names |
| [`iso-3166-2`](https://www.npmjs.com/package/iso-3166-2) npm package | 1.0.0 | MIT | ISO 3166-2 subdivision codes, names and types |

> **Attribution (required by CC BY 4.0):** This product includes geographical
> data from [GeoNames](https://www.geonames.org/), licensed under
> [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Data has been
> filtered, re-keyed to ISO 3166 codes, and reformatted; GeoNames does not
> endorse this work.

This attribution must remain visible wherever the data is redistributed. It is
reproduced in the app's licences screen.

---

## Build process

`build_dataset.py` in this directory produced the files. It is a **one-off,
run-by-hand script**, not part of any deploy, test or CI pipeline.

```bash
# from a scratch directory, download the GeoNames inputs
curl -O https://download.geonames.org/export/dump/cities15000.zip && unzip cities15000.zip
curl -O https://download.geonames.org/export/dump/admin1CodesASCII.txt
curl -O https://download.geonames.org/export/dump/countryInfo.txt
curl -o iso3166.min.js https://cdn.jsdelivr.net/npm/iso-3166-2@1.0.0/iso3166.min.js

python build_dataset.py     # writes out/, exits non-zero if any check fails
```

The script is **deterministic**: given the same four inputs it reproduces these
files byte for byte. Ordering never depends on the input file's row order.

### How cities are joined to subdivisions

GeoNames codes subdivisions inconsistently — `US.AR` is already ISO-shaped,
`IN.25` and `AE.03` are not — so cities are matched to ISO 3166-2 **by
subdivision name within the country**, never by GeoNames' own code. A city whose
subdivision name finds no ISO match is dropped and counted, never guessed at.

### City codes

`{ISO-3166-2 subdivision}-{UPPERCASED, ACCENT-STRIPPED, PUNCTUATION-COLLAPSED name}`
— e.g. Chennai in Tamil Nadu is `IN-TN-CHENNAI`. Codes are stable across
rebuilds and are the value stored in `city_code`.

---

## Deliberate deviations from the sources

Everything below is an approved, documented decision. Nothing here is a guess,
and no geographic relationship was invented.

### 1. Singapore is modelled as one city-state — `SG-SG`

**`SG-SG` is not an ISO 3166-2 code.** It is an application-level exception.

ISO defines five Singapore regions (`SG-01`…`SG-05`), but GeoNames publishes no
subdivision names for Singapore at all — its 65 Singapore rows carry `00`, `01`–`05`
or blank `admin1` values that cannot be verified against the ISO regions. Mapping
them would be guessing, so we don't.

Instead a single synthetic subdivision is created:

```json
{ "code": "SG-SG", "countryCode": "SG", "label": "Singapore",
  "type": "City-state", "isActive": true }
```

All 65 Singapore cities are assigned to it. This also matches how members
actually describe living in Singapore. `SG-01`…`SG-05` are retained in the table
(so any value referencing them still resolves) but are `isActive: false`.

### 2. India — current and superseded subdivision codes

The `iso-3166-2@1.0.0` package predates two published ISO changes, so both are
added explicitly:

| Code | Label | Status | Note |
|---|---|---|---|
| `IN-LA` | Ladakh | **active** | Created 2019; missing from the package |
| `IN-DH` | Dadra and Nagar Haveli and Daman and Diu | **active** | Merged UT, 2020 |
| `IN-DN` | Dadra and Nagar Haveli | inactive | Superseded by `IN-DH` |
| `IN-DD` | Daman and Diu | inactive | Superseded by `IN-DH` |

The two superseded codes are **retained, not deleted**: legacy profile values
must stay resolvable. Being inactive keeps them out of registration dropdowns.

### 3. Inactive subdivisions generally

The invariant is **active ⟺ has at least one city**. A subdivision with no city
behind it is a dead end in the registration form — the member picks it and the
city list is empty — so 243 such subdivisions were marked inactive. Their rows
are retained and remain resolvable; they are only excluded from dropdowns.

| Country | Count | Why |
|---|---:|---|
| GB | 235 | ISO codes the UK to 239 councils and boroughs; GeoNames codes it to the four countries. All 862 UK cities therefore sit under `GB-ENG` / `GB-SCT` / `GB-WLS` / `GB-NIR`. Assigning each town to a borough would mean guessing. |
| US | 6 | Territories (`AS`, `GU`, `MP`, `PR`, `UM`, `VI`) — GeoNames treats these as separate countries, outside our 8-country scope. |
| IN | 1 | `IN-LD` Lakshadweep — no settlement above the population floor. |
| CA | 1 | `CA-NU` Nunavut — no settlement above the population floor. |

Plus the 5 Singapore regions and 2 superseded Indian codes described above.

### 4. Explicit name aliases

GeoNames uses common English names; ISO 3166-2 uses official transliterations.
Each alias below is a reviewable assertion that two names denote the same
subdivision. **No fuzzy matching is used** — a name not listed here and not
matching exactly is left unmatched and reported.

| Country | GeoNames name | ISO 3166-2 name |
|---|---|---|
| AE | Dubai | Dubayy |
| AE | Abu Dhabi | Abū Z̧aby |
| AE | Sharjah | Ash Shāriqah |
| AE | Fujairah | Al Fujayrah |
| AE | Ajman | 'Ajmān |
| AE | Ras al Khaimah | Ra's al Khaymah |
| AE | Umm al Quwain | Umm al Qaywayn |
| MY | Penang | Pulau Pinang |
| MY | Malacca | Melaka |
| MY | Kuala Lumpur | Wilayah Persekutuan Kuala Lumpur |
| MY | Labuan | Wilayah Persekutuan Labuan |
| MY | Putrajaya | Wilayah Persekutuan Putrajaya |
| IN | Andaman and Nicobar | Andaman and Nicobar Islands |
| IN | Dadra and Nagar Haveli and Daman and Diu | *(same — matches `IN-DH` above)* |

---

## Population threshold

Cities with **population ≥ 15,000** only, from GeoNames' `cities15000` dataset.

The threshold is enforced by the build script rather than assumed from the
source: `cities15000.txt` ships a small number of rows below its own nominal
threshold, and one such row (Harewood, BC — 8,769) was excluded.

Lowering the threshold is the supported way to add smaller towns: swap the input
for `cities5000.txt` and lower `POPULATION_FLOOR`. Doing so would also give
several currently-inactive subdivisions their first city.

---

## Supported countries

Eight, chosen for where the member base and the diaspora actually are:

| Code | Country | Cities | Active subdivisions |
|---|---|---:|---:|
| IN | India | 3,737 | 35 |
| US | United States | 3,406 | 51 |
| GB | United Kingdom | 862 | 4 |
| MY | Malaysia | 355 | 16 |
| AU | Australia | 313 | 8 |
| CA | Canada | 507 | 12 |
| SG | Singapore | 65 | 1 |
| AE | United Arab Emirates | 63 | 7 |

Adding a country means adding its code to `SCOPE`, re-running the script,
reviewing the drop report for unmatched subdivision names, and adding aliases
for any that are genuinely the same place under a different name.

---

## Dropped records

Nothing is silently dropped. Of **9,359** source rows in scope, **9,308** were
kept and **51** dropped, each counted and explained:

| Count | Reason |
|---:|---|
| 50 | Name collides with a larger place of the same name in the same subdivision (e.g. two Ashfords in England, two Rajgarhs in Rajasthan). The larger population wins; `geonameId` breaks a tie. The full list is printed by the build script. |
| 1 | Below the 15,000 population floor (Harewood, BC). |

Zero rows were dropped for an unmatched subdivision name — every subdivision
name in all eight countries resolved to an ISO code, directly or via an alias.

---

## Validation

`build_dataset.py` exits non-zero unless all of the following hold:

1. No duplicate country codes
2. No duplicate subdivision codes
3. No duplicate city codes
4. Every subdivision belongs to a country in the dataset
5. Every city belongs to a country in the dataset
6. Every city's parent subdivision exists **and is active**
7. `IN-DD` and `IN-DN` are present and inactive
8. `SG-01`…`SG-05` are present and inactive
9. `IN-LA` and `IN-DH` are present and active
10. Every Singapore city is under `SG-SG`, and `SG-SG` is non-empty
11. Every active subdivision has at least one city
12. Every city meets the population floor
13. Every city code is well formed

---

## Changing this data

Do not hand-edit these files. Change `build_dataset.py` — an alias, the scope,
the population floor — and re-run it, so the data and its provenance stay in
step. Then review the drop report before committing.
