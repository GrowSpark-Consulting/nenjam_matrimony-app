# Location Master Data — Country → State → City

**Status:** Implemented, not yet deployed.
**Branch:** `feat/location-master-data`
**Date:** 2026-09-10

Replaces the hardcoded Flutter lists (8 countries, 11 states, 9 cities) with
backend-owned master data keyed by ISO 3166 codes: **8 countries, 384
subdivisions, 9,308 cities.**

This is the first of the deferred items in
[`docs/registration/profile-options-reference-data.md`](../registration/profile-options-reference-data.md)
§4 to be built. Religion, caste and mother-tongue taxonomies are deliberately
untouched.

---

## 1. What changed, in one line each

| Layer | Change |
| --- | --- |
| `seed-data/` | The dataset itself, plus the script that built it |
| Prisma | Three new tables; three new **nullable** columns on `user_profiles` |
| Seeder | `pnpm seed:locations` — idempotent, additive, safe against production |
| API | `GET /reference-data/countries \| states \| cities` — public |
| Validation | `LocationService.resolve()` — the server, not the client, is the authority |
| Flutter | `features/location` — models, repository, on-device cache, providers, cascade UI |
| Analysis | `pnpm analyze:locations` — **read-only** legacy backfill report |

---

## 2. The one thing to understand first

**Nothing about existing member data changes.**

The new `country_code` / `state_code` / `city_code` columns sit *beside* the
existing free-text `country` / `current_state` / `current_city`. They are
nullable, they start NULL for every existing profile, and they stay NULL until
a separate backfill is reviewed and approved.

Legacy values — `TN`, `chennai`, a Singapore address filed under Kerala —
remain exactly as members typed them. They are never silently corrected.

The migration contains no `NOT NULL`, no `DEFAULT`, no `UPDATE`, and no data
migration of any kind. Applying it to production changes no member's data.

---

## 3. Data model

```
Country (code PK, e.g. "IN")
  └── Subdivision (code PK, e.g. "IN-TN", country_code FK)
        └── City (code PK, e.g. "IN-TN-CHENNAI", state_code FK, country_code FK)
```

### Why the ISO code is the primary key

A surrogate `uuid` would have bought nothing. An ISO code is already unique,
stable and meaningful, so a profile stores `IN-TN-CHENNAI` directly and the API
never has to expose an internal database id to a client.

City codes are `{subdivision code}-{uppercased, accent-stripped,
punctuation-collapsed name}` — deterministic, so a dataset rebuild produces the
same code for the same city.

### `is_active`

What registration dropdowns filter on. **Deactivating is how a row is retired;
rows are never deleted**, because a profile may still reference one.

Foreign keys are `ON DELETE RESTRICT`, not Prisma's default `SET NULL` for an
optional relation — retiring a city must never silently blank a member's stated
location. A delete that would orphan a profile fails loudly instead.

### `city.country_code` is denormalized

Deliberate redundancy: it lets a country-wide city search skip the join, and the
foreign key stops it drifting out of step with the subdivision's own country.

---

## 4. Deliberate deviations from ISO

All approved and documented in full in
[`seed-data/README.md`](../../seed-data/README.md).

### Singapore — `SG-SG` is **not** an ISO code

ISO defines five Singapore regions (`SG-01`…`SG-05`), but GeoNames publishes no
subdivision names for Singapore at all — its 65 Singapore rows carry `00`,
`01`–`05` or blank `admin1` values that cannot be verified against the ISO
regions. Mapping them would be guessing.

Instead one synthetic city-state subdivision holds all 65 cities. This is also
how members describe living there. `SG-01`…`SG-05` are retained but inactive.

### India — current and superseded codes

| Code | Label | Status |
| --- | --- | --- |
| `IN-LA` | Ladakh | **active** (created 2019; missing from `iso-3166-2@1.0.0`) |
| `IN-DH` | Dadra and Nagar Haveli and Daman and Diu | **active** (merged UT, 2020) |
| `IN-DN` | Dadra and Nagar Haveli | inactive — superseded |
| `IN-DD` | Daman and Diu | inactive — superseded |

The superseded codes are retained so legacy values stay resolvable, and inactive
so they never appear in a dropdown.

### 243 subdivisions deactivated for having no city

The invariant is **active ⟺ has at least one city**. A subdivision with nothing
behind it is a dead end in the form: the member picks it and the city list is
empty.

| Country | Count | Why |
| --- | ---: | --- |
| GB | 235 | ISO codes the UK to 239 councils and boroughs; GeoNames codes it to the four countries, so all 862 UK cities sit under `GB-ENG`/`SCT`/`WLS`/`NIR`. Assigning each town to a borough would mean guessing. |
| US | 6 | Territories (`AS`, `GU`, `MP`, `PR`, `UM`, `VI`) — GeoNames treats these as separate countries, outside our 8-country scope. |
| IN | 1 | `IN-LD` Lakshadweep — no settlement above the population floor. |
| CA | 1 | `CA-NU` Nunavut — same. |

Rows are retained and resolvable. Lowering the population floor (swap
`cities5000.txt`, lower `POPULATION_FLOOR`) is the supported way to give them
cities.

---

## 5. Where the data comes from

GeoNames (CC BY 4.0) joined to ISO 3166-2 **by subdivision name within the
country**, never by GeoNames' own subdivision code — GeoNames codes them
inconsistently (`US.AR` is already ISO-shaped, `IN.25` and `AE.03` are not).

**GeoNames is a build-time source and is never called at runtime.** A GeoNames
outage or licence change cannot affect registration.

`seed-data/build_dataset.py` is committed alongside the data so its provenance
is reviewable. It is deterministic — same inputs, byte-identical output,
independent of input row order or platform — and exits non-zero unless 13
validation checks pass. Nothing is silently dropped: of 9,359 source rows in
scope, 9,308 were kept and 51 dropped, each counted and explained.

> **Attribution (required by CC BY 4.0):** includes data from
> [GeoNames](https://www.geonames.org/), licensed
> [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), filtered and
> re-keyed to ISO 3166. GeoNames does not endorse this work.

---

## 6. The API

```
GET /reference-data/countries[?includeInactive=true]
GET /reference-data/states?countryCode=IN[&includeInactive=true]
GET /reference-data/cities?stateCode=IN-TN[&search=chen][&limit=200]
```

**Public — deliberately not behind `FirebaseAuthGuard.`** The location step runs
during registration, before a member has a profile and, in the mobile+password
flow, potentially before a session exists at all. Requiring a token would make
the country dropdown unfillable for exactly the people who need it. There is
nothing to protect: ISO codes and city names, identical for every caller,
derived from a public dataset, nothing user-specific.

Throttling still applies — `ThrottlerGuard` is registered globally as an
`APP_GUARD`.

### Ordering

Cities come back **largest first**, so the list is useful before the member
types anything. With `search`, prefix matches rank above substring matches —
someone typing `cast` in New South Wales means Castle Hill, even though
Newcastle is 13× larger.

### Caching

The whole dataset is held **in memory** (~500KB, identical on every instance,
changes only on deploy), so a dropdown costs no round trip to Neon in Singapore.
Redis is not used: it is an optional dependency in development, and registration
is not.

The trade is that a seed run mid-process is not picked up until restart. That is
correct here — deploys restart the process anyway.

---

## 7. Server-side validation

`LocationService.resolve()` is what profile writes go through. It confirms the
triple exists **and that the hierarchy is genuinely consistent** — the city
really is in that state, the state really is in that country.

This is why the server is the authority: a hand-crafted request cannot file
Chennai under Singapore.

Two behaviours worth knowing:

- **Codes resolve against active *and* inactive rows.** A member holding a
  since-retired code must be able to save an unrelated profile edit without
  being forced to re-answer where they live. Only dropdowns filter on
  `is_active`.
- **No codes is not an error.** `resolve()` returns null, and the free-text
  columns remain the source of truth. Every profile written before this feature
  shipped, and every client not yet updated, works unchanged.

Writes populate **both** forms. The free-text columns stay authoritative for
everything that already reads them (search, feed cards, emails), with labels
taken from the master data where codes were sent, so text and code cannot
disagree. A client that sends no codes leaves the columns untouched rather than
nulling them.

---

## 8. Flutter — `features/location`

```
domain/models/location_models.dart     LocationOption, SelectedLocation
data/location_repository.dart          cache-first reads
data/location_cache.dart               SharedPreferences, 7-day TTL
presentation/providers/                Riverpod: countries, states(cc), cities(sc)
presentation/widgets/                  LocationPickerField, LocationCascade
```

`SelectedLocation` owns the cascade rule — changing a parent clears its children
— which is the same rule the server enforces, kept in one place so the two
cannot drift.

### The cache is not user data

`LocationCache` is deliberately its own `SharedPreferences` accessor rather than
a method on `StorageService`, because **`clearUserData()` on sign-out must not
drop it.** It holds a copy of a public reference table; clearing it would make
the next member on the device re-download everything.

An empty result is never cached — far more likely a transient backend problem
than a real answer, and caching it for a week would strand the member with an
empty dropdown.

### The picker handles all three real states

Loading, failed (with a retry the member can actually use), and ready. A
silently empty dropdown is the one outcome it must never produce: it looks
identical to "there is nothing here" while actually meaning "the request
failed".

### Legacy values are displayed, not discarded

A draft saved before this existed has labels and no codes. Those are **not**
promoted into a selection — guessing which city `chennai` meant is exactly what
the server refuses to do — but they are **not** discarded either. They are shown
in the field and re-emitted verbatim until the member replaces them.

> This matters more than it looks. The first version of the step emitted empty
> strings for legacy values, which would have **wiped the stored location of
> every existing member who edited any other field on that step.** The
> regression test `a location saved before the master data existed is not lost`
> exists to keep that fixed.

---

## 9. Deploying this

Not yet applied anywhere. In order:

```bash
# 1. Schema — additive, changes no member's data
pnpm prisma:migrate:deploy

# 2. Master data — idempotent, additive, touches only the three new tables
pnpm seed:locations

# 3. READ-ONLY report on what a legacy backfill would do
pnpm analyze:locations
```

**Step 3 produces the report that must be reviewed before any backfill.** It has
no write path at all — no update, no upsert, no delete anywhere in the file.

Its matching rule is strict: a profile counts as unambiguously resolvable only
when its city text resolves to exactly one city whose state and country agree
with the profile's own. Everything else is reported with the actual value shown,
for a person to decide. **No fuzzy matching — a near-miss is a miss.**

No backfill runs until that report is reviewed and approved.

### Rollback

The migration is additive, so rolling back the code is enough — the three new
tables and three new columns are simply unused. Nothing needs to be undone to
restore previous behaviour.

---

## 10. Changing the dataset

Do **not** hand-edit the files in `seed-data/`. Change `build_dataset.py` — an
alias, the country scope, the population floor — re-run it, and review the drop
report before committing, so the data and its provenance stay in step.

`libs/database/src/seeders/locations/locations.seed.spec.ts` guards the
committed bytes: the build script validates its own output, but the build script
is not what runs on deploy.

---

## 11. Test coverage

| Suite | Count |
| --- | --- |
| Backend total | 829 passing |
| `LocationService` (reads, hierarchy validation, retired codes) | 17 |
| Committed-dataset guard | 7 |
| Flutter total | 723 passing |
| `features/location` (models, cascade, repository, cache) | 16 |
| Registration location cascade + legacy-value regression | 6 |

Migration SQL was verified against `prisma migrate diff` as exactly what Prisma
generates from the schema — no drift.

> **Known unrelated failure:** `no_trust_score_references_test.dart` fails on
> `main` and on this branch. It flags `"Get verified to earn more trust."` in
> `completionCardBodyVerification` — a line this work does not touch.
