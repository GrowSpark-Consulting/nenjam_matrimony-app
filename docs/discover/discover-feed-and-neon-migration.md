# Discover Feed, Shared Neon Database & Partner-Preference Filtering

What changed, why, and how to verify it. Covers two merged PRs:

- **PR #2** — `feat(discover+db): real backend Discover feed, preference filtering, and Neon-ready DB config` (commit `e3ee338`, merged `7627bb2`)
- **PR #3** — `feat(discover): filter the feed by saved partner preferences` (commit `0208011`, merged `64235be`)

---

## 1. Real backend Discover feed (PR #2)

**Before:** the Flutter Discover screen, Matches reels, Search, and "similar profiles" all read from a hardcoded mock datasource (`Advika`, `Kavya`, `Rahul`, `Ananya`, …).

**After:** every one of those surfaces reads from one real backend feed. No UI, layout, navigation, or Hero-animation changes.

### New backend module: `backend/apps/api/src/modules/matches/`

| File | Purpose |
|---|---|
| `controllers/discover.controller.ts` | `GET /discover`, `GET/PUT /discover/preferences`, `GET /discover/search` — all behind `FirebaseAuthGuard` |
| `services/feed.service.ts` | Pagination + DTO assembly; delegates "which profiles" to a `RecommendationService` |
| `recommendation/recommendation.service.ts` + `filtered-feed.strategy.ts` | Strategy interface so the matching algorithm can be swapped later (e.g. an AI-ranked strategy) without touching the controller |
| `filters/partner-preference-where.builder.ts` | Pure function: preferences → dynamic Prisma `WHERE`. See §3 for the full rewrite. |
| `repositories/feed.repository.ts` | Runs the query against `user_profiles`, paginated, in one transaction with `count()` |
| `repositories/preference.repository.ts` | CRUD on `partner_preferences` |
| `mappers/profile-feed.mapper.ts` | Row → `DiscoverProfileDto`. Only public fields (no email/phone/firebaseUid). Presigns S3 photo URLs. |
| `search/search.strategy.ts` + `postgres-search.strategy.ts` | Same strategy pattern for free-text search (Postgres today, Elasticsearch-swappable later) |
| `dto/discover-profile.response.dto.ts`, `dto/partner-preference.dto.ts` | Wire contracts, matching Flutter's `DiscoveryProfileModel.fromJson` field-for-field |

### Frontend rewiring

- `Frontend/lib/features/discover/data/repositories/discover_repository_impl.dart` — now calls `GET /discover` via the shared `ApiClient`, normalizes gender casing (backend sends lowercase; the gender-aware placeholder needs `'Male'`/`'Female'`), and **partitions** the flat feed round-robin across the six on-screen sections (New Today / AI Recommended / Recently Joined / Verified / Near You / Premium).
  - *Why partition instead of repeating profiles*: every card shares `Hero(tag: 'profile-photo-$id')`. The same id in two visible sections would crash Flutter with a duplicate-hero error on navigation.
- Deleted: `discover_mock_datasource.dart`, `discover_remote_datasource.dart` (dormant/unused), `discover_datasource.dart` interface.
- `discover_providers.dart` — repository now constructed from `apiClientProvider` instead of the mock datasource.

Everything downstream (Matches reels, Search's client-side pool, Profile Detail's "similar profiles") re-projects `discoverFeedProvider`, so all of it went real at once with no separate wiring.

### Bug fix: height parsing (`profile.service.ts`)

The wizard's height picker emits `5'9"`-style strings. The old parser (`parseLeadingNumber`) read only the leading number, storing `5` into `height_cm` instead of `175` — silently breaking any height-range partner filter. Added `parseHeightToCm` to convert feet+inches → cm correctly, with a plain-cm fallback.

---

## 2. Shared Neon PostgreSQL database (PR #2)

**Problem found:** the app read the database connection from **discrete** env vars (`DATABASE_HOST`, `DATABASE_PORT`, …), while only the Prisma CLI honored a full `DATABASE_URL`. A teammate who set the shared Neon `DATABASE_URL` in their `.env` was — invisibly — still connecting the running app to their own local Postgres, because the app-level code never read that variable.

**Fix — `DATABASE_URL` is now authoritative everywhere, with SSL, and a discrete-field fallback stays for pure-local setups:**

| File | Change |
|---|---|
| `backend/libs/database/src/prisma.service.ts` | `PrismaPg` adapter now prefers `{ connectionString: db.url }`; falls back to discrete host/port/user/password/database. Boot banner parses the URL so it reports the real host, not `localhost`. |
| `backend/libs/database/src/seed.ts` | Same fix — the seeder was still discrete-fields-only; it would have silently seeded a teammate's local DB even with `DATABASE_URL` set. |
| `backend/libs/config/src/configuration.ts` | Exposes `database.url` from `process.env.DATABASE_URL`. |
| `backend/libs/config/src/validation.ts` | `DATABASE_URL` added as optional; the five discrete `DATABASE_*` vars relaxed from `.required()` to `.optional()` — a teammate now only needs to set the one URL. |
| `backend/libs/config/src/config.service.ts` | Startup "Configuration Loaded" banner also reports the real DB target. |
| `backend/.env.example` | Documents both onboarding paths (shared `DATABASE_URL` vs. local discrete fields). |
| `backend/.gitignore` | Added `.neon` (a local Neon CLI artifact — not a secret, but not something to commit either). |

### Migration + data move (operational, not code)
- Applied all 6 existing Prisma migrations to the empty Neon database (`prisma migrate deploy`) — no new migrations created, `schema.prisma` untouched.
- Copied all local data to Neon table-by-table (`pg_dump` + `\COPY`, both Postgres 18) after confirming the two schemas' column intersection. Verified: row-count parity across 11 tables, **0 orphaned foreign keys** out of 40 FKs, all 4 seeders idempotent (`upsert` on stable keys — re-running creates no duplicates).

### How a teammate switches to the shared DB today
```bash
git pull
# put DATABASE_URL=<shared neon url> in .env.local
npx prisma generate
npx prisma migrate deploy      # already applied — no-op
npm run start:dev
```
Confirm it worked: the boot banner must read `Database: ...neon.tech (via DATABASE_URL)`. If it still says `localhost:5432`, `DATABASE_URL` isn't set or the old code wasn't pulled.

---

## 3. Partner-preference filtering, done correctly (PR #3)

PR #2 already filtered the feed by saved preferences, but it applied the wizard's preference **values literally** — and that vocabulary is mostly non-literal UI shorthand, not real profile data. Applying it as-is silently **over-filtered the feed to empty**.

### The vocabulary problem
| Preference field | Stored values are often | A literal match against... |
|---|---|---|
| Caste | `Same Caste`, `Any Caste`, `Inter-Caste OK` | ...a real `caste` column — never equals any of these |
| Location | `Same City`, `Same State`, `Anywhere in India`, `NRI OK` | ...a real `currentCity`/`currentState` — never matches |
| Education / Occupation | `B.E / B.Tech+`, `Software / IT` (grouped labels) | ...a real single value — never matches |
| Any field | `Any` | ...means "no preference", not a literal choice |

Real data also has inconsistent casing (`sheikh` vs `Sheikh`), which an exact-match filter also silently drops.

### The fix — `backend/apps/api/src/modules/matches/filters/partner-preference-where.builder.ts`

`buildFeedWhere()` now **interprets** the preference before turning it into SQL:

1. **Drop meaningless tokens** — `Any`, `Any Caste`, `Any Degree`, `Doesn't Matter`, `Inter-Caste OK`, `Anywhere in India`, `NRI OK`, and any value containing `/` or `+` (grouped UI labels) are never used as a filter.
2. **Resolve "Same X"** — `Same Caste` / `Same City` / `Same State` / `Same Mother Tongue` resolve to the *caller's own* profile value (loaded via `FeedRepository.findSelf()`, new). If the caller has no value for that field, the preference becomes a no-op rather than an error.
3. **Case-insensitive matching** — every text filter uses Prisma's `{ equals, mode: 'insensitive' }` (via an `OR` of case-insensitive equals for multi-value fields), so `sheikh` matches `Sheikh`.
4. **Extended preferences** — the standalone Partner Preferences page (an already-existing feature, merged separately) stores advanced fields as a free-form JSON blob (`partner_preferences.extended_preferences`). The builder now reads `diet` / `smoking` / `drinking` / `country` from it when present, using the same "ignore Any/meta" rule.
5. Everything from PR #2 stays: opposite-gender matching, self-exclusion, soft-deleted-user exclusion, age/height bounds (birthday-accurate), income floor, marital-status enum mapping, pagination, photos + S3 presigned URLs, and the **exact same response DTO** — zero schema, route, or frontend changes.

### `FeedRepository.findSelf()` (new, replaces `findGender`)
Loads the caller's own `gender`, `caste`, `currentCity`, `currentState`, `motherTongue` in one query — used both for opposite-gender matching and to resolve "Same X" preferences.

### Verification
- 10 new unit tests for the builder (`partner-preference-where.builder.spec.ts`) covering every rule above.
- Fixed 5 pre-existing test failures in `validation.spec.ts` that were left over from PR #2's discrete-field-to-optional change (the test still asserted those fields were required).
- **Full backend suite: 31 suites / 91 tests, all green.**
- Live-verified against Neon with a real account (MALE, `caste=sheikh`, opposite-gender = FEMALE):

  | Preference set | Result |
  |---|---|
  | Empty | All 3 female profiles, self excluded |
  | `religion=Muslim` | 2 matches (Muslim only) |
  | `religion=Hindu` | 1 match |
  | `caste=Same Caste` | 2 matches — resolved to caller's `sheikh`, matched `Sheikh` case-insensitively (previously: **0**, feed silently empty) |
  | `caste=Any Caste` | All 3 (meta token ignored) |
  | `limit=2` pagination | Page 1 → 2 items, `hasMore=true`; page 2 → 1 item, `hasMore=false` |

---

## 4. Test accounts (data only, not code)

10 finalized profiles were seeded directly into the shared Neon database for manual verification: 5 male + 5 female, partner preferences set to fully open (`Any`/empty on every field), covering a spread of religions/cities/professions so both empty-preference and filtered scenarios can be exercised by hand from the phone.

---

## 5. Where things stand

- Both PRs are **merged into `main`** (`64235be` is the current head at time of writing).
- Local and remote `main` are in sync; no other application-code changes are pending.
- An unrelated, older teammate branch (`origin/env-unification`, Firebase auth/config work, last touched 2026-07-12) exists unmerged — explicitly left untouched, not part of this work.
