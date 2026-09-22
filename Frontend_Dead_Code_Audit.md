# Nenjam Matrimony — Frontend Dead Code Audit

**Scope:** `Frontend/lib/` as it exists on `main` (post PR #79 / #80 / #81)
**Method:** reference-proving, not inspection. Every finding was verified by repo-wide symbol and path searches across `lib/` **and** `test/`, plus checks for provider registration, GoRouter wiring, conditional imports, and string interpolation before classification.
**Constraint:** no source code was modified and nothing was deleted. This report is the only artefact.

---

## 1. Executive Summary

**423 production Dart files** were analysed (427 total, less `l10n/` generated output and `firebase_options.dart`).

The codebase is **remarkably clean**. Exhaustive scans for unreferenced files, classes, providers, routes, endpoints and constants produced **6 findings total**, of which only **3 are genuinely dead**. There is no accumulation of legacy layers, no old-vs-new duplicate implementations, and no orphaned feature directories.

| Classification | Count |
|---|---|
| **A. Definitely dead** | **3** |
| **B. Probably dead** | **0** |
| **C. Intentionally unused / reserved** | **3** |
| **D. Backend-dependent / waiting** | **3** |
| **E. Test-only** | **0** |
| **F. Not dead (false positives investigated)** | **6** |
| **Total findings** | **15** |

Two contributing factors explain the low yield:

1. **`flutter analyze lib/` reports zero issues**, with `strict-casts` / `strict-inference` / `strict-raw-types` enabled — so unused imports and unused private declarations are already eliminated at source.
2. A recent frontend audit already removed the one substantial piece of dead code in the repo (`MatchesRepositoryImpl` and its interface). The endpoint constants below are the residue of that removal.

**Additionally, one documentation defect was found** that is not dead code but is actively misleading: a doc comment asserting a repository is "dormant, not wired" when it is fully wired and in production use (see §10).

---

## 2. Definitely Dead

| File | Symbol | Type | Evidence | Replacement | Safe to Remove | Confidence |
|---|---|---|---|---|---|---|
| `lib/features/verification/data/repositories/mock_face_verification_repository.dart` | `MockFaceVerificationRepository` | Mock repository class (whole file) | **Zero references anywhere.** File never imported by any file in `lib/`; class name returns 0 hits across `lib/` and `test/`. An exhaustive scan of every `class` declaration in the codebase found this to be **the only class with no references at all**. | `ApiFaceVerificationRepository`, wired at `face_verification_providers.dart:19` | **Yes** | **High** |
| `lib/core/network/api_endpoints.dart` | `ApiEndpoints.matches` (`/matches`) | Endpoint constant | Zero consumers in `lib/`. Backend `matches.controller.ts` has **no `@Get()` root route** — only `interest`, `shortlist` ×3, `profile-views`, `profile-view`. | Discover feed (`/discover`) serves the reel via `reelFeedProvider` | **Yes** | **High** |
| `lib/core/network/api_endpoints.dart` | `ApiEndpoints.matchDecline` (`/matches/decline`) | Endpoint constant | Zero consumers in `lib/`. **No corresponding backend route exists.** | None — the Matches "Decline" button updates local widget state only | **Yes** | **High** |
| `lib/core/network/api_endpoints.dart` | `ApiEndpoints.matchViewed` (`/matches/viewed`) | Endpoint constant | Zero consumers in `lib/`. No such backend route; profile-view recording uses `/matches/profile-view` (`matchProfileView`), which **is** consumed. | `ApiEndpoints.matchProfileView`, used by `profile_views_repository_impl.dart:40` | **Yes** | **High** |

> Counted as **3 findings** (one file + one grouped endpoint-constant finding covering three constants).

**Shared origin:** all three endpoint constants were consumed exclusively by `MatchesRepositoryImpl`, which was deleted during the recent frontend audit. The constants were deliberately left in place at the time because two sibling constants in the same block (`matchInterest`, `matchShortlist`) **are** actively used, and removing constants is a separate concern from removing a repository. They are now confirmed orphaned.

**Tests/docs referencing them:** none. No test file references `MockFaceVerificationRepository` or any of the three constants.

---

## 3. Probably Dead

**None.**

Every candidate surfaced by automated scanning resolved to either a definite classification or a proven false positive. No finding was left in a state where dynamic usage prevented a conclusion.

---

## 4. Duplicate / Superseded Code

**One instance, and it is not dead** — recorded here because it looks like duplication and will be re-flagged by any future audit.

### `MockFaceVerificationRepository` vs `ApiFaceVerificationRepository`

The face-verification feature carries both a mock and an API implementation of `FaceVerificationRepository`. Only the API one is wired. This is the **one genuine superseded-implementation case** in the codebase, and it is listed as definitely dead in §2.

**Contrast with the two legitimate mock/API pairs**, which must not be confused with it:

| Feature | Mock | API | Wired default | Status |
|---|---|---|---|---|
| Face verification | `MockFaceVerificationRepository` | `ApiFaceVerificationRepository` | **API** | ⚠️ mock is dead |
| Astro compatibility | `MockCompatibilityRepository` | `ApiCompatibilityRepository` | **Mock** | ✅ both intentional |
| Psychology | `MockPersonalityRepository` | `ApiPersonalityRepository` | **Mock** | ✅ both intentional |

The distinction is decisive: for astro and psychology **the backend does not exist**, so the mock is the working implementation and the API class is the prepared swap-in. For face verification the backend **does** exist and is wired, leaving the mock with no role.

**No other duplicate implementations were found.** There is no old-repository/new-repository pair, no legacy model alongside a canonical one, and no superseded service left after a migration.

---

## 5. Unused Routes

**None.**

Every constant in `lib/core/router/route_names.dart` was checked for references outside its own declaration file. **All are referenced.** There are no orphaned route constants, no duplicate route declarations, and no pages left unreachable after the onboarding/registration rework.

Routes were verified against `app_router.dart` registration rather than by direct symbol search alone, since GoRouter references route constants through `path:` / `name:` parameters and navigation uses `context.go` / `context.push` with the same constants.

---

## 6. Unused API / Repository Code

### Dead (see §2)
- `ApiEndpoints.matches`, `.matchDecline`, `.matchViewed` — zero consumers, no backing backend routes.
- `MockFaceVerificationRepository` — zero references.

### Not dead, despite zero direct instantiation

| Symbol | Why it stays |
|---|---|
| `ApiCompatibilityRepository` | Prepared real implementation; referenced in doc comments describing the swap. Astro backend does not exist. **Category D.** |
| `ApiPersonalityRepository` | Same pattern; Psychology backend module does not exist at all. **Category D.** |
| `SupportRepositoryUnavailable` | **Category C** — see §9. Deliberate fallback, explicitly documented. |

### Endpoint constants with zero consumers but a live backend

`ApiEndpoints.subscriptionStatus` has **zero consumers**, but the corresponding capability is partially built (PR #79 delivered the entitlements read path). It is **Category D**, not dead — see §9.

### Repository methods

No repository interface was found declaring a method with no implementation call site. `SettingsRepositoryImpl`'s methods are all reached via `settingsRepositoryProvider` from `privacy_page.dart:62` and `settings_page.dart:107`.

---

## 7. Unused Providers / State

### `matchCategoryFeedProvider` — **investigated, borderline**

| | |
|---|---|
| **File** | `lib/features/matches/presentation/providers/matches_providers.dart:20` |
| **Evidence** | Zero references in `lib/` **and** `test/` — the declaration line is the only occurrence of the name anywhere in the repository. |
| **Classification** | **C — Intentionally unused / reserved** (see reasoning below) |

This provider re-projects the shared Discover feed into per-category lists (New Profiles, etc.). Its **sibling `matchCategoryProvider` is actively used** in four places in `matches_page.dart` (lines 66, 234, 264), so the category-selection feature is live — the UI simply renders through `reelFeedProvider` rather than this projection.

**Why it is classified C rather than A:** its own doc comment documents an interim architecture — the Matches reel "temporarily reuses the shared Discover feed" pending a dedicated Daily Recommendations endpoint (`TODO(backend)` at `matches_providers.dart:30`, tracked as a pending backend feature). This provider is the projection layer that interim arrangement is built around. Removing it is defensible, but it is **a product-architecture decision, not a mechanical cleanup**, and it should be made together with the Daily Recommendations work.

**If the Daily Recommendations endpoint is descoped or implemented differently, this becomes Category A.**

### All other providers

Every other `final …Provider` declaration in `lib/` has at least one `ref.watch` / `ref.read` / `ref.listen` / override consumer. No provider is registered-but-unused, and no controller is instantiated without being driven.

---

## 8. Unused Constants / Configuration

| Constant group | Result |
|---|---|
| `ApiEndpoints` | **3 unused** — `matches`, `matchDecline`, `matchViewed` (§2). One further zero-consumer constant, `subscriptionStatus`, is Category D (§9). |
| `RouteNames` | **All used.** |
| `AppConstants` | **All used.** |
| Feature flags | **All used** — `dummyOtpEnabled`, `_useRealOtp`, `_dummyOtpInRelease` are all consumed by `otpVerifierProvider`. |
| Environment / config values | **All used.** |

> **Methodology note:** an initial automated pass flagged `AppConstants.androidPackageId` as unused. It is **not** — it is consumed through **string interpolation** at `app_constants.dart:19` (`…details?id=$androidPackageId`), which a symbol-boundary grep misses. Every other constant finding in this report was re-checked for interpolated usage before classification. This is exactly the class of false positive that makes naive "looks unused" cleanup dangerous.

---

## 9. Backend-Dependent Code That Must NOT Be Deleted

These are valid, deliberate, and would cost real work to reconstruct.

### `ApiCompatibilityRepository` — **Category D**
`lib/features/astro/data/repositories/api_compatibility_repository.dart`
A complete real implementation against `GET /astro/profile/me` and `GET /astro/compatibility/:id`. The astrology backend does not exist; `compatibilityRepositoryProvider` therefore defaults to the mock. The file carries an explicit `TODO(backend)` naming the endpoints it awaits. **Deleting it discards finished work that becomes live with a one-line provider override.**

### `ApiPersonalityRepository` — **Category D**
`lib/features/psychology/data/repositories/api_personality_repository.dart`
Same pattern, against `GET /psychology/quiz/active`, `/me`, and `POST /submit`. **No Psychology backend module or controller exists at all**, so these routes are currently unreachable — but the client code is correct and ready. Same reasoning applies.

### `ApiEndpoints.subscriptionStatus` — **Category D**
Zero consumers today. PR #79 built the premium **read** path (entitlement rule, feed probe, privacy API) but **nothing creates `UserSubscription` rows** — checkout and the Razorpay webhook remain unimplemented. This constant is the client's half of a contract that is actively being built out. **Do not remove.**

### `SupportRepositoryUnavailable` — **Category C**
`lib/features/support/data/repositories/support_repository_unavailable.dart`
A no-network fallback implementation. `supportRepositoryProvider` currently wires the **real** `SupportRepositoryImpl`, and the support backend module is live — so this class is not on the active path.

**It is nevertheless deliberate, and the codebase says so explicitly:** the provider's own comment reads *"Swap back to `SupportRepositoryUnavailable()` only if the backend is taken offline."* It is a documented operational kill-switch, not an abandoned implementation.

**This is the one finding where reasonable engineers could disagree.** It is a small file, it is referenced only in prose, and it is not reachable at runtime. Classified **C rather than A** because removing it would delete a stated operational affordance — that is a team decision, not a mechanical cleanup. If the team does not want a kill-switch, it can be removed safely.

### `local_media_image_web.dart` — **Category F, flagged for protection**
`lib/core/widgets/images/local_media_image_web.dart`
Appears in no import statement **by basename**, because it is pulled in through a **conditional import**: `if (dart.library.js_interop) 'local_media_image_web.dart'` (`local_media_image.dart:4`). **This file is load-bearing for web builds** and would be a catastrophic false-positive deletion. Any future automated dead-file tooling must special-case conditional imports.

---

## 10. Obsolete TODOs / Placeholders

**15 `TODO` comments exist in `lib/`. Fourteen are legitimate and should remain** — each names a genuinely pending backend capability (astro endpoints, psychology module, daily recommendations, subscription status, profile analytics, verification status, the five inert Search filter fields, Matrimony ID).

**None of the TODOs is attached to dead code**, and none refers to work that has already been completed — with one exception:

### ⚠️ Stale documentation — `settings_repository_impl.dart`

| | |
|---|---|
| **File** | `lib/features/settings/data/repositories/settings_repository_impl.dart:7-11` |
| **Type** | Documentation defect (**not** dead code) |
| **Claim** | *"Real backend implementation — **dormant, not wired to any provider**. TODO(backend): the `settings` controller is currently **an empty stub — zero routes**, despite `ApiEndpoints.settings`/`.privacySettings`/`.deleteAccount` all being defined."* |

**Both halves of that claim are now false:**

1. **It is wired.** `settingsRepositoryProvider` (`settings_providers.dart:11`) instantiates `SettingsRepositoryImpl`, and it is used in production at `privacy_page.dart:62` (`updatePrivacySettings`) and `settings_page.dart:107` (`deleteAccount`).
2. **The controller has routes.** PR #79 added `@Get()`, `@Patch('privacy')` and `@Delete('delete-account')` to the backend settings controller.

**Risk if left:** this comment tells a future reader that a live, production-critical repository is dormant — inviting exactly the kind of "unused, delete it" mistake this audit exists to prevent. **Recommended: correct the comment** (documentation only; no behavioural change).

### Placeholders that must remain

`isPremium: false` at `profile_page.dart:177` and `:446`, `visibilityPct: 0`, `responseTime: '—'`, and the hardcoded-`0` compatibility scores are all **correct placeholders for unimplemented backend capabilities**, each carrying an accurate `TODO(backend)`. They are not dead code and must not be "cleaned up".

---

## 11. False Positives Investigated

Documented so a future audit does not re-litigate them.

| Candidate | Why it looked dead | Verdict |
|---|---|---|
| `local_media_image_web.dart` | Never imported by basename anywhere in `lib/` | **NOT DEAD** — conditional import for web (`dart.library.js_interop`). Would break web builds. |
| `AppConstants.androidPackageId` | Zero `AppConstants.androidPackageId` references | **NOT DEAD** — used via **string interpolation** at `app_constants.dart:19`. |
| `NmTodayPriorityCard` | Only referenced inside its own file | **NOT DEAD** — consumed by `NmTodayPrioritiesSection` in the same file, which `profile_page.dart:45` imports and renders. |
| `SettingsRepositoryImpl` | Doc comment explicitly says "dormant, not wired to any provider" | **NOT DEAD** — fully wired and used in two production call sites. **The comment is wrong** (§10). |
| 16 single-file `Notifier` / `Controller` classes | Each referenced only within its own file | **NOT DEAD** — standard Riverpod: the class is named once in its `NotifierProvider` constructor in the same file. Expected, not suspicious. |
| `MockCompatibilityRepository`, `MockPersonalityRepository` | "Mock" naming suggests test scaffolding | **NOT DEAD** — these are the **wired production defaults**; their features have no backend. |

---

## 12. Recommended Cleanup Order

Ordered by **safety and dependency**, not preference. Each step is independently revertible.

**Step 1 — Remove `MockFaceVerificationRepository`** *(lowest risk)*
Delete `lib/features/verification/data/repositories/mock_face_verification_repository.dart`.
Zero references in `lib/` or `test/`; the API implementation is wired and the backend exists.
*Verify:* `flutter analyze lib/` clean, `flutter test test/features/verification/`.

**Step 2 — Remove the three orphaned endpoint constants** *(low risk, do not batch with neighbours)*
Delete `matches`, `matchDecline`, `matchViewed` from `api_endpoints.dart`.
⚠️ **Leave `matchInterest`, `matchShortlist`, `matchProfileView`, `matchProfileViews` untouched** — they sit in the same block and are actively used.
*Verify:* `flutter analyze lib/`.

**Step 3 — Correct the stale `settings_repository_impl.dart` doc comment** *(documentation only)*
Not a deletion. Prevents a future reader treating a live repository as dead.

**Steps requiring a decision before action:**

**Step 4 — `matchCategoryFeedProvider`** — resolve alongside the Daily Recommendations backend decision, not before.
**Step 5 — `SupportRepositoryUnavailable`** — keep or remove is a team call on whether the documented offline kill-switch is wanted.

**Explicitly do NOT remove:** `ApiCompatibilityRepository`, `ApiPersonalityRepository`, `ApiEndpoints.subscriptionStatus`, `local_media_image_web.dart`, or any `TODO(backend)` placeholder.

---

## 13. Final Summary

**How much code is genuinely dead:** very little — **one file (~40 lines) and three string constants.** That is roughly **0.2%** of 423 production files. This codebase does not have a dead-code problem.

**Safe to remove now (no decision needed):**
- `mock_face_verification_repository.dart`
- `ApiEndpoints.matches`, `.matchDecline`, `.matchViewed`

**Should remain:**
- Both prepared API repositories (astro, psychology) — finished work awaiting backends that do not exist.
- `ApiEndpoints.subscriptionStatus` — half of a contract actively being built.
- `local_media_image_web.dart` — load-bearing conditional import.
- All 15 `TODO(backend)` placeholders — each names a real pending capability.

**Requires human / product decision:**
- `matchCategoryFeedProvider` — tied to the Daily Recommendations architecture decision.
- `SupportRepositoryUnavailable` — keep the documented offline fallback, or not.

**One non-deletion action recommended:** correct the stale doc comment on `SettingsRepositoryImpl`, which currently describes a live production repository as dormant and unwired. Left alone, it is a trap for the next person auditing this code.

---

## Validation Performed

| Check | Result |
|---|---|
| `flutter analyze --no-fatal-infos lib/` | **No issues found** (423 files, strict-casts/inference/raw-types enabled) |
| `flutter test test/features/matches/ test/features/verification/ test/features/search/` | **112/112 passed** |
| Reference search for every A/B finding (`lib/` + `test/`) | Completed — all confirmed zero-reference |
| Exhaustive class-declaration scan across `lib/` | Completed — `MockFaceVerificationRepository` is the only zero-reference class |
| Provider registration check (all `final …Provider`) | Completed — `matchCategoryFeedProvider` is the only zero-consumer provider |
| Route registration check (`RouteNames` vs `app_router.dart`) | Completed — all constants referenced |
| Conditional-import check | Completed — caught `local_media_image_web.dart` |
| String-interpolation check | Completed — caught `AppConstants.androidPackageId` |

**No source code was modified. No files were deleted.**
