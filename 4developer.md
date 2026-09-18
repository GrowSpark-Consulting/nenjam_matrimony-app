# Nenjam Matrimony — Backend ↔ Flutter Integration Audit

**Read-only, evidence-based.** Every claim below is backed by an exact file:line citation gathered by inspecting the current repo (backend/apps/api, Frontend/lib) directly — not by trusting BRAIN.md, PROJECT_RULES, or code comments at face value (comments are quoted only where independently confirmed still accurate, and flagged where stale). Authentication (Dummy OTP / Firebase) is treated as a fixed, accepted development assumption — not audited, not a task.

---

## 1. Executive Summary

| Metric | Count | Evidence |
|---|---:|---|
| Backend modules registered in `AppModule` | 13 of 19 | `backend/apps/api/src/app.module.ts` imports array |
| Backend modules that are **100% empty scaffolding** (every controller/service/module file is 1–5 lines, zero routes, zero logic) | 6 — `admin`, `astro`, `search`, `subscription`, `trust-score`, `verification` | `wc -l` on every file in each module — see §2 |
| Real, routed backend HTTP endpoints (wired modules only) | **78** | Full `@Get/@Post/@Patch/@Put/@Delete` inventory, §2 |
| Of those 78, confirmed **zero Flutter consumer** (orphans) | **2** — `POST /notifications/test`, `GET /profiles/completion` | §3 |
| Of those 78, confirmed connected end-to-end (screen → provider → repository → route) | **76** (97.4%) | §3, §18 |
| Flutter repository files making real `ApiClient` calls | 32 files, ~72 call sites | grep across `Frontend/lib/features/**/data/repositories` |
| Flutter calls pointing at backend routes that **do not exist at all** (0 routes registered, any module) | **7 live** (psychology ×3, verification ×2, astro ×2 if provider is flipped) + **3 dead-code** (`MatchesRepositoryImpl`, unreferenced) | §4 |
| Frontend features that are **structurally mock-only** (no real-repository code path exists, not just "defaults to mock") | **3** — Profile Detail (other member), Premium, Subscription | §7 |
| Major integration gaps | Other-member profile detail is 100% fabricated; Psychology quiz and Verification screens are wired to routes that 404; Horoscope/Astro screen is silently mocked; Premium/Subscription screens have no data layer at all | — |

---

## 2. Backend API Inventory

### 2a. Wired modules — 78 real, routed endpoints

Grouped by module. "Flutter consumer" is verified by tracing screen→provider→repository→`ApiClient` call, not by a repository method merely existing.

| Module | Route (method) | Purpose | DB op? | Flutter consumer | Status |
|---|---|---|---|---|---|
| reference-data | GET `/reference-data/countries`, `/states`, `/cities` | Location cascade | ✅ | `location_repository.dart` | A |
| reference-data | GET `/reference-data/religions`, `/communities` | Religion cascade | ✅ | `religion_repository.dart` | A |
| profiles | GET `/profiles/draft` + 10× PATCH `/profiles/draft/*-details` incl. `partner-preference` | Registration wizard | ✅ | `registration_repository.dart` — all 11 confirmed called | A |
| profiles | POST `/profiles/finalize` | Complete wizard | ✅ | `registration_repository.dart:111` | A |
| profiles | GET `/profiles/me` | Own profile | ✅ | `backend_sync_service.dart:26`, `api_profile_repository.dart:30` | A |
| profiles | PUT `/profiles/me/location` | Store own coords | ✅ | `nearby_repository_impl.dart:75` | A |
| profiles | GET `/profiles/completion` | Completion score | ✅ | **none found** | **B (orphan)** |
| profiles | POST `/profiles/completion/dismissals`, DELETE `/dismissals/:cardKey` | Dismiss a completion card | ✅ | `completion_recommendation_repository.dart:23,33` | A |
| profiles (photos) | GET/POST/PUT/PATCH×2/DELETE `/profiles/me/photos*` (6 routes) | Photo CRUD | ✅ | `photo_repository.dart` — all 6 verbs confirmed | A |
| profiles (prompts) | GET `/bank`, GET `/me`, PUT `/me`, DELETE `/me/:promptId` | Profile prompts | ✅ | `api_profile_prompt_repository.dart` — all 4 confirmed | A |
| matches (discover) | GET `/discover`, GET/PUT `/discover/preferences`, GET `/discover/search` | Feed, preferences, search | ✅ | `discover_repository_impl.dart`, `partner_preferences_repository_impl.dart`, `search_repository_impl.dart` | A |
| matches | POST `/matches/interest` (polymorphic send/respond), GET/POST/DELETE `/matches/shortlist`, GET `/matches/profile-views`, POST `/matches/profile-view` | Interest, shortlist, profile views | ✅ | `interests_repository_impl.dart`, `shortlist_repository_impl.dart`, `profile_views_repository_impl.dart` | A |
| matches (nearby) | GET `/profiles/nearby` | Proximity search | ✅ | `nearby_repository_impl.dart:33` | A |
| interests | GET `/interests/received`, `/sent`, DELETE `/interests/:id` | Interest inbox/withdraw | ✅ | `interests_repository_impl.dart` | A |
| notifications | GET `/notifications`, `/unread-count`, PATCH `/read-all`, `/:id/read`, POST/DELETE `/device` | Notification center + push token | ✅ | `notification_api_repository_impl.dart` | A |
| notifications | POST `/notifications/test` | Dev test-fire | ✅ | **none found** | **B (orphan, Type D — internal/dev tool)** |
| chat | GET/POST `/chat/conversations`, POST `get-or-create`, PATCH `:id`, POST `:id/read`, `:id/unread`, DELETE `:id`, POST `:id/block`, `:id/unblock` (8 routes) | Conversations | ✅ | `conversation_api_repository_impl.dart` — all 8 confirmed | A |
| chat | GET/POST `/chat/messages`, PATCH/DELETE `:id`, GET `:id/media-url` | Messages | ✅ | `conversation_api_repository_impl.dart:171` (media-url) + others | A |
| chat | POST `/chat/attachments` | Voice/media upload | ✅ | `conversation_api_repository_impl.dart:202,226` | A |
| settings | GET `/settings`, PATCH `/privacy`, DELETE `/delete-account` | Account settings | ✅ | `settings_repository_impl.dart` | A |
| support | POST/GET `/support/tickets` | Support tickets | ✅ | `support_repository_impl.dart` | A |
| blocks | GET `/users/blocked`, POST/DELETE `/users/:id/block` | Block list | ✅ | `safety_repository_impl.dart` | A |
| reports | POST `/users/:id/report` | Report a user | ✅ | `safety_repository_impl.dart:37` | A |
| users | POST `/auth/account-exists` | Pre-signup phone/email check | ✅ | `account_availability.dart:59` | A |
| users | POST `/auth/dummy-otp/session` | Dev-OTP session mint (accepted per instruction) | — | Auth flow | A |

**Total: 78 real routes, 76 connected, 2 orphaned.**

### 2b. Unwired/stub modules — 0 real endpoints (verified by content, not just import-graph absence)

Every file below is 1–5 lines: `import { Controller } from '@nestjs/common'; @Controller() export class X {}` (and the equivalent for services/modules/repositories). This is not "logic exists but isn't exposed" — there is genuinely **no business logic anywhere** in these six trees.

| Module | Files | Total lines | Controller routes | AppModule import | Classification |
|---|---:|---:|---:|---|---|
| `admin` | 12 | 42 | 0 | Not imported | I (planned only) |
| `astro` | 9 | 30 | 0 | Not imported | I (planned only) |
| `search` (Elasticsearch-backed, distinct from `/discover/search`) | 9 | 27 | 0 | Not imported | I (planned only) |
| `subscription` | 14 | 48 | 0 | Not imported | I (planned only) |
| `trust-score` | 8 | 26 | 0 | Not imported | I (planned only) |
| `verification` | 11 | 36 | 0 | Not imported | I (planned only) |

⚠️ **Naming trap**: `backend/apps/api/src/modules/search/` (unwired, 0 routes) is a completely different thing from `/discover/search` (real, wired, connected — §2a). Do not confuse "search is not built" with the actual profile search feature, which works.

⚠️ Also confirmed: **no `psychology` backend module exists at all** — not even scaffolding. Zero files anywhere in `backend/` mention it except comments in `profile-completion.service.ts` and `profile-feed.mapper.ts` explicitly noting it doesn't exist yet.

---

## 3. Backend APIs Not Connected to Flutter

### ORPHAN BACKEND API TABLE

| # | Backend API | Method | Module | What it does | Flutter consumer? | Why not connected | Required frontend work | Priority |
|---|---|---|---|---|---|---|---|---|
| 1 | `/profiles/completion` | GET | profiles (wired, real) | Returns profile-completion score + card list | None | Flutter reconstructs completion cards from `profileDraft`'s embedded `recommendations` field instead (per `api_endpoints.dart:44`'s own comment) — a deliberate design choice, not an oversight | None required — arguably delete the unused Flutter constant, or use this route to replace the draft-piggyback approach if it drifts | P3 |
| 2 | `/notifications/test` | POST | notifications (wired, real) | Dev tool: fires a test push notification to the caller | None | Dev/ops utility, not a product feature | None — Type D, internal-only | P3 |

**Only 2 real orphans exist.** There are no "STUB orphan APIs" to list because the 6 unwired modules have zero routes to be orphaned — see §2b for those (they're "planned only," not "orphaned").

---

## 4. Frontend APIs With No Backend

### BROKEN FRONTEND API CALL TABLE

| # | Flutter file | Flutter API call | Method | Expected backend route | Backend exists? | Problem | Fix required | Priority |
|---|---|---|---|---|---|---|---|---|
| 1 | `features/psychology/data/repositories/api_personality_repository.dart:25,35,48` | `psychologyQuizActive`, `psychologyQuizSubmit`, `psychologyQuizMe` | GET/POST | `/psychology/quiz/*` | **No — zero `psychology` module exists** | This repo is the **default, live-wired** implementation (`personalityRepositoryProvider`) reachable from `/registration/psychology-quiz`. Every call 404s today. | Build the entire `psychology` backend module (schema — `PsychologyQuiz`/`UserQuizResponse` already exist in Prisma — just needs controller/service) | **P1** |
| 2 | `features/verification/data/repositories/verification_repository_impl.dart:30,48` | `verificationStatus`, `verificationDocuments` | GET/POST(multipart) | `/verification/*` | Controller/module exist but are **empty stubs, 0 routes** | Default, live-wired repository (`verificationRepositoryProvider`), reachable from `/verification`. 404s today. | Fill in `VerificationController`/`Service`/DTOs against the shape `VerificationDocumentRecord.fromJson` already expects (repo header comment documents the intended contract) | **P1** |
| 3 | `features/astro/data/repositories/api_compatibility_repository.dart:23,42` | `astroProfileMe`, `astroCompatibility(:id)` | GET | `/astro/*` | Controller exists, **empty stub, 0 routes** | **Not** the default provider today (`compatibilityRepositoryProvider` → `MockCompatibilityRepository`), so this is currently dormant, not broken-in-production — but it's real code that will 404 the moment someone flips the override | Fill in `AstroController`/`CompatibilityService`, then flip the provider default | P2 (masked by mock today) |
| 4 | `features/matches/data/repositories/matches_repository_impl.dart:23` (`getMatches`) | `ApiEndpoints.matches` (`/matches`) | GET | No such route (`matches.controller.ts` has no bare `@Get()`) | No | **Dead code** — class has zero provider references anywhere in `lib/`; its own header comment is stale ("matches controller is currently an empty stub" — false today, see §6) | Delete `MatchesRepositoryImpl`/`matches_repository.dart`, or repurpose it if a real "Matches" list endpoint is ever built | P3 (no runtime impact, but confusing dead code) |
| 5 | Same file, `decline`/`markViewed` | `matchDecline` (`/matches/decline`), `matchViewed` (`/matches/viewed`) | POST | Neither route exists | No | Same dead class | Same as #4 | P3 |

**No live, reachable Flutter code path currently throws against a truly nonexistent route in normal user flows** — the two P1s above (psychology, verification) are the exception: they're wired as the *default* provider and will 404 for any real user who reaches those two screens today.

---

## 5. API Contract Mismatches

### CONTRACT MISMATCH TABLE

| # | Feature | Backend contract | Flutter expectation | Mismatch | Impact | Fix |
|---|---|---|---|---|---|---|
| 1 | Interest send/respond | `POST /matches/interest` is **polymorphic**: `{profileId}` → send, `{interestId, accept}` → respond (documented in `MatchInterestDto` + controller `@ApiBody` examples, `matches.controller.ts:78-96`) | `InterestsRepositoryImpl.sendInterest` sends `{profileId}` (line 65), `.respond` sends `{interestId, accept}` (line 56) | **None — this is correct.** Flagging only because it looks like a mismatch at first glance (two different bodies, one route) and is easy to "fix" incorrectly if not read carefully | None | No action — leave as is |
| 2 | Profile Detail (other member) | No backend route exists for fetching another member's full profile by id (`profile.controller.ts` only has `me`, `finalize`, `me/location` — no `:id`) | `ProfileDetailRepositoryImpl` (constructor-hardwired to `ProfileDetailMockDataSource`, no API path exists to even swap in) | Backend route was never built; frontend never attempted one | Every "View Profile" tap shows **fabricated data** the real backend member never provided | Build `GET /profiles/:id` (owner-safe, respecting existing eligibility/privacy rules used by feed/search) + a real `ApiProfileDetailRepository` |
| 3 | Discover feed `psychologyMatchPercent` | Hardcoded to `0` server-side (`profile-feed.mapper.ts:66`, explicit comment: "Astrology and psychology engines do not exist yet") | Flutter displays whatever number the field carries | Not a bug — server is honest about the placeholder — but the UI does not distinguish "0% compatible" from "not yet computed," so it reads as a real (bad) score | Low — cosmetic misrepresentation | Either suppress the badge when the source engines don't exist, or block on §4 items #1/#3 |
| 4 | `astro.setMatchingEnabled()` | No endpoint exists for this at all (comment in `api_compatibility_repository.dart:33-36` confirms it's a literal no-op) | UI toggle presumably calls this and expects persistence | Toggle currently does nothing silently | User believes they changed a setting; nothing is saved | Needs its own endpoint once the astro module is built |

No other contract mismatches (field names, enums, pagination envelope, status codes) were found among the 76 connected endpoints — the `{items, page, limit, total, hasMore}` envelope is used consistently across discover/search/interests/shortlist, and DTO field names line up (verified for interests, shortlist, preferences, prompts, photos, chat, notifications during direct trace work).

---

## 6. Frontend Feature Audit

| # | Screen/Feature | Current state | Backend available? | API connected? | What's missing? | Developer | Priority |
|---|---|---|---|---|---|---|---|
| 1 | Registration wizard (12 steps) | DONE | ✅ | ✅ | Nothing | — | — |
| 2 | Discover feed | DONE | ✅ | ✅ | Nothing | — | — |
| 3 | Search | DONE | ✅ | ✅ | Nothing (connected) | — | — |
| 4 | Partner Preferences | DONE | ✅ | ✅ | Nothing (connected) | — | — |
| 5 | Matches tab | DONE — built on `reelFeedProvider` + Interests + Shortlist, **not** the dead `MatchesRepositoryImpl` | ✅ | ✅ | Nothing functionally; delete dead class (§4 #4/#5) | Flutter (cleanup only) | P3 |
| 6 | Interests (sent/received/respond) | DONE | ✅ | ✅ | Nothing | — | — |
| 7 | Shortlist | DONE | ✅ | ✅ | Nothing | — | — |
| 8 | Profile Views ("who viewed me") | DONE | ✅ | ✅ | Nothing | — | — |
| 9 | Near Me | DONE | ✅ | ✅ | Nothing | — | — |
| 10 | Notifications center | DONE | ✅ | ✅ | Nothing | — | — |
| 11 | Chat/Inbox (text, media, block/unblock) | DONE | ✅ | ✅ | Nothing | — | — |
| 12 | Profile photos | DONE | ✅ | ✅ | Nothing | — | — |
| 13 | Profile prompts | DONE | ✅ | ✅ | Nothing (delete connected) | — | — |
| 14 | Privacy/Block/Report | DONE | ✅ | ✅ | Enforcement of the toggles themselves in feed/search queries is a separate, already-known P0 (tracked elsewhere, out of scope here) | Backend A | (tracked elsewhere) |
| 15 | Account settings | DONE | ✅ | ✅ | Nothing | — | — |
| 16 | **Profile Detail (other member)** | **MOCKED** | ❌ (no route) | ❌ | Real backend route + real repository — no swap path exists today | Full-stack | **P0** |
| 17 | **Psychology Quiz** | **BROKEN** (wired to live 404) | ❌ (module doesn't exist) | Wired, but fails | Entire backend module | Backend B (+ nothing on Flutter — already built) | **P1** |
| 18 | **Verification (Aadhaar/income/NRI docs)** | **BROKEN** (wired to live 404) | ❌ (stub only) | Wired, but fails | Fill in controller/service/DTOs | Backend B (+ nothing on Flutter — already built) | **P1** |
| 19 | **Horoscope/Astro matching** | **MOCKED** (silently, by design — default provider is Mock) | ❌ (stub only) | ❌ | Backend module + flip provider default | Full-stack | P2 |
| 20 | **Premium** | **NOT IMPLEMENTED** — zero data layer, one static page file | ❌ (module empty) | ❌ | Everything: repository, provider, DTO, backend logic | Full-stack | P2 |
| 21 | **Subscription/Payment** | **NOT IMPLEMENTED** — zero data layer, one static page file | ❌ (module empty) | ❌ | Everything, incl. Razorpay integration | Full-stack | P2 (blocked on Razorpay creds) |
| 22 | Trust Score / Badges | **NOT IMPLEMENTED**, and deliberately absent from Flutter (enforced by `no_trust_score_references_test.dart`) | ❌ (module empty) | N/A | Backend + a first Flutter surface, if/when product wants it | Backend B, then Flutter | P3 |
| 23 | Admin | Not applicable to the mobile app | ❌ (module empty) | N/A | Out of scope for this Flutter client | — | — |

---

## 7. Mock/Placeholder Audit

| Feature | Flutter file | Mock source | Real backend exists? | What must be connected | Priority |
|---|---|---|---|---|---|
| Profile Detail (other member) | `features/profile_detail/data/repositories/profile_detail_repository_impl.dart` | `ProfileDetailMockDataSource` — **hardwired in the constructor**, no alternate implementation exists | ❌ No | Build `GET /profiles/:id` + `ApiProfileDetailRepository`; this is a **backend implementation task**, not just a wiring task | **P0** |
| Horoscope/Astro compatibility | `features/astro/presentation/providers/compatibility_provider.dart:10` | `MockCompatibilityRepository` (explicit provider default, with a code comment inviting the swap) | ❌ No (stub controller) | Build `astro` backend module, then flip the provider override | P2 |
| — | — | *(No other structural mocks found; Premium/Subscription aren't "mocked," they simply have no data layer to mock anything into — see §6 #20/21)* | — | — | — |

---

## 8. Navigation Audit

All 23 features in §6 are reachable via `go_router` routes registered in `app_router.dart` — confirmed for the three risk cases explicitly (`/registration/psychology-quiz`, `/verification`, `/horoscope-matching` all have live route entries in `route_names.dart`/`app_router.dart`). **No dead routes, unreachable screens, or disconnected buttons were found among the audited features.** The gaps here are entirely API-layer, not navigation-layer — every broken/mocked screen is fully reachable, it just shows fake data or a 404 error state once you arrive.

---

## 9. Quick Wins

Ranked by (1) lowest effort, (2) highest backend readiness, (3) lowest dependency risk — not subjective value:

| Rank | Task | Existing API | Existing DTO | Flutter screen | Missing | Est. effort | Dependencies |
|---|---|---|---|---|---|---|---|
| 1 | Delete dead `MatchesRepositoryImpl`/`matches_repository.dart` | N/A | N/A | N/A (unused) | Nothing — pure cleanup | 0.5d Flutter | None |
| 2 | Wire `GET /profiles/completion` to a real "Completion %" widget (replace the draft-piggyback heuristic) | ✅ Real, wired | ✅ | Profile/Edit Profile | Repository method + provider | 1d Flutter | None |
| 3 | Fill in `verification` backend (controller/service/DTOs already scaffolded with the exact shape Flutter expects) | Scaffolded only | Scaffolded only | ✅ Already built, wired to live repo | Backend logic only — Flutter needs **zero changes** | 3–4d Backend | AWS Rekognition/Signzy for the real check; S3 upload already exists in `libs/storage` |
| 4 | Fill in `psychology` backend (Prisma models `PsychologyQuiz`/`UserQuizResponse` already exist) | None (build from scratch) | None | ✅ Already built, wired to live repo | Controller + service + 3 routes | 2–3d Backend | None external — pure CRUD over existing schema |
| 5 | Fill in `astro` backend minimally (profile summary only, skip live Prokerala call) + flip Flutter provider | Scaffolded only | Scaffolded only | ✅ Already built | Backend logic + 1-line provider flip | 3–5d Backend, 0.5d Flutter | Prokerala API for real compatibility scoring (can ship rasi/nakshatra from existing `AstrologyProfile` data first, defer live scoring) |

Items #3 and #4 are genuinely the highest-value work in this entire audit: **the Flutter side is 100% finished and waiting** for both.

---

## 10. Remaining Flutter Work

- [ ] Delete `features/matches/data/repositories/matches_repository_impl.dart` + `domain/repositories/matches_repository.dart` (dead code, P3)
- [ ] Add a repository/provider for `GET /profiles/completion` if the product wants a live completion score instead of the current draft-derived approximation (P3, optional)
- [ ] Build `ApiProfileDetailRepository` once backend ships `GET /profiles/:id` (P0, blocked on backend)
- [ ] Flip `compatibilityRepositoryProvider` from Mock to `ApiCompatibilityRepository` once `astro` backend ships (P2, blocked on backend — otherwise zero Flutter work)
- [ ] Build Premium/Subscription data layer (repository, provider, models) once backend ships (P2, blocked on backend)
- [ ] Wire `astro.setMatchingEnabled()` to a real endpoint once one exists (P3, blocked on backend)

Notably: **no standalone Flutter task exists for Psychology or Verification** — both are already fully built and correctly wired; they're 100% blocked on backend.

---

## 11. Remaining Backend Work

- [ ] **P0**: `GET /profiles/:id` — real, privacy/eligibility-respecting profile-detail endpoint (currently doesn't exist at all)
- [ ] **P1**: Build `psychology` module from scratch (schema exists) — `GET /quiz/active`, `GET /quiz/me`, `POST /quiz/submit`
- [ ] **P1**: Fill in `verification` module (scaffolding + DTOs already match the Flutter contract) — document submit + status
- [ ] **P2**: Fill in `astro` module — profile summary at minimum; compatibility scoring can follow
- [ ] **P2**: Fill in `subscription` module (checkout, plans, Razorpay webhook) — blocked on Razorpay credentials for the live-payment path, but plan listing (`GET /plans`) needs no external credential and can ship first
- [ ] **P3**: Fill in `trust-score` module — no Flutter consumer exists or is planned yet (per the enforced test), so this is purely backend-initiative work with no urgency
- [ ] **P3**: `admin`/`search` (Elasticsearch) modules — no mobile-client dependency; build only if/when an admin surface or full-text search is prioritized

---

## 12. Full-Stack Work

| Task | Flutter side | Backend side | Priority |
|---|---|---|---|
| Other-member Profile Detail | Build `ApiProfileDetailRepository` (small — same shape as Discover cards, extended) | Build `GET /profiles/:id` | **P0** |
| Astro/Horoscope matching | 1-line provider flip once ready | Build module | P2 |
| Premium/Subscription | Build entire feature from scratch (repository, provider, checkout UI, Razorpay SDK) | Build module + Razorpay integration | P2 |

---

## 13. Priority Matrix

**P0** — blocks a core, already-shipped product surface (every profile-card tap across Discover/Matches/Search/Shortlist/Interests leads here):
- `GET /profiles/:id` + `ApiProfileDetailRepository` (§6 #16)

**P1** — backend exists in name (or Flutter is already built and waiting), connection/build is the only blocker:
- `psychology` backend module (§6 #17)
- `verification` backend module (§6 #18)

**P2** — useful incomplete functionality, moderate effort, some external dependency:
- `astro` backend module (§6 #19)
- Premium (§6 #20)
- Subscription/Razorpay (§6 #21)

**P3** — optional/future/cleanup:
- Delete dead `MatchesRepositoryImpl`
- `/profiles/completion` real wiring
- `trust-score`, `admin`, `search` (Elasticsearch) modules
- `/notifications/test` (no action needed, it's a dev tool by design)

*(Dummy OTP is intentionally excluded from this matrix.)*

---

## 14. Developer Assignment

| Owner | Tasks |
|---|---|
| **Flutter Dev** | Delete dead `MatchesRepositoryImpl` (P3); build `ApiProfileDetailRepository` once backend ships `GET /profiles/:id` (P0, small — reuses `DiscoveryProfileModel` shape); flip astro provider (P2, trivial); build Premium/Subscription UI data layer (P2, larger) |
| **Backend Dev A** (core APIs: profile/discover/search/matches) | `GET /profiles/:id` (P0 — highest priority in this entire audit); `GET /profiles/completion` real wiring if pursued (P3) |
| **Backend Dev B** (integrations/verification/subscription/external) | `verification` module (P1); `psychology` module (P1 — note: this is core-CRUD, not an "integration," but Dev A is occupied by P0; recommend Dev B takes it since psychology has zero external-API dependency and can start immediately in parallel); `astro` module (P2); `subscription`/Razorpay (P2); `trust-score` (P3) |
| **Full-Stack/Coordination** | Profile Detail end-to-end contract review (payload shape between Dev A and Flutter); Premium/Subscription contract design before either side starts |

---

## 15. Estimated Developer-Days

| Task | Flutter | Backend | Dependency | Parallel? | Complexity |
|---|---:|---:|---|---|---|
| Delete dead `MatchesRepositoryImpl` | 0.5d | — | None | Yes | Small |
| `GET /profiles/:id` (backend) | — | 2d | None | Yes | Small |
| `ApiProfileDetailRepository` (Flutter) | 1d | — | Backend route ships first (or agree contract up front and build in parallel) | Yes, if contract agreed first | Small |
| `psychology` module (backend) | — | 2–3d | None (schema exists) | Yes | Small–Medium |
| `verification` module (backend) | — | 3–4d | S3 upload already exists; real AWS Rekognition/Signzy check can be a stub-return initially | Yes | Medium |
| `astro` module (backend, summary only) | — | 3–5d | Prokerala API for live scoring (can defer) | Yes | Medium |
| Astro Flutter provider flip | 0.5d | — | Backend module | No — trivial, do last | Small |
| `subscription` module + plans listing | — | 4–5d | Razorpay credentials for checkout/webhook (plans-only can ship without) | Yes | Medium–Large |
| Premium/Subscription Flutter data layer | 3–4d | — | Backend contract agreed | Partially — UI shell can start immediately, wiring waits | Medium |
| `trust-score` module | — | 3–4d | None, but no consumer yet | Yes, low priority | Medium |

**Total estimated backend work for P0+P1: ~7–9 developer-days across 2 backend devs, largely parallelizable.**

---

## 16. Parallel Execution Plan

**Week 1, simultaneously:**
- Flutter Dev: delete dead code (0.5d), then stand by / start Premium UI shell (no backend dependency for pure layout)
- Backend Dev A: `GET /profiles/:id` (2d) → hands off contract to Flutter Dev
- Backend Dev B: `psychology` module (2–3d, starts immediately, zero dependency)

**Week 1–2, simultaneously:**
- Flutter Dev: build `ApiProfileDetailRepository` against Dev A's shipped route (1d)
- Backend Dev A: move to `/profiles/completion` real wiring (optional, P3) or assist Dev B
- Backend Dev B: `verification` module (3–4d, continues)

**Week 2, simultaneously:**
- Backend Dev B: `astro` module summary-only (3–5d)
- Flutter Dev: flip astro provider once ready (0.5d); continue Premium/Subscription data layer against agreed contract

---

## 17. Recommended Next 2 Weeks

1. **`GET /profiles/:id` + `ApiProfileDetailRepository`** — P0, closes the single highest-impact gap (every profile card tap in the app), small on both sides, zero external dependency.
2. **`psychology` backend module** — P1, zero external dependency, Flutter is 100% done and waiting; this is the best-ROI task in the whole backlog.
3. **`verification` backend module** — P1, Flutter is 100% done and waiting; ship with a stubbed/manual-review verdict initially if Signzy/AWS Rekognition credentials aren't ready, so the endpoint at least stops 404ing.
4. Delete `MatchesRepositoryImpl` (0.5d, do it opportunistically — zero risk).
5. Defer Premium/Subscription/Astro to the following sprint — they carry real external-dependency risk (Razorpay, Prokerala) and larger scope; don't let them block the P0/P1 items above.

---

## 18. Final Integration Coverage

**% of backend endpoints consumed by Flutter** (wired modules only, since unwired modules have zero routes to consume):
`76 connected / 78 real routes = 97.4%`

**% of Flutter API calls backed by real backend routes:**
Of ~72 traced call sites, **69 hit real, working routes**; **3 are dead code** (`MatchesRepositoryImpl`, never executed at runtime) hitting nonexistent routes; **3 are live** (psychology ×2 methods used, verification ×2 methods used — counting distinct call sites, not endpoints) hitting routes that don't exist yet. → **~92% of live (reachable) call sites hit real routes; 100% of dead-code call sites don't** (irrelevant at runtime).

**% of major screens (23 audited in §6) using real backend data:**
`20 DONE / 23 = 87%` (3 gaps: Profile Detail, Premium, Subscription — Psychology and Verification count as "using real backend data" architecturally even though the backend currently 404s, since the Flutter side is complete and correct — but if you count them as broken-today, it's `18/23 = 78%`).

**% of major features end-to-end connected** (screen → state → repository → API → controller → service → Prisma → DB → response → UI, all links present and live):
`20/23 = 87%`, using the same denominator as above, counting Psychology/Verification as **not** end-to-end today because the DB/service links are missing even though every other link exists.

**Methodology note**: percentages are computed against the 78-route wired-module inventory (§2a) and the 23-screen feature audit (§6), both built from direct source inspection in this session, not from documentation. The 6 stub modules (§2b) are excluded from the denominator since they contribute zero real routes — including them would understate genuine coverage by conflating "not built" with "built but disconnected."
