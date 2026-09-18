# Nenjam Matrimony — Current Implementation Status

**Audit date:** 2026-09-18
**Commit/branch:** `main` @ `3077b14` (+ uncommitted working-tree changes from 4 completed integration tasks this session: Search, Partner Preferences, Feed Invalidation/Realtime, Profile Prompt Delete — see §L)

**Method:** Every claim below is anchored to a file read, a grep, or a command run today. Nothing is taken from prior reports, TODO comments, or doc claims without independent verification in this session.

## Overall

```
DONE:      54
PARTIAL:   16
BROKEN:     3
NOT DONE:  36
BLOCKED:    3
ORPHANED:   4
```
(116 items scored across §1–19; §E is a condensed cross-section, not an exhaustive re-listing)

## 🔴 Fix First
1. **Registration wizard's caste-no-bar toggle can silently overwrite Partner Preferences base fields** — `applyOnboardingReligion()` still round-trips through the draft-materialize path, which unconditionally recomputes all 10 base preference columns from possibly-stale draft data.
2. **`POST /auth/dummy-otp/session` — live, unauthenticated Firebase-session-minting bypass** — works in any `NODE_ENV` when `DUMMY_OTP_ENABLED=true`.
3. **Privacy toggles are write-only** — `profileVisibleToPremiumOnly`/`hidePhotosFromNonConnections` are saved but read by zero feed/search/nearby/shortlist/profile-view query.
4. **Other-member profile detail is 100% fabricated client-side data** — `ProfileDetailMockDataSource` synthesizes family/horoscope/bio from `id.hashCode`; no backend endpoint exists to replace it.
5. **Committed Prisma client is stale** — 21 `tsc` errors on a clean clone (`religion`/`community` delegates missing) until `prisma generate` is run.

## 🟡 Then Build
1. Verification module (Aadhaar/income/NRI) — Flutter fully built, backend 4-line stub, not in `AppModule`.
2. Subscription + Razorpay + entitlement enforcement — zero revenue path, zero gating anywhere.
3. Badge derivation — 5 hardcoded `false`s in `ProfileFeedMapper` (`isVerified`, `isPremium`, `isPsychologyCompleted`, `horoscopeAvailable`, `photoProtected`).
4. Psychology module backend (models + Flutter UI exist; zero backend module).
5. iOS APNs configuration — Dart side complete, zero native entitlement/background-mode config.

## 🔵 External APIs Required
1. Firebase Phone Auth SMS billing (Blaze plan) — still `BILLING_NOT_ENABLED`, mock OTP is the default.
2. Signzy (Aadhaar/KYC) — 0 code references anywhere.
3. AWS Rekognition (face verification) — 0 code references anywhere.
4. Prokerala (horoscope/Kundli) — 2 empty stub classes, no client.
5. Razorpay — 3 empty stub controllers, no npm package, no Flutter SDK.

## 🗄️ DB Changes Required
1. **None required** for any of the P0/P1 items above — every gap identified is a missing service/controller implementation over an *already-existing* schema, or a client-side sync issue. Verification (`KycVerification`, `FaceVerification`), Subscription (`SubscriptionPlan`, `UserSubscription`, `PaymentTransaction`), Psychology (`PsychologyQuiz`, `QuizQuestion`, `UserQuizResponse`), Trust score (`TrustScoreLog`) — all modeled, all unused by any live code path.
2. A migration is needed **only if** `SubscriptionPlanName` gains a `DIAMOND` tier (product decision, not yet made) or `extendedPreferences` is promoted onto `/discover/preferences`'s DTO (also a product/backend decision).
3. No orphaned/unused model was found that should be *dropped* — `RefreshToken` is the one clearly dead table (zero writes anywhere), safe to remove in a cleanup migration.

## 👥 Team Next Steps
**Frontend:** iOS APNs entitlements; wire `MatchesRepositoryImpl` or retire it; premium plan UI once backend plans endpoint ships.
**Backend 1:** Enforce privacy flags in every feed/search/nearby/shortlist/profile-view query; build `GET /profiles/:id`; regenerate Prisma client.
**Backend 2:** Verification module (Signzy-gated document flow first, real Signzy call second); Subscription + Razorpay + entitlement guard.

---

## 1. AUTHENTICATION

| Item | Status | Evidence |
|---|---|---|
| Firebase email/password | DONE | `firebase_auth_service.dart`, `AuthRepositoryImpl` |
| Phone OTP | BLOCKED | `otp_verifier.dart`: `MockOtpVerifier` accepts any non-empty code, default in every debug build. Real `FirebasePhoneOtpVerifier` complete, unused. Root cause unchanged: Firebase SMS billing off. |
| Email verification | DONE | `firebase_auth_service.dart:54,87` |
| Forgot password | DONE | `forgot_password_controller.dart` |
| Session restoration | DONE | `app_router.dart` awaits `authStateChangesProvider.future` |
| Logout | DONE | `logout_flow.dart`; teardown in `main.dart`'s auth-state listener |
| Route guards | PARTIAL | `_signedInLocally()` (SharedPreferences bool) admits a signed-out device to protected UI routes; API calls still 401 correctly |
| Backend guard (`FirebaseAuthGuard`) | DONE | Per-controller `@UseGuards`, no bypass in the guard itself |
| Dummy-OTP bypass | **BROKEN (security)** | `POST /auth/dummy-otp/session` — unauthenticated, mints a real Firebase custom token, works in **any** `NODE_ENV` when `DUMMY_OTP_ENABLED=true` |
| 401 handling | DONE | `api_interceptor.dart` — one force-refresh retry, then teardown |
| Backend JWT | NOT DONE | `JWT_SECRET` required by Joi, zero `@nestjs/jwt` dependency, never read |
| Username signup | NOT DONE | 0 hits for `username` in schema or backend |

## 2. REGISTRATION

| Item | Status | Evidence |
|---|---|---|
| 10-section wizard | DONE | All `PATCH /profiles/draft/*` + `POST /profiles/finalize` wired |
| Backend validation | DONE | Global `ValidationPipe`, per-DTO `class-validator` decorators |
| Skip logic | DONE | Steps 5/6 nullable, `finalize()` enforces only mandatory fields |
| Profile completeness % | PARTIAL | Formula reads `KycVerification(APPROVED)` rows that **nothing can create** — 100% unreachable |
| Preferences persistence | **PARTIAL → improving this session** | Base 10 fields now via `GET`/`PUT /discover/preferences` (this session's work); `extended` fields (diet/mangalik/etc.) still only via the registration draft, with no safe channel from the standalone Partner Preferences screen (see §F CRITICAL #1) |

## 3. PROFILE

| Item | Status | Evidence |
|---|---|---|
| Own profile (`GET /profiles/me`) | DONE | Returns profile + photos + partnerPreference + astrology + completion |
| Edit profile | DONE | Reuses draft PATCH routes |
| **Other-member profile detail** | **BROKEN** | `ProfileDetailMockDataSource` — zero network call, fabricates family/horoscope/bio from `base.id.hashCode`. No `GET /profiles/:id` exists — and per `profile.controller.ts:12-18`'s own comment, this is **deliberate**: other-member reads are meant to live in the matches module, but no module actually provides profile-detail-shaped data (only feed-card shape) |
| Profile privacy (backend enforcement) | **BROKEN** | Flags stored, read by 0 queries |
| Family info capture | DONE | `family-details.dto.ts`, 25 decorators |
| Family info in other-member view | NOT DONE | No detail endpoint exists (see above) |
| Partner preferences (base fields) | **DONE (this session)** | `GET`/`PUT /discover/preferences`, full round-trip conversion, 30 tests |
| Partner preferences (extended fields) | **NOT DONE** | No backend field exposes `extendedPreferences` via any safe endpoint (see §F CRITICAL #1) |
| Profile prompts — add/replace | DONE | `PUT /profiles/prompts/me` |
| Profile prompts — **delete one** | **DONE (this session)** | `DELETE /profiles/prompts/me/:promptId`, IDOR-verified safe, 16 tests |
| Profile completeness card | PARTIAL | Same KYC-dependency issue as above |

## 4. PHOTOS

| Item | Status | Evidence |
|---|---|---|
| Upload → S3 | DONE | `photo.service.ts`, rollback on DB failure |
| Presigned URLs | DONE | Never public-read |
| Crop/compress | DONE | Pure-Dart, off-UI-isolate |
| Primary/delete/reorder | DONE | All 3 routes real |
| Max photos | PARTIAL | Hardcoded `6`, not plan-aware (seeder promises 4/10) |
| Face detection | NOT DONE | No Rekognition |
| Moderation/approval | NOT DONE | `isApproved` column dead — never set true, never filtered |
| Selfie | NOT DONE | Deliberately removed from registration per its own header comment |
| Family/background photo | NOT DONE | 0 references anywhere |
| Photo privacy (`hidePhotosFromNonConnections`) | **BROKEN** | Stored, never read by `ProfileFeedMapper` |

## 5. DISCOVER / SEARCH / MATCHES

| Item | Status | Evidence |
|---|---|---|
| Discover feed | DONE | `GET /discover`, Redis-cached, progressive fallback |
| **Search** | **DONE (this session)** | Was: client-side filter over one feed page. Now: `GET /discover/search`, real pagination, query preserved across silent refresh |
| Nearby | DONE | Bounding-box + Haversine, no coordinate leakage |
| Matches reel | PARTIAL | `reelFeedProvider` re-reads the same `/discover` feed; no distinct "Matches" semantics; `MatchesRepositoryImpl` still fully dormant (0 instantiations) |
| **Feed invalidation (`feed.invalidate`)** | **DONE (this session)** | Was: backend emits, 0 Flutter listeners. Now: wired into `realtimeSyncProvider`, invalidates Discover/Matches/Search, proven no-loop |
| Block filtering | DONE | `safety-exclusions.builder.ts`, applied in feed/search/nearby/shortlist/profile-view |
| Privacy filtering | **BROKEN** | Confirmed again this session — 0 reads of the two privacy flags anywhere in matches/search/nearby |
| Match compatibility % | DONE (real, not AI) | Deterministic scorer, `scoring/compatibility.service.ts` — **not** Gemini/AI despite `aiMatchPercent` naming |
| `astroMatchPercent`/`psychologyMatchPercent` | NOT DONE | Hardcoded 0, honestly commented as such |
| `isVerified`/`isPremium`/`isPsychologyCompleted`/`horoscopeAvailable`/`photoProtected` | **NOT DONE** | All 5 hardcoded `false` in `ProfileFeedMapper` |

## 6. INTERACTIONS

| Item | Status | Evidence |
|---|---|---|
| Interests (send/accept/decline/withdraw) | DONE | Polymorphic, idempotent, race-safe |
| Shortlist | DONE | Block-filtered |
| Profile views | DONE | Transactional with notification |
| Block/unblock | DONE | Enforced across every read path |
| Report | PARTIAL | Row created, nothing consumes it (admin stub) |
| Contact reveal | NOT DONE | 0 references anywhere |
| Daily interest limits | NOT DONE | No per-user counter; only IP-level throttle |

## 7. CHAT

| Item | Status | Evidence |
|---|---|---|
| Socket connection | DONE | Single connection, per-user room, token-refresh-on-reconnect |
| Send/receive | DONE | 746-line `messages.service.ts`, largest service in the app |
| Delivery/read status | DONE | `MessageDeliveryStatus` enum, ack events |
| Attachments | PARTIAL | Backend fully real; frontend primary-send path needs confirmation (retry path confirmed wired) |
| Block enforcement | DONE | `ConversationParticipantGuard`, audit-logged denials |
| Accepted-interest gate | DONE | `hasAcceptedInterest()` check before any message |

## 8. NOTIFICATIONS

| Item | Status | Evidence |
|---|---|---|
| FCM registration | DONE | `POST /notifications/device` |
| Push: interest/message/view/shortlist | DONE | 5 real transactional call sites |
| Push: subscription/badge/kundli | NOT DONE | Enum values exist, zero producers |
| In-app centre | DONE | Full CRUD + deep links |
| Android push | DONE | |
| iOS push | **BLOCKED** | No `.entitlements`, no `UIBackgroundModes` in `Info.plist` |
| Notification preferences | NOT DONE | `UserSettings.pushNotificationsEnabled` never read by dispatch, never written by any UI |

## 9. VERIFICATION

| Item | Status | Evidence |
|---|---|---|
| Aadhaar/KYC UI | PARTIAL | Full Flutter UI, POSTs into a 4-line stub controller (404) |
| Signzy | NOT DONE | 0 references |
| Face verification / Rekognition | NOT DONE | 0 references |
| Verification status persistence | NOT DONE | `KycVerification` never written by any code path |

## 10. BADGES

All NOT DONE — 5 hardcoded booleans in `ProfileFeedMapper`, no badge derivation logic anywhere. See §5.

## 11. ASTROLOGY

| Item | Status | Evidence |
|---|---|---|
| Birth detail capture | DONE | `AstrologyProfile` fully written at finalize |
| Prokerala integration | NOT DONE | 2 empty classes |
| Guna Milan / compatibility | NOT DONE | `HoroscopeMatch` table, `rawChart` column — zero writes anywhere |
| Flutter Astro screen | PARTIAL | Real UI, bound to `MockCompatibilityRepository`; real `ApiCompatibilityRepository` exists, 0 provider bindings |

## 12. PSYCHOLOGY

| Item | Status | Evidence |
|---|---|---|
| Backend module | NOT DONE | No `psychology` module exists at all — not even a stub |
| Frontend UI | PARTIAL | Real quiz UI, bound to `MockPersonalityRepository` |
| DB models | ORPHANED | `PsychologyQuiz`/`QuizQuestion`/`UserQuizResponse` + seeder exist, zero backend consumer |

## 13. AI (GEMINI)

NOT DONE. `grep -ri "gemini\|generativeai"` → 0 hits repo-wide. No key, no client. The app's real, deterministic compatibility scorer is sometimes mislabeled "AI" in field names (`aiMatchPercent`) — it is not AI.

## 14. PREMIUM / SUBSCRIPTIONS

| Item | Status | Evidence |
|---|---|---|
| Plan DB | PARTIAL | `FREE`/`SILVER`/`GOLD` enum, no `DIAMOND`; seeder never seeds `FREE` |
| Razorpay | NOT DONE | 3 empty controllers, no npm package, no Flutter SDK |
| Entitlement enforcement | NOT DONE | Nothing gated anywhere — free users already have every "paid" capability |
| Premium UI | NOT DONE | Static marketing pages, hardcoded ₹4,999 matching no seeded plan |

## 15. PRIVACY

Toggles exist and save correctly; **zero backend enforcement**. Hide-phone/hide-email are DONE **by omission** — the feed mapper simply never includes those fields for anyone, which is correct but coincidental, not a deliberate privacy-check.

## 16. ADMIN / MODERATION

Entirely NOT DONE. `admin` module = 3× 4-line-stub controllers, not in `AppModule`. `RolesGuard`/`AdminOnlyGuard` are empty stub classes. No admin frontend of any kind.

## 17. SETTINGS

| Item | Status | Evidence |
|---|---|---|
| Privacy settings | DONE (save) / BROKEN (enforcement) | See §15 |
| Notification/theme/language settings | NOT DONE | `UserSettings` table exists, **never written by the live API** |
| Delete account | DONE | Full cascade cleanup, S3 object deletion |

## 18. INFRASTRUCTURE

| Item | Status | Evidence |
|---|---|---|
| Redis | DONE | Feed cache, presence, uid→id cache, Socket.IO adapter, BullMQ |
| PostgreSQL / Prisma | DONE (schema) / BROKEN (generated client) | 21 `tsc` errors on clean clone |
| S3 | DONE | Presigned, private bucket |
| Elasticsearch | **ORPHANED** | Required at boot (production-fatal if unreachable), `SEARCH_STRATEGY` bound to Postgres — connected, serves zero queries |
| Firebase | DONE | Auth + FCM |
| Railway | DONE | `worker`/`scheduler` need separate services with overridden start commands (deployment-config item, unverifiable from repo) |
| Sentry | NOT DONE | 0 references in any of the 4 backend processes or Flutter |
| Cron jobs | PARTIAL | Only `WeeklyDigestCron` registered; 4 others are stub files |
| Workers | PARTIAL | Only the mail queue processor registered; 7 others are stub files |

## 19. SECURITY

| Item | Status | Evidence |
|---|---|---|
| Dummy auth bypass | **CRITICAL — live** | See §F |
| IDOR | DONE (verified twice this session) | Profile ownership (existing e2e test) + prompt-delete ownership (`deleteMany({userId, promptId})`, verified this session) — both correctly scoped |
| Rate limiting | DONE | Global throttler + per-route tiers; `getPreferences`/`updatePreferences` notably have **no** explicit tier (inherits global default — not a gap, just worth knowing) |
| CORS | DONE | Fail-closed in production |
| Secret management | DONE | Pre-commit hook exists, **opt-in per clone** (not a gap in code, a process gap) |
| Webhook verification | NOT DONE | `RazorpaySignatureGuard` is an empty stub — moot until Razorpay itself is built |
| Global exception filter | NOT DONE | Registered nowhere; Nest's default handling is what actually runs |

---

## E. MASTER FEATURE TABLE (condensed — full detail in §1–19 above)

| Feature | Frontend | Backend | DB | External API | Status | Main Problem | Next Action |
|---|---|---|---|---|---|---|---|
| Firebase email/phone/Google auth | ✅ | N/A | ✅ | Firebase | DONE | — | — |
| Mobile OTP | ⚠️ mock | ✅ real | ✅ | Firebase (billing) | BLOCKED | SMS billing off | Enable Blaze plan |
| Dummy-OTP bypass | ⚠️ | ⚠️ | ✅ | Firebase | BROKEN | Live in any NODE_ENV | Close before beta |
| Registration wizard | ✅ | ✅ | ✅ | — | DONE | — | — |
| Profile completeness % | ✅ | ⚠️ | ✅ | — | PARTIAL | Depends on unreachable KYC | Ship verification |
| Own profile CRUD | ✅ | ✅ | ✅ | — | DONE | — | — |
| Other-member profile detail | ❌ mock | ❌ | ✅ | — | BROKEN | No detail endpoint anywhere | Build one |
| Partner preferences (base) | ✅ | ✅ | ✅ | — | **DONE** | — | — |
| Partner preferences (extended) | ✅ local-only | ❌ | ✅ column | — | NOT DONE | No safe write path | Backend DTO extension |
| Profile prompts add/replace | ✅ | ✅ | ✅ | — | DONE | — | — |
| Profile prompts delete | ✅ | ✅ | ✅ | — | **DONE** | — | — |
| Photo upload/S3 | ✅ | ✅ | ✅ | AWS S3 | DONE | — | — |
| Photo moderation | ❌ | ❌ | ✅ unused col | AWS Rekognition | NOT DONE | — | Backend + Rekognition |
| Photo/profile privacy enforcement | ✅ toggle | ❌ | ✅ | — | BROKEN | Zero enforcement | Read flags in every query |
| Discover feed | ✅ | ✅ | ✅ | — | DONE | — | — |
| Search | ✅ | ✅ | ✅ | — | **DONE** | — | — |
| Matches reel | ⚠️ | ✅ (unused route) | ✅ | — | PARTIAL | Same data as Discover | Define real semantics |
| Feed invalidation (socket) | ✅ | ✅ | — | — | **DONE** | — | — |
| Badges (verified/premium/etc.) | ✅ UI | ❌ | ✅ | — | NOT DONE | 5 hardcoded fields | Derive from real rows |
| Interests/Shortlist/ProfileViews | ✅ | ✅ | ✅ | — | DONE | — | — |
| Block/Report | ✅ | ✅ | ✅ | — | DONE (block) / PARTIAL (report) | No moderation queue | Admin module |
| Chat (send/receive/delivery) | ✅ | ✅ | ✅ | Redis | DONE | — | — |
| Push notifications (Android) | ✅ | ✅ | ✅ | FCM | DONE | — | — |
| Push notifications (iOS) | ✅ | ✅ | ✅ | APNs | BLOCKED | No native config | Add entitlements |
| Aadhaar/KYC | ✅ mock-ready | ❌ stub | ✅ | Signzy | NOT DONE | No backend, no Signzy | Build module |
| Face verification | ❌ | ❌ | ✅ | Rekognition | NOT DONE | — | Build + AWS |
| Astrology/Kundli | ✅ mock | ❌ stub | ✅ | Prokerala | NOT DONE | No backend, no Prokerala | Build module |
| Psychology quiz | ✅ mock | ❌ **no module** | ✅ | — | NOT DONE | No backend at all | Build module (cheapest gap) |
| Gemini AI matchmaking | ❌ | ❌ | — | Gemini | NOT DONE | Doesn't exist | Out of MVP scope? |
| Premium/subscription | ⚠️ static | ❌ stub | ✅ | Razorpay | NOT DONE | No backend, no gating | Build + Razorpay |
| Contact reveal | ❌ | ❌ | — | — | NOT DONE | Doesn't exist | Depends on premium |
| Admin panel | ❌ | ❌ stub | ✅ | — | NOT DONE | No RBAC, no UI | Build from scratch |
| Notification/theme/lang settings | ❌ | ❌ | ✅ unused | — | NOT DONE | Table exists, never written | Build write path |
| Elasticsearch | — | ⚠️ connected, unused | — | Elasticsearch | **ORPHANED** | Prod-fatal if down, serves nothing | Wire or drop |
| Sentry / error monitoring | ❌ | ❌ | — | Sentry | NOT DONE | Zero observability | Add to all 4 processes |
| Prisma client (generated) | — | ⚠️ stale | ✅ schema current | — | BROKEN | 21 tsc errors on clean clone | `prisma generate` |

---

## 🔴 CRITICAL (max 10)

**1. Registration draft can silently overwrite Partner Preferences base fields**
- **Why it matters:** a member who edits base preferences via the new `/discover/preferences` screen, then later edits Religion via Profile Edit (which still round-trips the full draft), can have their carefully-set age/height/religion/etc. filters silently reset to stale values.
- **Where:** `registration_provider.dart`'s `applyOnboardingReligion()` → `writeProfileFromDraft()` in `profile.service.ts` (unconditional recompute of all 10 base columns from draft data).
- **Fix:** make `writeProfileFromDraft`'s partner-preference materialization a true partial merge, or migrate the caste-no-bar toggle off the draft path too.

**2. `POST /auth/dummy-otp/session` — live authentication bypass**
- **Why it matters:** mints a real, usable Firebase session for any phone number with zero SMS verification, in **any** environment including production, when `DUMMY_OTP_ENABLED=true`.
- **Where:** `dummy-otp-session.controller.ts`, `dev-auth.ts`.
- **Fix:** `USE_REAL_OTP=true` once SMS billing is enabled; delete the bypass entirely.

**3. Privacy toggles enforce nothing**
- **Why it matters:** members who toggle "hide my profile"/"hide my photos" believe they are hidden. They are not — every feed/search/nearby/shortlist/profile-view query is blind to both flags.
- **Where:** `settings.service.ts` (write-only), absent from `partner-preference-where.builder.ts`, `safety-exclusions.builder.ts`, `nearby.repository.ts`, `shortlist.repository.ts`, `profile-view.repository.ts`, `ProfileFeedMapper`.
- **Fix:** read both flags in every listed query/mapper.

**4. Other-member profile detail is entirely fabricated**
- **Why it matters:** the app's primary decision surface (viewing a candidate's full profile) shows invented family/horoscope/bio data as if real — the highest-trust screen in a matrimony app is the least honest one.
- **Where:** `ProfileDetailMockDataSource`.
- **Fix:** build a real detail endpoint (design decision needed: which module owns it, per `profile.controller.ts`'s own architectural note).

**5. Every trust/premium badge on every profile card is hardcoded false**
- **Why it matters:** `isVerified`, `isPremium`, `isPsychologyCompleted`, `horoscopeAvailable`, `photoProtected` can never be true — every badge in the entire app is decorative, misleading users about verification/premium status.
- **Where:** `ProfileFeedMapper`.
- **Fix:** derive from real `KycVerification`/`UserSubscription`/`UserQuizResponse`/`AstrologyProfile` rows once those exist.

**6. No feature gating anywhere — the paid tier confers zero enforced privilege**
- **Why it matters:** even once Razorpay ships, unless entitlement checks are added, a free user calling the API directly bypasses every "paid" restriction.
- **Where:** no code exists for this at all.
- **Fix:** build the entitlement guard as part of the subscription work, not after.

**7. Verification/KYC accepts uploads into a 404**
- **Why it matters:** members attempt real document verification and silently fail with no backend to receive it — a broken core-trust flow, not just a missing feature.
- **Where:** `verification.controller.ts` (4-line stub, unregistered).
- **Fix:** implement + register the module.

**8. Elasticsearch is a production-fatal required dependency serving zero queries**
- **Why it matters:** a live availability risk — if the ES cluster goes down, the API refuses to boot in production, for a service that currently does nothing.
- **Where:** `ElasticsearchService` (boot check), `validation.ts` (`ELASTICSEARCH_NODE` required).
- **Fix:** either wire real search to it or make the node optional.

**9. Committed Prisma client is stale — repo doesn't type-check from a clean clone**
- **Why it matters:** blocks onboarding, and CI only passes because it regenerates first — a real risk of shipping code that was never actually type-checked locally.
- **Where:** `libs/database/generated/client`.
- **Fix:** `pnpm prisma generate`, commit the output.

**10. No error monitoring in any of the 4 backend processes or Flutter**
- **Why it matters:** a production failure today is invisible until a user reports it.
- **Where:** repo-wide — 0 Sentry/equivalent references.
- **Fix:** add Sentry to `api`, `worker`, `scheduler`, Flutter.

---

## 🟠 IMPORTANT (max 15)

1. Verification module backend (Aadhaar/income/NRI) — FE built, 404 today.
2. Subscription + Razorpay backend — no revenue path exists.
3. Badge derivation from real rows (depends on #1/#2 above).
4. Psychology module backend — cheapest real gap (models + seed data + FE all exist).
5. Prokerala/horoscope backend — FE bound to mock, real repository unused.
6. Matches-tab semantics — currently indistinguishable from Discover.
7. `MatchesRepositoryImpl` — write, wire, or delete (currently 100% dead code).
8. Admin panel + real `RolesGuard` — no moderation queue for the reports that already exist.
9. iOS APNs entitlements — Dart side complete, native config missing.
10. `UserSettings` write path — notification/theme/language toggles persist nowhere.
11. Contact reveal — doesn't exist, blocks a premium selling point.
12. Daily interest limits — only IP-level throttling, no per-user quota.
13. Photo moderation — `isApproved` column is fully dead.
14. Chat attachment primary-send path — confirm it's actually wired (retry path is; primary needs a check).
15. Extend `/discover/preferences` DTO to cover `extendedPreferences`, closing the Partner Preferences gap properly (removes the workaround/disclosure banner added this session).

---

## 🟢 POLISH (max 10)

1. Delete dead scaffolding: `AllExceptionsFilter`, `RolesGuard`/`AdminOnlyGuard` stubs, `ZodValidationPipe`, `@app/logger`, `apps/websocket`, `RefreshToken` model, unused `JWT_SECRET`.
2. Plan-aware photo cap (hardcoded 6, should read `plan.limits.photoUploads`).
3. Seed the `FREE` subscription plan (never seeded today).
4. Add `@Throttle` tiers to `/discover/preferences` GET/PUT (currently inherit only the global default).
5. Educate `educationPref` — the only base preference field with zero UI control.
6. Flutter release/store pipeline — CI only runs analyze+test, no build step.
7. Make backend ESLint blocking once its 38 pre-existing errors are cleared.
8. Mandate the pre-commit secret-scanning hook (currently opt-in per clone).
9. Rename `aiMatchPercent` (it's deterministic scoring, not AI) to avoid future confusion.
10. `NotificationType` enum has 4 values with zero producers (`SUBSCRIPTION_EXPIRING/RENEWED`, `KYC_APPROVED/REJECTED`) — wire once their parent features exist.

---

## G. IMPLEMENTATION ROADMAP

### PHASE 1 — CORRECTNESS / SECURITY
- [ ] **Regenerate + commit Prisma client**
  Owner: BACKEND · Dependency: none · Files: `libs/database/generated/client` · Result: clean `tsc --noEmit` · Verify: run on a fresh clone.
- [ ] **Close the dummy-OTP bypass**
  Owner: BACKEND + EXTERNAL (SMS billing) · Dependency: Firebase Blaze plan · Files: `dev-auth.ts`, `dummy-otp-session.*` · Result: route removed · Verify: 404 on the old path, real SMS round-trips.
- [ ] **Enforce privacy flags in every read query**
  Owner: BACKEND · Dependency: none · Files: `partner-preference-where.builder.ts`, `safety-exclusions.builder.ts`, `nearby.repository.ts`, `shortlist.repository.ts`, `profile-view.repository.ts`, `ProfileFeedMapper` · Result: hidden member absent from every listed surface · Verify: e2e per path.
- [ ] **Fix the draft-overwrite risk for Partner Preferences**
  Owner: BACKEND · Dependency: privacy-flags task pattern · Files: `profile.service.ts`'s `writeProfileFromDraft` · Result: partial merge, not full overwrite · Verify: edit base prefs via new screen, then edit Religion, confirm no reversion.

### PHASE 2 — CORE MVP COMPLETION
- [ ] **`GET /profiles/:id` + delete `ProfileDetailMockDataSource`**
  Owner: BOTH · Dependency: Phase 1 privacy enforcement · Files: new controller route, `ProfileDetailApiDataSource` · Result: real family/horoscope/bio · Verify: e2e for blocked/hidden/self.
- [ ] **Badge derivation**
  Owner: BACKEND · Dependency: verification + subscription (partial credit possible sooner) · Files: `ProfileFeedMapper` · Result: no hardcoded booleans · Verify: mapper unit tests.
- [ ] **Matches-tab real semantics or removal**
  Owner: BOTH · Dependency: product decision · Files: `reelFeedProvider`, `matches.controller.ts` · Result: Matches ≠ Discover, or documented as intentionally the same.
- [ ] **`UserSettings` write path**
  Owner: BACKEND + FRONTEND · Dependency: none · Files: `settings.controller.ts`, `settings_page.dart` · Result: theme/language/notification prefs persist.

### PHASE 3 — EXTERNAL INTEGRATIONS
- [ ] **Verification module (documents, then Signzy)**
  Owner: BACKEND + EXTERNAL · Dependency: Phase 1 · Files: `verification/*` · Result: real KYC rows · Verify: e2e submit/status, no plaintext doc numbers logged.
- [ ] **Psychology module backend**
  Owner: BACKEND · Dependency: none (cheapest) · Files: new `psychology` module · Result: FE mock→real flip.
- [ ] **Prokerala/horoscope backend**
  Owner: BACKEND + EXTERNAL · Dependency: Prokerala account · Files: `astro/*`.
- [ ] **Face verification (Rekognition)**
  Owner: BACKEND + EXTERNAL · Dependency: verification module · Files: `verification/*`, new AWS client.

### PHASE 4 — PREMIUM / MONETIZATION
- [ ] **Subscription + Razorpay + entitlement guard**
  Owner: BOTH + EXTERNAL · Dependency: Phase 1 · Files: `subscription/*`, new entitlement middleware · Result: real checkout, real gating · Verify: e2e proving a free user is blocked at the API, not just the UI.
- [ ] **Daily interest limits**
  Owner: BACKEND · Dependency: subscription plans · Files: new Redis counter in `interests` module.
- [ ] **Contact reveal**
  Owner: BOTH · Dependency: subscription + interests.

### PHASE 5 — SMART FEATURES
- [ ] **Gemini/AI matchmaking** (if still desired — confirm product scope first)
- [ ] **Trust score** — needs verification (50% of formula) shipped first.

### PHASE 6 — PRODUCTION HARDENING
- [ ] **Sentry across all 4 backend processes + Flutter**
- [ ] **iOS APNs configuration**
- [ ] **Elasticsearch decision** (wire or drop the boot requirement)
- [ ] **Admin panel + real RBAC**
- [ ] **Flutter release/store pipeline**

---

## H. TEAM SPLIT

**FRONTEND DEVELOPER**
- iOS APNs entitlements + background modes
- Wire or retire `MatchesRepositoryImpl`
- `UserSettings` UI (theme/language/notification toggles)
- Premium plan UI (parallel-buildable against a mocked plans response, wire once backend Phase 4 lands)

**BACKEND DEVELOPER 1**
- Phase 1 in full (Prisma regen, privacy enforcement, draft-overwrite fix, dummy-OTP closure) — these block almost everything else and should go first
- `GET /profiles/:id`
- `UserSettings` backend

**BACKEND DEVELOPER 2**
- Verification module (parallel with Dev 1 once Phase 1 lands)
- Psychology module (fully parallel — no dependency on anything)
- Subscription + Razorpay (after Phase 1)

**DATABASE**
- No migrations required for any P0/P1 item
- Optional: `DIAMOND` plan tier, `extendedPreferences` DTO exposure (both product decisions, not blockers)
- Cleanup-only: drop `RefreshToken` (confirmed dead)

**EXTERNAL SERVICES**
- Firebase Blaze/SMS billing — blocks real OTP, needed immediately
- Signzy account — blocks verification's final step (document flow itself can ship without it)
- AWS Rekognition IAM policy — blocks face verification
- Prokerala account — blocks horoscope
- Razorpay account — blocks monetization
- Sentry DSN — blocks observability, zero product dependency, can be added any time

---

## I. API REQUIREMENTS CHECKLIST

### APIs already implemented + connected
`GET /discover`, `GET /discover/search`, `GET`/`PUT /discover/preferences`, `POST /matches/interest`, `GET /interests/{received,sent}`, `GET/POST/DELETE /matches/shortlist`, `GET/POST /matches/profile-view(s)`, `GET /profiles/nearby`, `PUT /profiles/me/location`, `GET /profiles/me`, `POST /profiles/finalize`, all `PATCH /profiles/draft/*`, `GET/POST/PUT/PATCH/DELETE` photo routes, `GET /profiles/prompts/{bank,me}`, `PUT /profiles/prompts/me`, `DELETE /profiles/prompts/me/:promptId`, `GET/PATCH /notifications/*`, `POST/DELETE /users/:id/block`, `POST /users/:id/report`, all `chat/*` routes, `GET/PATCH/DELETE /settings/*`.

### APIs implemented but unused/orphaned
- None currently known — this session closed the last 3 (search, preferences, feed.invalidate, prompt-delete). `GET /` (root) and `POST /notifications/test` remain technically unconsumed but are explicitly out of scope per this task's own instructions.

### APIs missing but required
| Method | Route | Purpose | Auth | Dependency |
|---|---|---|---|---|
| GET | `/profiles/:id` | Other-member profile detail | Firebase | Privacy enforcement first |
| POST | `/verification/documents` (real) | Aadhaar/income/NRI submit | Firebase | Signzy (later) |
| GET | `/psychology/quiz/active`, `/me` | Quiz + results | Firebase | none |
| POST | `/psychology/quiz/submit` | Save answers | Firebase | none |
| GET | `/astro/profile/me`, `/astro/compatibility/:id` | Horoscope + Guna Milan | Firebase | Prokerala |
| GET | `/plans` | Subscription plans | Firebase | none |
| POST | `/subscriptions/checkout` | Razorpay order | Firebase | Razorpay |
| POST | `/webhooks/razorpay` | Payment confirmation | Signature | Razorpay |
| PATCH | `/settings` (general) | Theme/language/notif prefs | Firebase | none |

### APIs that require external providers
Verification (Signzy), Face verification (Rekognition), Horoscope (Prokerala), Payments (Razorpay), Phone OTP (Firebase SMS billing).

### APIs that can be built without external APIs
`GET /profiles/:id`, Psychology module (entirely — models + seed data already exist), `UserSettings` write path, Matches-tab redefinition, Badge derivation (once verification/subscription exist), Daily interest limits, Contact reveal (data model + gating logic; the "call" itself would need Exotel later).

---

## J. TESTING STATUS

| Suite | Result | Verified |
|---|---|---|
| `flutter analyze --no-fatal-infos` | **No issues found!** | Run today |
| Flutter full `flutter test` | **889/889 passed**, 79 test files | Run today (twice, consistent) |
| Backend `pnpm test` | **857/857 passed**, 72/75 suites (3 skipped, 12 todo) | Run today |
| Backend `tsc --noEmit` | **21 errors** (stale Prisma client) | Run today |
| Backend `pnpm test:e2e` | UNKNOWN | Not run — requires the shared Neon instance, deliberately not touched |

**Features with no meaningful tests:** admin (no code to test), verification (blocked on backend), subscription (blocked on backend), psychology backend (doesn't exist), astro backend (doesn't exist), badges (nothing to test — all hardcoded), photo moderation (dead column).

**12 backend `it.todo`s** map exactly onto the stub modules: `moderation`, `astro/compatibility`, `recommendation`, `profile-draft`, `search-query`, `checkout`, `trust-score`, `users`, `verification`, `subscription-expiry.cron`, `websocket/chat.gateway`, `photo-moderation.processor`.

---

## 🚀 IMMEDIATE NEXT PROMPT

NEXT TASK:
**Enforce `profileVisibleToPremiumOnly` and `hidePhotosFromNonConnections` in every feed/search/nearby/shortlist/profile-view query and the photo mapper**

OWNER:
Backend

WHY NOW:
It's the highest-severity confirmed defect with zero external dependency and zero design ambiguity — the fix is mechanical (read two existing, already-persisted booleans in five already-identified files) and directly closes a real user-trust and data-exposure gap before any new feature work continues.

DEPENDENCIES:
None — flags already exist on `User`, already save correctly via `PATCH /settings/privacy`.

DONE WHEN:
A member who sets either toggle is provably absent from (or photo-stripped in) `GET /discover`, `GET /discover/search`, `GET /profiles/nearby`, shortlist listings, and profile-view listings for any non-premium/non-connected viewer, with a passing test for each of the five paths.
