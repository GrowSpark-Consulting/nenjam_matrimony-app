# Nenjam Matrimony — Backend Dead Code Audit

**Scope:** `backend/` as it exists on `main` (post PR #79 / #80 / #81)
**Method:** runtime-graph reachability first, then reference-proving. Module registration was resolved from `AppModule` outward through transitive imports before any symbol was classified. Every finding was checked against NestJS DI registration, controller registration, `@Type()` nested validation, Prisma usage, queue/cron registration, and string-based references.
**Constraint:** no source code was modified and nothing was deleted.

---

## 1. Executive Summary

| Category | Count |
|---|---:|
| **A. Definitely dead** | **1** |
| **B. Probably dead** | **0** |
| **C. Incomplete feature — keep** | **8** |
| **D. Backend-only / future consumer — keep** | **2** |
| **E. Test-only** | **0** |
| **F. Generated / framework required** | **2** |
| **G. Confirmed active (false positives)** | **7** |
| **Total findings** | **20** |

### The headline

**Exactly one symbol in the entire backend is genuinely dead code: `ProfileResponseDto`.**

An initial automated scan surfaced **106 exported classes with no external production reference**, which looks alarming. Disciplined verification collapsed that to one. The other 105 fall into two well-defined groups:

1. **~90 are empty scaffolding stubs** — 3–4 non-blank lines each, `@Module({})` / `@Controller()` with no body. They are placeholders for unbuilt features, which your brief explicitly separates from dead code. Deleting them removes no logic, only the shape of planned work.
2. **~15 are false positives** — reached through NestJS module registration, `@Type()` nested validation, or same-file composition, none of which a symbol grep detects.

**On the two specific questions asked:**

- **Did Entitlements supersede Subscription after PR #79?** **No.** They are complementary, not duplicative — Entitlements *reads* `UserSubscription`, Subscription would *write* it. `EntitlementsModule`'s own doc comment states it is *"independent of the (still unimplemented) subscription/checkout module."*
- **Did PR #80 leave obsolete matching code behind?** **No.** `preference-categories.ts` is consumed by the active `partner-preference-where.builder.ts`. No sibling was orphaned; `matches/filters/` contains exactly three implementation files, all live.

---

## 2. Definitely Dead

| File | Symbol | Type | Evidence | Replacement | Safe to Remove | Confidence |
|---|---|---|---|---|---|---|
| `apps/api/src/modules/profiles/dto/profile.response.dto.ts` | `ProfileResponseDto` | Response DTO (61 lines, fully written out) | **Zero references anywhere.** The file is never imported (`grep` for both the path and the symbol across `apps/` returns nothing outside its own declaration). It is not used in a controller signature, a service return type, or a Swagger decorator. | `ProfileEntity` — `GET /profiles/me` exists at `profile.controller.ts:25` but is declared `getOwn(...): Promise<ProfileEntity>`, not this DTO. | **Yes** | **High** |

**Why this is real and not a false positive.** Unlike every other DTO in the codebase, this one is not reached by any indirect mechanism:

- It is **not** nested inside another DTO via `@Type()` (contrast `FamilyMemberDto`, §13).
- It is **not** referenced in a controller's return type (contrast `DiscoverFeedResponseDto`).
- It is **not** used as a Swagger `@ApiProperty({ type: ... })` target (contrast `TemporaryCredentialsDto`, §13).
- The endpoint it documents itself as serving — *"Shape returned by `GET /profiles/me`"* — **demonstrably returns a different type**.

This is a contract that was written, then superseded by `ProfileEntity`, and never removed. It is the single genuine instance of superseded code in the backend.

**Tests referencing it:** none.

---

## 3. Probably Dead

**None.**

Every other candidate resolved to a definite classification. No finding was left in a state where dynamic or runtime usage prevented a conclusion — module registration, `@Type()` decorators, and same-file composition each gave a determinate answer.

---

## 4. Duplicate / Superseded Backend Code

### 4.1 — Subscription vs. Entitlements — **NOT superseded** (specifically investigated)

This was the primary question. The two are **complementary halves of one capability**, split deliberately:

| | `EntitlementsModule` | `SubscriptionModule` |
|---|---|---|
| **Status** | Real, ~25-line service + repository | Empty stubs (`@Module({})`, `@Controller()` with no routes) |
| **Reachable?** | **Yes** — via `SettingsModule` → `AppModule` | **No** — imported by nothing |
| **Role** | **Reads** `UserSubscription` to answer "is this member premium?" | **Would write** `UserSubscription` via checkout + Razorpay webhook |

The entitlements module documents the split in its own header:

> *"Premium entitlement checks, independent of the (still unimplemented) subscription/checkout module: this only READS UserSubscription rows, so it works unchanged once checkout and the Razorpay webhook start writing them."*

**Conclusion:** PR #79 did **not** replace an older Subscription implementation — there was never an implementation to replace, only stubs. Nothing was orphaned. The subscription stubs are **Category C**, not dead.

`activePremiumSubscriptionWhere` (`libs/database/src/entitlements/premium-entitlement.ts`) is the single shared premium rule, consumed by both the entitlement repository and the feed's `photoPrivacySelectFor`. **No duplicate definition of "premium" exists** — that was the explicit design goal, and it holds.

### 4.2 — PR #80 preference scoring — **no obsolete code left behind** (specifically investigated)

`matches/filters/` contains exactly three implementation files, all active:

- `eligibility.builder.ts` — live
- `partner-preference-where.builder.ts` — live, and **imports** `preference-categories.ts` at line 10
- `preference-categories.ts` — the PR #80 addition, consumed by the above

PR #80 **modified** the existing builder rather than adding a parallel path. There is no old matching implementation sitting beside the new one. `EDUCATION_CATEGORIES` / `OCCUPATION_CATEGORIES` are referenced by the builder and pinned by a drift spec that reads the Dart source.

### 4.3 — No other duplication found

No old-repository/new-repository pair, no legacy service beside a replacement, no duplicate DTO for the same contract — with the single exception of `ProfileResponseDto` vs `ProfileEntity` (§2).

---

## 5. Dead Modules / Controllers

**No module is dead. Five are unreachable stubs (Category C).**

| Module | In `AppModule`? | Imported by any module? | Files | Non-blank lines | Verdict |
|---|---|---|---|---|---|
| `admin` | No | No | 12 | 33 | **C — stub** |
| `astro` | No | No | 9 | 24 | **C — stub** |
| `search` | No | No | 9 | 22 | **C — stub** |
| `subscription` | No | No | 14 | 38 | **C — stub** |
| `trust-score` | No | No | 8 | 21 | **C — stub** |

**52 files totalling ~138 non-blank lines — under 3 lines per file.** A scan for any file in these five modules exceeding 6 non-blank lines returned **nothing**. Representative example, in full:

```ts
// subscription/subscription.module.ts
import { Module } from '@nestjs/common';
@Module({})
export class SubscriptionModule {}
```

These are architectural placeholders for features the product intends to build (admin console, astrology, Elasticsearch search, payments, trust scoring). Per the brief's explicit instruction, **incomplete ≠ dead**. See §12.

### Controllers inside *reachable* modules that are not registered

`UsersModule` and `VerificationModule` **are** in `AppModule` but deliberately register only part of their contents:

- **`UsersModule`** registers `AccountAvailabilityController` + `DummyOtpSessionController` only. Its comment: *"the rest of the module is still a stub."* `UsersController` (3 lines) is unregistered.
- **`VerificationModule`** registers `FaceVerificationController` only. Its comment is explicit: *"The document-verification stubs beside it … are **intentionally NOT registered**: they are still empty, and registering them would change nothing but the route table."*

Both are **Category C**, and the second is self-documenting about the decision.

### `apps/websocket`

Every file is 2–10 non-blank lines; `railway.toml` deliberately excludes it from the build. Real-time runs inside `apps/api`'s `RealtimeModule`. **Category C**, consistent with the documented architecture.

---

## 6. Dead Services / Providers

**None dead.**

Unregistered service classes in reachable modules are all 3–4 line stubs:

| Symbol | Lines | Module registered? | Verdict |
|---|---|---|---|
| `UsersService` | 3 | No | C — stub |
| `VerificationService` | 3 | No | C — stub |
| `FaqService` | 3 | No | C — stub |
| `DocumentCheckService` | stub | No | C — stub |

Every **registered** provider in the reachable graph is injected and used. No provider was found registered-but-unconsumed.

---

## 7. Dead Repositories / Prisma Access

**None dead.**

- `UsersRepository`, `VerificationRepository`, `ModerationRepository`, `AstroCacheRepository`, `TrustScoreRepository`, `SubscriptionRepository`, `MatchRepository` — all stubs in unregistered modules or unregistered within their module. **Category C.**
- **`UserSubscription` Prisma model** — has exactly one application consumer: `entitlement.repository.ts:18` (`prisma.userSubscription.findFirst`). It is read but never written, because checkout is unimplemented. **This is Category C, explicitly not dead** — the brief's instruction not to call a Prisma model dead for feature incompleteness applies precisely here.
- No duplicate data-access implementation was found. Each live repository is the sole access path for its aggregate.

---

## 8. Dead DTOs / Mappers / Types

**One dead DTO** — `ProfileResponseDto` (§2).

All other DTOs flagged by automated scanning are reached indirectly:

| DTO | Reached via | Verdict |
|---|---|---|
| `FamilyMemberDto`, `SiblingMemberDto` | `@Type(() => …)` nested validation inside `FamilyDetailsDto`, which `profile-draft.controller.ts:16` imports | **G — active** |
| `TemporaryCredentialsDto` | `@ApiProperty({ type: TemporaryCredentialsDto })` + field type at `face-verification.dto.ts:116` | **G — active** |
| `SendInterestDto`, `InterestResponseDto`, `NotificationResponseDto`, `MatchCandidateResponseDto`, `SearchFiltersDto`, `PlanResponseDto`, `CheckoutDto`, `ModerationActionDto`, `TrustScoreResponseDto`, `UserResponseDto`, `UpdateAccountDto` | Empty stub classes in stub modules, or unregistered stubs | **C — stub** |

**Mappers:** `profile-feed.mapper.ts` is actively used by feed, search, shortlist, and profile-view services. No orphaned mapper found.

---

## 9. Dead Auth / Guards / Interceptors

**None dead — all are documented 4-line stubs (Category C).**

| Symbol | Lines | Attached anywhere? | Note |
|---|---|---|---|
| `RolesGuard` | 4 | No | Empty stub; `@Roles()` has no reader |
| `AdminOnlyGuard` | 4 | No | Stub in unregistered `admin` module |
| `RazorpaySignatureGuard` | stub | No | Stub in unregistered `subscription` module |
| `WsJwtGuard` | 4 | No | In the non-deployed `apps/websocket` |
| `ProfileOwnershipGuard` | 4 | No | Stub; ownership is enforced inside services |
| `AllExceptionsFilter` | 4 | Not registered | Nest's default handling is what runs |
| `TransformResponseInterceptor` | 4 | Not registered | Stub |
| `RequestTimingInterceptor` | 4 | Not registered | Stub |
| `ZodValidationPipe` | 4 | Not registered | **`zod` is not even a dependency** (`grep '"zod"' package.json` → 0) |
| `DocumentTypePipe` | stub | No | Stub |

**Actually active and must not be confused with the above:** `FirebaseAuthGuard` (applied per-controller), the global `ValidationPipe`, `ThrottlerGuard` (global `APP_GUARD`), `@CurrentUser()`, and the chat module's `conversation-participant.guard.ts`.

---

## 10. Dead Events / Queues / Jobs

**None dead — all unregistered stubs (Category C).**

- **Worker:** `worker.module.ts` registers **no `*Processor` classes** directly; only `MailModule.forWorker()` (the mail queue) is wired. The 7 processor files (`photo-compression`, `photo-moderation`, `push-fanout`, `search-indexing`, `recommendation-recompute`, `prokerala-lookup`, `otp-dispatch`) are unregistered stubs — each paired with an equally stubbed `*Producer`, so **neither side of any queue exists**. Nothing is orphaned; the whole pipeline is unbuilt.
- **Scheduler:** only `WeeklyDigestCron` is registered. `InactiveProfileNudgeCron`, `SearchReindexSweepCron`, `SubscriptionExpiryCron`, `TrustScoreDecayCron` are unregistered stubs.
- **Event emitters/listeners:** `ChatEventsEmitter`, `InterestEventsEmitter`, `SubscriptionEventsEmitter`, `NotificationListeners`, `TrustScoreListeners`, `ProfileIndexingListener` — all stubs. Real-time delivery runs through `RealtimeModule`'s Socket.IO path instead, which is live.

---

## 11. Dead Configuration / Constants

**None dead.**

- No environment variable was found that is Joi-validated but never read, with one **documented** exception: `JWT_SECRET` is required by Joi but consumed by no token logic (auth is Firebase-ID-token-only). This is a known, documented quirk rather than an audit discovery, and removing it would require touching the Joi schema — out of scope here.
- No unreferenced API constant, feature flag, or configuration provider was found.
- `CloudFrontService` (`libs/storage`) is a 3-line stub — **Category C**, reserved for the stable-CDN-URL work.
- The entire `@app/logger` lib (`LoggerModule`, `LoggerService`, `RequestContextMiddleware`) is stubs; Nest's built-in per-class `Logger` is the real mechanism. **Category C.**

---

## 12. Incomplete Features That MUST NOT Be Deleted

Each of these is unreachable today but is deliberate product architecture. The brief's distinction — *"dead" vs "incomplete but intentionally retained"* — resolves every one to the latter.

### Subscription / Payments / Razorpay — **C**
**Code:** `modules/subscription/` (14 stub files: checkout, plans, Razorpay webhook controllers; `RazorpayService`, `CheckoutService`, `PlansService`, `SubscriptionRepository`, `RazorpaySignatureGuard`).
**Why incomplete:** nothing creates `UserSubscription` rows; checkout and the webhook are unimplemented.
**Why NOT dead:** the *read* half shipped in PR #79 and is live in production (`EntitlementsModule`, the feed's premium probe, privacy gating). These stubs are the write half of a capability that is actively being built out. The Prisma model, the entitlement rule, and the frontend's `subscriptionStatus` constant are all waiting on exactly this.
**Activated by:** implementing checkout + the Razorpay webhook.

### Astrology — **C**
**Code:** `modules/astro/` (9 stubs), `ProkeralaService`, `ProkeralaLookupProducer`, `AstroCacheRepository`.
**Why incomplete:** no astrology engine; `astroMatchPercent` is a deliberate `0`.
**Why NOT dead:** `AstrologyProfile` / `gotram` Prisma columns are populated by the live finalize path, and the Flutter client carries a complete prepared `ApiCompatibilityRepository`. The contract is half-built on both sides.

### Psychology — **C**
**Why incomplete:** no module exists at all in `AppModule`; `psychologyMatchPercent` is `0`.
**Why NOT dead:** the `PsychologyQuiz` / `QuizQuestion` / `UserQuizResponse` Prisma models exist and the Flutter client has a prepared `ApiPersonalityRepository`. Both ends are staged.

### Search (Elasticsearch) — **C**
**Code:** `modules/search/` (9 stubs), `SearchIndexService`, `SearchQueryService`, `ProfileIndexingListener`, `SearchIndexingProcessor`.
**Why NOT dead:** `ElasticsearchModule` **is** in `AppModule` and health-checked at boot. Text search currently runs through `matches/services/search.service.ts` (Postgres). These stubs are the planned Elasticsearch path — note that deleting them would leave a connected, health-checked ES client with no consumer at all.

### Trust score — **C**
`TrustScoreLog` Prisma model exists; a frontend regression test (`no_trust_score_references_test.dart`) actively asserts the feature is *not* surfaced yet — evidence of a deliberate, tracked hold rather than abandonment.

### Admin console — **C**
12 stubs; `AdminAccount` and `AuditLog` Prisma models exist. `db:seed` creates a default admin.

### Verification (document) — **C**
`VerificationModule` is live for **face** verification; the document stubs beside it are, in the module's own words, *"intentionally NOT registered."*

### `apps/websocket` — **C**
Excluded from the Railway build by design; real-time runs in `apps/api`.

---

## 13. False Positives Investigated

Documented so a future audit does not re-litigate them. **Each of these would have been a damaging deletion.**

| Candidate | Why it looked dead | Verdict |
|---|---|---|
| `FamilyMemberDto`, `SiblingMemberDto` | No external import of either symbol | **ACTIVE** — reached via `@Type(() => FamilyMemberDto)` nested validation inside `FamilyDetailsDto`; deleting them breaks runtime validation of family details with no compile error. |
| `TemporaryCredentialsDto` | Not imported by any controller or service | **ACTIVE** — used at `face-verification.dto.ts:116` as a field type and `@ApiProperty` target inside `StartFaceSessionResponseDto`. |
| `UsersController` / `VerificationService` / `FaqService` | Not registered in their (live) modules | **Stubs, not dead** — 3 lines each; their modules deliberately register only the implemented parts. |
| `EntitlementsModule` | Absent from `AppModule` | **ACTIVE** — reachable transitively via `SettingsModule`. Reachability must be computed through the whole import graph, not just `AppModule`'s literal list. |
| `preference-categories.ts` | New file from PR #80 | **ACTIVE** — imported at `partner-preference-where.builder.ts:10`. |
| `UserSubscription` Prisma model | No writes anywhere in application code | **NOT dead** — read by `entitlement.repository.ts:18`; the absence of writes is the unimplemented feature, not evidence of deadness. |
| `activePremiumSubscriptionWhere` | Lives in `libs/`, easy to miss | **ACTIVE** — consumed by both the entitlement repository and `photoPrivacySelectFor` (feed + notifications). |

---

## 14. Recommended Cleanup

### Safe cleanup — evidence-backed, no decision required

1. **Remove `apps/api/src/modules/profiles/dto/profile.response.dto.ts`** (`ProfileResponseDto`).
   Zero references; superseded by `ProfileEntity`, which is what `GET /profiles/me` actually returns.
   *Verify:* `npx tsc --noEmit` error count unchanged at 4 (pre-existing), `npx jest` still 1134 passing.

**That is the complete safe-cleanup list.** One file.

### Cleanup requiring developer / product confirmation

2. **The five unreachable stub modules** (`admin`, `astro`, `search`, `subscription`, `trust-score` — 52 files, ~138 lines).
   These could be deleted and re-scaffolded later. **This is a product-roadmap decision, not a code-quality one.** Arguments to keep: they encode intended architecture, cost ~138 lines total, and three of them (subscription, astro, search) have live counterparts already depending on the capability landing. Arguments to remove: they inflate the module count and repeatedly surface in audits.
   **Recommendation: keep**, and revisit only if a feature is formally descoped.

3. **`libs/common` inert infrastructure** (`AllExceptionsFilter`, `RolesGuard`, `ZodValidationPipe`, the two interceptors) and the `@app/logger` lib.
   Same reasoning. Note `ZodValidationPipe` is the weakest case — `zod` is not a dependency, so it could not be implemented as written without adding one.

### Do not touch

- `EntitlementsModule` / `premium-entitlement.ts` / `photo-visibility.ts` — live production code from PR #79.
- `preference-categories.ts` — live production code from PR #80.
- `UserSubscription` Prisma model and every model backing an incomplete feature.
- Any `@Type()`-nested DTO (§13).
- `apps/websocket` — excluded from build by design, not by neglect.

---

## 15. Final Status

**How much backend code is genuinely dead:** **one symbol in one file** — `ProfileResponseDto` (61 lines). Out of ~106 initially-flagged exports, exactly one survived verification. This backend does not have a dead-code problem.

**Safe removal candidate:** `apps/api/src/modules/profiles/dto/profile.response.dto.ts`.

**Incomplete but intentionally retained:** the five stub modules (admin, astro, search, subscription, trust-score), the unregistered stubs inside `users` / `verification` / `support`, all 7 worker processors and their producers, 4 unregistered crons, the `libs/common` inert infrastructure, `@app/logger`, `CloudFrontService`, and `apps/websocket`. Roughly **90 files of scaffolding**, none of which contains logic.

**Did recent PRs leave duplicate or superseded implementations?** **No.**
- **PR #79** added Entitlements *alongside* the unbuilt Subscription stubs, by explicit design — read path vs. write path, documented in the module header. Nothing was orphaned.
- **PR #80** modified the existing preference builder in place rather than adding a parallel implementation. No obsolete matching code remains.

**The one non-deletion observation worth acting on:** `ProfileResponseDto` documents itself as *"Shape returned by GET /profiles/me"* while that endpoint returns `ProfileEntity`. Beyond being dead, it is **actively misleading** to anyone reading the profiles module for the response contract.

---

## Validation Performed

| Check | Result |
|---|---|
| `npx tsc --noEmit -p tsconfig.json` | **4 errors — all pre-existing**, all in one block at `profile.service.ts:645-648` (`number \| null` vs `number \| undefined`). Unrelated to dead code. `git status backend/` confirms **no backend file was modified by this audit**, so these are the state of `main`. |
| `npx jest --silent` | **1134 passed**, 17 skipped, 12 todo, 0 failed (88 of 92 suites; 4 skipped) |
| `AppModule` reachability, incl. transitive imports | Completed — caught `EntitlementsModule` (reachable via `SettingsModule`) |
| Exhaustive exported-class reference scan (`apps/` + `libs/`, excluding generated/spec) | Completed — 106 candidates, narrowed to 1 |
| Controller / provider DI registration check | Completed per module file |
| `@Type()` nested-validation check | Completed — caught `FamilyMemberDto`, `SiblingMemberDto` |
| Swagger `@ApiProperty({ type })` check | Completed — caught `TemporaryCredentialsDto` |
| Prisma model usage (`prisma.<model>.`) | Completed — `UserSubscription` read-only, correctly classified C |
| Queue processor / cron registration | Completed — worker registers no processors; scheduler registers only `WeeklyDigestCron` |

**No backend source code was modified. No files were deleted.**
