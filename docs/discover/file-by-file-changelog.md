# File-by-File Changelog

Every file touched across the three merged PRs, what changed in it, and why. Line counts are `git show --numstat` — exact, not estimated.

- **PR #2** `e3ee338` → merged `7627bb2` — real Discover feed + shared Neon DB support
- **PR #3** `0208011` → merged `64235be` — correct partner-preference filtering
- **PR #4** `bd55745` → merged `e4d718b` — exclude invalid profiles + remaining preference fields

---

## PR #2 — `feat(discover+db): real backend Discover feed, preference filtering, and Neon-ready DB config`

### Frontend

| File | +/- | Change |
|---|---|---|
| `Frontend/lib/features/discover/data/repositories/discover_repository_impl.dart` | +86/-20 | Rewritten. Was: called the mock datasource's 7 methods in parallel. Now: calls `GET /discover` via the shared `ApiClient`, unwraps the response, normalizes `gender` casing (backend sends lowercase `"male"`/`"female"`; the gender-aware placeholder widget matches `'Male'`/`'Female'` exactly), dedupes by id, and **partitions** the flat list round-robin into 6 buckets (`aiRecommended`, `recentlyJoined`, `verifiedProfiles`, `nearYou`, `premiumMembers`, `stories`). Added private `_toStory()` and `_normalizeGender()` helpers. |
| `Frontend/lib/features/discover/presentation/providers/discover_providers.dart` | +6/-9 | `discoverRepositoryProvider` now builds `DiscoverRepositoryImpl` from `apiClientProvider` instead of `discoverMockDataSourceProvider`. Removed the `discoverMockDataSourceProvider` definition entirely. |
| `Frontend/lib/features/discover/data/datasources/discover_mock_datasource.dart` | +0/-321 | **Deleted.** This held every hardcoded profile (Advika, Kavya, Rahul, Ananya, Vikram, Meera, Ishaan, Alex Vance, …) and the 7 mock-data methods. |
| `Frontend/lib/features/discover/data/datasources/discover_remote_datasource.dart` | +0/-93 | **Deleted.** A dormant, never-wired-up alternate datasource stub that assumed a different (`/search?category=`) contract — superseded by the repository calling `/discover` directly. |
| `Frontend/lib/features/discover/domain/datasources/discover_datasource.dart` | +0/-20 | **Deleted.** The shared interface those two datasources implemented; with both gone, nothing implemented or referenced it. |
| `Frontend/pubspec.lock` | +11/-11 | Regenerated lockfile noise from a `flutter pub get` during the work; no dependency version changes intended. |

### Backend — new `matches` module (`backend/apps/api/src/modules/matches/`)

All of these are **new files**, none existed before this PR:

| File | Lines | Purpose |
|---|---|---|
| `controllers/discover.controller.ts` | 75 | `@Controller('discover')`, `@UseGuards(FirebaseAuthGuard)`. Routes: `GET /discover` (feed), `GET /discover/preferences`, `PUT /discover/preferences`, `GET /discover/search?q=`. |
| `services/feed.service.ts` | 49 | `getFeed(userId, {page, limit, category})` — computes `skip`/`take`, delegates row selection to the injected `RecommendationService`, maps rows via `ProfileFeedMapper`, returns `{items, page, limit, total, hasMore}`. |
| `services/search.service.ts` | 48 | Same shape as `feed.service.ts` but delegates to the injected `SearchStrategy` for free-text search. |
| `services/preferences.service.ts` | 90 | `get(userId)` / `update(userId, dto)` — reads/writes `partner_preferences` with schema defaults (minAge 18, maxAge 45, minHeightCm 140, maxHeightCm 210) when a user has never set any. |
| `recommendation/recommendation.service.ts` | 30 | Defines the `RECOMMENDATION_SERVICE` DI token (a `Symbol`) and the `RecommendationService` interface (`getFeedForUser`) — the strategy abstraction so the matching algorithm is swappable later without touching the controller/service. |
| `recommendation/filtered-feed.strategy.ts` | 39 | `FilteredFeedStrategy implements RecommendationService` — today's (only) strategy: loads the caller's gender + saved preference, builds the WHERE via `buildFeedWhere`, runs it through `FeedRepository`. |
| `search/search.strategy.ts` | 25 | Same DI-token + interface pattern as `recommendation.service.ts`, for search. |
| `search/postgres-search.strategy.ts` | 63 | `PostgresSearchStrategy` — case-insensitive `contains` OR-search across firstName/lastName/profession/highestEducation/currentCity/currentState/country/religion/motherTongue/bio. Reuses `FeedRepository.findMatching`. Elasticsearch-swappable later behind the same interface. |
| `repositories/feed.repository.ts` | 60 (PR #2) → +23/-5 in PR #3 | `FEED_PROFILE_INCLUDE` (shared Prisma include for feed+search+mapper), `findGender()` (**replaced by `findSelf()` in PR #3** — see below), `findMatching(where, {skip, take})` — runs `findMany` + `count` in one `$transaction`. |
| `repositories/preference.repository.ts` | 33 | `findByUserId(userId)`, `upsert(userId, data)` on `partner_preferences`. |
| `mappers/profile-feed.mapper.ts` | 98 | `ProfileFeedMapper` (injects `S3Service`). `toDto()`/`toDtoList()` — computes age from DOB, formats height cm → `5'9"`, presigns S3 photo URLs, and includes **only** public fields (no email/phone/firebaseUid/tokens). |
| `filters/partner-preference-where.builder.ts` | 157 (first version; **rewritten in PR #3**, see below) | `buildFeedWhere(params)` — pure function, preference row → Prisma `UserProfileWhereInput`. First version: literal `IN` filters per field, age/height date-math, marital-status enum mapping. |
| `dto/discover-profile.response.dto.ts` | 49 | `CompatibilityDto`, `DiscoverProfileDto` (mirrors Flutter's `DiscoveryProfileModel.fromJson` field-for-field), `DiscoverFeedResponseDto {items, page, limit, total, hasMore}`. |
| `dto/partner-preference.dto.ts` | 101 | `UpdatePartnerPreferenceDto` (class-validator decorated) + `PartnerPreferenceResponseDto` interface. |
| `matches.module.ts` | +40/-1 | Wires it all together: `imports: [StorageModule]`; providers register `{provide: RECOMMENDATION_SERVICE, useClass: FilteredFeedStrategy}` and `{provide: SEARCH_STRATEGY, useClass: PostgresSearchStrategy}` plus the concrete classes and repositories. |

### Backend — existing files touched

| File | +/- | Change |
|---|---|---|
| `backend/apps/api/src/app.module.ts` | +2/-0 | Added `import { MatchesModule }` and registered it in the root `imports: []`. |
| `backend/apps/api/src/modules/profiles/services/profile.service.ts` | +18/-1 | **Bug fix.** Added `parseHeightToCm(value)`: matches `(\d+)\s*'\s*(\d+)` (e.g. `5'9"`), converts feet+inches → cm (`Math.round((feet*12+inches)*2.54)`), falls back to `parseLeadingNumber` for a plain numeric string. Changed the one call site at profile finalize from `parseLeadingNumber(physical.height...)` to `parseHeightToCm(...)`. Before this, `5'9"` was stored as `heightCm = 5`, silently breaking any height-range partner filter. |

### Backend — Neon / `DATABASE_URL` support

| File | +/- | Change |
|---|---|---|
| `backend/libs/database/src/prisma.service.ts` | +43/-18 | Constructor now builds `poolConfig` as `{ connectionString: db.url }` when `db.url` is set, else the old discrete `{host, port, user, password, database}`. Spread into the `PrismaPg` adapter config alongside the existing timeouts. Removed the temporary `log: ['query', 'warn', 'error']` (restored to `['warn', 'error']` — the `query` level was left in from an unrelated earlier debug session). Added private `describeTarget()`: parses `DATABASE_URL` for the boot-banner host/port/name so it never misreports `localhost` when actually connected to Neon. |
| `backend/libs/database/src/seed.ts` | +16/-7 | Same fix as `prisma.service.ts`: reads `process.env.DATABASE_URL`, passes `{connectionString: databaseUrl}` to `PrismaPg` when set, else the old discrete-field object. Without this the seeder would silently write to `localhost` even when `DATABASE_URL` was set for the app. |
| `backend/libs/config/src/configuration.ts` | +6/-0 | Added `database.url?: string` to the `AppConfig` interface; populated from `process.env.DATABASE_URL?.trim() \|\| undefined`. |
| `backend/libs/config/src/validation.ts` | +11/-5 | `DATABASE_HOST/PORT/USER/PASSWORD/NAME` changed from `.required()` to `.optional()`; added `DATABASE_URL: Joi.string().optional()`. Either a URL or the discrete fields now satisfies validation — `PrismaService` fails fast at boot with a real Postgres error if neither resolves to a working connection. |
| `backend/libs/config/src/config.service.ts` | +16/-1 | The "Configuration Loaded" boot banner's `Database` line now calls a new private `describeDatabaseTarget()` instead of printing `this.database.host:this.database.port` directly — same fix as `prisma.service.ts`, applied to the second (config-level) banner. |
| `backend/.env.example` | +8/-0 | Documented the two onboarding paths above `DATABASE_HOST`: **(A)** set a single `DATABASE_URL` for shared/managed Postgres, **(B)** leave it unset and fill the discrete fields for local Postgres. |
| `backend/.gitignore` | +3/-0 | Added `.neon` — a local Neon CLI artifact file, not a secret, but not something to commit. |

---

## PR #3 — `feat(discover): filter the feed by saved partner preferences`

### Rewritten

| File | +/- | Change |
|---|---|---|
| `backend/apps/api/src/modules/matches/filters/partner-preference-where.builder.ts` | +167/-23 | Substantially rewritten. Added: `MEANINGLESS_TOKENS` set (`any`, `any caste`, `any degree`, `any religion`, `any mother tongue`, `any city`, `any state`, `doesn't matter`, `doesnt matter`, `no preference`, `inter-caste ok`, `anywhere in india`, `nri ok`) — these are UI shorthand, never literal profile values, so they're now dropped instead of filtered on. Added `SelfAttributes` interface (`caste`, `currentCity`, `currentState`, `motherTongue`) and a `self?` param on `FeedWhereParams` — used to resolve `"Same Caste"` / `"Same City"` / `"Same State"` / `"Same Mother Tongue"` to the caller's own value. Added `extendedPreferences?: unknown` to `PreferenceFilters` — reads `diet`/`smoking`/`drinking`/`country` from the JSON blob. New helper functions: `resolveValues()` (token → literal-or-null, folding "Same X" and dropping meta tokens), `isLiteral()` (rejects empty/meta/grouped-label — i.e. containing `/` or `+` — values), `isSame()`, `pushIf()`, `hasText()`, `asRecord()`. Location handling special-cased: `preferredCities` values of `"Same City"`/`"Same State"` are routed to the `currentCity`/`currentState` columns respectively (previously both would have gone into a single `currentCity IN (...)` filter, which is wrong for "Same State"). Marital-status parsing now also uppercases and replaces spaces/hyphens with underscores before matching the enum list, so labels like `"Never Married"` map to `NEVER_MARRIED`. All multi-value string filters (`religion`, `caste`, `motherTongue`, `highestEducation`, `profession`, `currentCity`, `currentState`) changed from Prisma `{in: [...]}` to an `OR` of `{equals, mode: 'insensitive'}` per value — case-insensitive, because real data has mixed casing (`"sheikh"` vs `"Sheikh"`). `addEquals()` (new) applies the same case-insensitive-equals treatment to the single-value extended fields. |
| `backend/apps/api/src/modules/matches/recommendation/filtered-feed.strategy.ts` | +8/-3 | `getFeedForUser()` now calls `this.feedRepository.findSelf(userId)` instead of `findGender(userId)`, and passes both `myGender: self?.gender ?? null` and `self` into `buildFeedWhere(...)` (previously only `myGender` was passed). |
| `backend/apps/api/src/modules/matches/repositories/feed.repository.ts` | +23/-5 | `findGender(userId): Promise<Gender \| null>` **replaced** by `findSelf(userId): Promise<SelfProfile \| null>`, which selects `gender, caste, currentCity, currentState, motherTongue` in one query instead of just `gender`. Added the exported `SelfProfile` interface. |

### New

| File | Lines | Purpose |
|---|---|---|
| `backend/apps/api/src/modules/matches/filters/partner-preference-where.builder.spec.ts` | 129 | 10 unit tests: base clauses always present; opposite-gender applied/omitted correctly; empty/"Any"/meta tokens produce zero extra clauses; literal values become case-insensitive filters; `"Same Caste"` resolves to `self.caste` (and becomes a no-op with no `self`); `"Same City"`/`"Same State"` route to the correct column; grouped labels (`"Software / IT"`, `"B.E / B.Tech+"`) are dropped; marital-status labels normalize to enum values (and `"Doesn't Matter"`/`"Any"` are dropped); extended diet/smoking/country apply while a meta `drinking: "Any"` doesn't; age/height bounds apply. |

### Fixed (pre-existing test regression from PR #2)

| File | +/- | Change |
|---|---|---|
| `backend/libs/config/src/validation.spec.ts` | +20/-5 | The `it.each([...])` "fails when required variable is missing" table still listed `DATABASE_HOST/PORT/USER/PASSWORD/NAME` as required — but PR #2 made them optional (in favor of `DATABASE_URL`), so those 5 sub-tests were failing after PR #2 merged. Removed those 5 entries from the table (kept `REDIS_HOST/PORT`, `ELASTICSEARCH_NODE`, `SMTP_HOST/PORT`, `JWT_SECRET`, which are still genuinely required). Added a new test, `'passes with a single DATABASE_URL and no discrete DATABASE_* fields'`, asserting the intended new behavior explicitly. |

---

## PR #4 — `fix(discover): exclude invalid profiles and add remaining preference filters`

Found by cross-checking the feed filter against a full field/exclusion requirement list. All additive — no schema/DTO/route/response/UI changes.

| File | +/- | Change |
|---|---|---|
| `backend/apps/api/src/modules/matches/filters/partner-preference-where.builder.ts` | +27/-4 | Base `and[]` clauses changed from 2 to 3: added `{ isProfileComplete: true }` (defensive — all current rows already satisfy it) and expanded the single `user.is` clause from just `{ deletedAt: null }` to `{ deletedAt: null, status: 'ACTIVE', NOT: [{blocksMade: {some: {blockedUserId: currentUserId}}}, {blocksReceived: {some: {blockerId: currentUserId}}}] }`. The `status: 'ACTIVE'` check excludes `PENDING_VERIFICATION`/`SUSPENDED`/`DEACTIVATED`/`BANNED` users, which were previously visible in the feed. The `NOT: [...]` excludes both directions of a `UserBlock` row (a table that existed in the schema but was unused anywhere in the app). Also added two `addEquals()` calls: `addEquals(and, 'community', ext.ethnicity)` and `addEquals(and, 'subCaste', ext.subCaste)` — wiring two more of the standalone Partner Preferences page's extended fields into the filter, same pattern as the existing diet/smoking/drinking/country. |
| `backend/apps/api/src/modules/matches/filters/partner-preference-where.builder.spec.ts` | +51/-10 | Introduced a `BASE_CLAUSE_COUNT = 3` constant, replacing every hardcoded `toHaveLength(2)` assertion (the base-clause count changed). Rewrote the "always excludes..." test to assert the exact new `user.is {...}` shape. Added two new tests: `'applies extended community (ethnicity) and sub-caste preferences'` and `'always requires ACTIVE status and excludes both directions of a block'`. |

### Deliberately not implemented (documented in the code/PR, not silently skipped)
- **Annual income range** — schema has only `minIncomeLakhs` (a floor); a max would need a new column, which is a schema change.
- **Physical-status value matching** — `UserProfile.physicalStatus` stores an undocumented composite string (observed real value: `"Average · Fair · A+ · None"`); parsing it would mean guessing at an unverified format.
- **Horoscope compatibility** — the extended `hasHoroscope`/`horoscopeMatchRequired` flags exist, but applying them meaningfully overlaps compatibility-scoring/ranking, which is explicitly out of scope for this feed.

### Verification
Full backend suite **31/31 green** (12 builder unit tests, 2 new). Live on Neon: a `PENDING_VERIFICATION` profile (`dhatri`, FEMALE) that appeared in an earlier test run of the feed was confirmed **excluded** after this change, with no change to any other previously-verified scenario (empty prefs, religion filter, `Same Caste` resolution, pagination).

---

## Data-only changes (not in any PR — no code, nothing to review as a diff)

- **Neon migration/data move**: applied the 6 existing Prisma migrations to the (previously empty) shared Neon database via `prisma migrate deploy`; copied all local table data into Neon via `pg_dump`/`\COPY`. No migration files were added or edited — `schema.prisma` is unchanged by this work.
- **10 test accounts**: 5 male + 5 female finalized profiles inserted directly into Neon (SQL), partner preferences left open/`Any`, for manual on-device verification. Not application code.

---

## Everything explicitly *not* touched

Per the task constraints for the preference-filtering work: no changes to `schema.prisma`, API routes, the response DTO shape, `FirebaseAuthGuard`/authentication, pagination mechanics, photo/S3 logic, or any Flutter UI/layout/navigation/animation file.
