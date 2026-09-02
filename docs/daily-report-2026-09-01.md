# Nenjam Matrimony — Daily Development Report

**Date:** 1 September 2026
**Project:** Nenjam Matrimony
**Developer:** Dhatri Patel
**Branch:** `feat/profile-detail-hero-redesign`

---

## 0. Scope note (read first)

Two accuracy caveats, both verified against Git rather than recalled:

1. **Three commits were made today**, all pushed to `origin/feat/profile-detail-hero-redesign`. The bulk of today's work is **still uncommitted**: `git diff --stat` reports roughly **37 files changed**, plus **19 untracked files**.
2. **The working tree also carries pre-existing uncommitted work from earlier sessions** — five deleted `registration_*` helpers, `profile_wizard_page.dart`, `registration_sticky_bottom_bar.dart` and `widget_test.dart` were already modified before today. Per-file line counts therefore do **not** isolate today's session for those files.

The backend endpoint added today **is deployed and live in production** (verified by real HTTP request, section 8).

---

## 1. Today's Summary

- Replaced the signup path with a **ten-screen onboarding flow** (Profile For → Religion → Email + Mobile → State + City → Marital → Education → Income → Photos → About → OTP → Discover), built on the existing `ProfileDraft`, repository and Riverpod state.
- Added a new **Welcome Back** login screen; the old tabbed Login/Sign Up page is no longer the auth entry.
- Added **duplicate-account detection**, backed by a new `POST /auth/account-exists` endpoint on the existing `FirebaseService`.
- Replaced the onboarding OTP with an **isolated static verifier** after real Firebase Phone Auth failed with `BILLING_NOT_ENABLED`.
- Fixed a **white-on-white dropdown** bug affecting every dropdown in the app.
- Fixed **landscape + keyboard overflow** on three onboarding steps.
- Restored the **existing-member short-circuit** in `PostAuthDestination` so login never drags an existing user into signup onboarding.
- `flutter analyze` clean; **333 Flutter tests** and **548 backend tests** pass; debug APK builds and runs on device.

---

## 1a. Authentication — what works today, and what is still required

The new UI is finished. Authentication behind it is **complete on the login side and deliberately incomplete on the signup side**, because signup now opens Profile For directly with no credential form in front of it. This section states exactly where that leaves things, so nobody has to infer it from the code.

### Working today

| Path | Status | Notes |
|---|---|---|
| **Login → Mobile OTP** | Real | Welcome Back → existing `LoginOtpScreen` → Firebase phone sign-in → `PostAuthDestination` |
| **Login → Password** | Real | Existing email/password form and controller |
| **Login → Google** | Real | Existing `GoogleSignInController` + backend sync |
| **Login → Email** | Real | Existing email login |
| **Sign Up with Google** | Real | Full Google/Firebase auth, then Profile For |
| **Existing-user routing** | Correct | `isComplete == true` → Discover; an existing member is never pulled into signup onboarding |
| **Duplicate detection** | Live | `POST /auth/account-exists`, verified in production |
| **Onboarding OTP** | Static, by design | Any numeric code of the expected length; no SMS, no provider call |

### Not done — required for proper auth

1. **Email and Mobile signup create no Firebase account.** Both buttons go straight to Profile For, so there is **no session, no uid and no ID token** for the whole of onboarding on those two paths. Consequence: every per-step backend PATCH is skipped (each needs a token), and the profile lives only in the local draft and its `SharedPreferences` snapshot until a session exists. Only the Google path produces a real account today.

2. **A local development bridge currently substitutes for the session.** The OTP step writes `StorageService.onboardingCompleted`, and the router guard treats that flag as permission to enter the app. **This is an auth bypass and must be deleted before release** — it is device-local and proves nothing about identity. It exists only so the flow can be walked end to end while signup creates no account.

3. **A decision is outstanding: where credentials get collected.** Two workable options, either of which removes items 1, 2 and 6 together:
   - **(a) Before Profile For** — a Nenjam-styled signup screen driving the existing `SignupController` (name / email / password). This was built and then removed on request, because it put a screen back in front of onboarding. Restoring it is roughly a one-file change.
   - **(b) At the Email + Mobile step** — add a password field there and create the account mid-flow, then flush the draft. Keeps onboarding first, but steps 1–2 still run session-less and their answers must be replayed after account creation (`flushOnboardingToBackend` already does exactly that).

4. **Real OTP is not wired.** Swapping the `otpVerifierProvider` override restores it with no screen changes, but it needs **Firebase SMS billing enabled** — it currently fails with `BILLING_NOT_ENABLED`.

5. **Anonymous Auth is disabled** in the Firebase project (`admin-restricted-operation`). Relevant only if a session-without-credentials approach is revisited; it was tried and rejected.

6. **The duplicate-account check cannot yet prevent a duplicate Firebase account** on the email/mobile paths, because no Firebase account is created there. It correctly blocks the *flow*, but the guarantee only becomes real once option (a) or (b) lands.

### Suggested order of work

1. Pick option (a) or (b) and land it — this alone resolves items 1, 2 and 6.
2. Delete `StorageService.onboardingCompleted`, its `AppConstants` key, and the `_onboardingCompletedLocally()` branch in `app_router.dart`.
3. Remove the onboarding routes from `RouteNames.publicRoutes` so the guard is strict again.
4. Once SMS billing is enabled, swap `otpVerifierProvider` for a Firebase-backed verifier.

---

## 2. Commits Made Today

| Hash | Time | Subject |
|---|---|---|
| `6fbc52d` | 16:13 | `feat(backend): add account availability check for signup` |
| `6b6553a` | 17:10 | `fix(onboarding): end signup in a session so OTP reaches Discover` |
| `d5f0538` | 17:23 | `feat(auth): add a back arrow to the Nenjam landing screen` |

### 2.1 `6fbc52d` — account availability endpoint (5 files, +151)

`FirebaseService.accountExists()` looks up an email via `getUserByEmail` and a mobile via `getUserByPhoneNumber`. `auth/user-not-found` is the expected "no"; any other failure is rethrown, because reporting a taken identifier as free is how duplicate accounts get created.

`POST /auth/account-exists` exposes it — deliberately unauthenticated (the caller has no token yet) and kept narrow in exchange: two booleans only, no uid/name/provider, plus a tighter throttle than the default.

### 2.2 `6b6553a` — session at the end of onboarding (3 files, +302)

Entering the OTP bounced the member back to the landing screen, because `/discover` is auth-gated and signup ran signed out. **This commit's approach (an anonymous Firebase session) was later reverted** — see section 5.

### 2.3 `d5f0538` — landing back arrow (1 file, +57 / −8)

The screen handled Android system back but had no visible control. The arrow is layered over the hero in a `Stack`, because the hero bleeds to the screen edge in both orientations. Arrow and system gesture share one `_back()`.

---

## 3. Uncommitted Work

### 3.1 The ten-screen onboarding flow

| # | Screen | Route | Required |
|---|---|---|---|
| 1 | Profile For | `/create-profile-for` | `profileFor` |
| 2 | Your Religion | `/registration/religion` | religion, community, living in |
| 3 | Email + Mobile | `/registration/contact` | email, mobile |
| 4 | State + City | `/registration/profile-basics` | state, city |
| 5 | Marital Status | `/registration/marital-status` | marital status, height |
| 6 | Education | `/registration/education` | qualification |
| 7 | Income + Work | `/registration/income` | annual income |
| 8 | Add Photos | `/registration/photos` | — (optional) |
| 9 | About Yourself | `/registration/about` | about |
| 10 | Verify Mobile | `/registration/verify-mobile` | static OTP |

Every field maps onto a section `ProfileDraft` already had — nothing introduces a second representation of existing backend data. `OnboardingStepScaffold` holds the crest / headline / fields / pinned-CTA shape once, so ten screens share one implementation of scrolling, safe areas, the disabled-CTA explanation and save-failure handling.

### 3.2 Auth entry

The landing keeps its three sign-up buttons and Login. **All three sign-up buttons open Profile For directly** — see §1a for the consequences. Login opens the new Welcome Back screen; the old tabbed form remains only at `/login/form`, reached for the password and email login actions.

### 3.3 Duplicate-account detection

The Email + Mobile step calls `/auth/account-exists` on Continue. Three outcomes, not two: free, taken, and **"could not tell"** — a failed lookup blocks signup rather than assuming availability. Editing either field clears the verdict so the next Continue re-checks.

### 3.4 Static OTP

`OtpVerifier` is a one-method seam; `MockOtpVerifier` accepts any numeric code of the expected length and contacts nothing.

---

## 4. Bugs Found and Fixed

### 4.1 Dropdowns rendered white-on-white
`AppTypography` styles come from `GoogleFonts` and carry **no colour**, and `DropdownButtonFormField.style` paints the *open menu* — so items resolved to white on white. Fixed in the shared `NmDropdown` with explicit `dropdownColor` and `style` colour, fixing every dropdown at once. Verified on device by pixel analysis: seven evenly-spaced dark-text bands in the open Religion menu.

### 4.2 Real SMS sent from the onboarding flow
The Email + Mobile step handed a new number to the real verify-phone screen, which called `verifyPhoneNumber()` and failed with `BILLING_NOT_ENABLED`. The handoff was removed; the step now captures and stores only.

### 4.3 Landscape + keyboard overflow
Contact, Education and Income overflowed by up to 82px. Header and footer now shrink below a 420dp usable height.

### 4.4 Login dragged existing users into signup
`PostAuthDestination` had no "already registered" short-circuit, so an existing member missing any one of the ten new fields was routed into signup onboarding on every login. Restored: `isComplete == true` → Discover.

---

## 5. Approaches Tried and Reverted

Recorded because both were wrong turns and the reasons matter.

- **Anonymous Firebase session.** The OTP step called `signInAnonymously()` to satisfy the auth guard. Firebase rejected it with `admin-restricted-operation` — Anonymous Auth is disabled in the project — and it reintroduced a Firebase dependency into a step required to be static. **Removed.**
- **A Nenjam-styled credential screen before Profile For.** Built to restore real account creation without the old tabbed UI, then **removed on request** because signup must open Profile For directly. It remains the cleanest route to proper auth — option (a) in §1a.

---

## 6. Files Created (19 untracked)

**Core / domain:** `core/constants/profile_options.dart`, `registration/domain/models/onboarding_forms.dart`, `registration/domain/models/profile_for_relation.dart`, `authentication/domain/services/otp_verifier.dart`, `authentication/domain/services/account_availability.dart`

**Screens:** `onboarding_religion_page.dart`, `onboarding_contact_page.dart`, `profile_basics_page.dart`, `onboarding_marital_page.dart`, `onboarding_education_page.dart`, `onboarding_income_page.dart`, `onboarding_photos_page.dart`, `onboarding_about_page.dart`, `welcome_back_page.dart`, `widgets/onboarding_scaffold.dart`

**Tests:** `otp_verifier_test.dart`, `onboarding_contact_duplicate_test.dart`, `onboarding_religion_page_test.dart`, `profile_basics_page_test.dart`, `onboarding_test_support.dart`

---

## 7. Files Modified (~37 tracked)

**Routing / core:** `app_router.dart`, `route_names.dart`, `app_constants.dart`, `storage_service.dart`, `api_endpoints.dart`, `app_dropdown.dart`, `matrimony_selectors.dart`

**Authentication:** `post_auth_destination.dart`, `registration_landing_page.dart`, `auth_repository_impl.dart`, `firebase_auth_service.dart`, `email_verify_screen.dart`, `phone_verify_screen.dart`

**Registration:** `registration_provider.dart`, `create_profile_for_page.dart`, `onboarding_verify_mobile_page.dart`, `step_basic_info.dart`, `step_education.dart`, `step_location.dart`, `step_religion.dart`

**Other:** `splash_provider.dart`, five l10n files, four test files

> `profile_wizard_page.dart`, `registration_sticky_bottom_bar.dart`, `widget_test.dart` and the five deleted `registration_*` helpers carry **earlier uncommitted work**, not today's.

---

## 8. Production Verification

Against `https://api-production-83c6.up.railway.app`:

| Check | Result |
|---|---|
| `GET /health` | 200 |
| `POST /auth/account-exists` | 200 `{"emailExists":false,"phoneExists":false}` |
| Response keys | exactly `emailExists`, `phoneExists` — both `bool`, no uid/email/phone/provider |
| Malformed email | 400 `"email must be a valid address"` |
| Non-E.164 phone | 400 `"phone must be in E.164 format…"` |

**On device (Android 14):** APK installs and launches clean; landing renders; Sign Up opens Profile For; dropdowns render correctly; back arrow returns to Language selection; **no** `verifyPhoneNumber` / `PhoneAuthProvider` / SMS / `BILLING_NOT_ENABLED` in logcat across the session.

---

## 9. Testing & Validation

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **333 passed** |
| Backend `tsc --noEmit` | clean |
| Backend `jest` | 57 suites, **548 passed**, 12 todo |
| `flutter build apk --debug` | Success |
| Responsive audit | 18 screens × 12 size/orientation combos × 2 locales, no overflow |

One **pre-existing** backend prettier error remains at `firebase.service.ts:229` (`withTimeout`) — untouched by today's diff and deliberately left alone.

---

## 10. Known Limitations

1. **Signup creates no account on the email/mobile paths** — see §1a, items 1–3. This is the main outstanding item.
2. **The router contains a development auth bypass** (`onboardingCompleted`) that must be removed before release.
3. **Rate limiting is diluted.** `/auth/account-exists` is set to 10/60s but production allowed 38 of 40 before returning 429 — consistent with `throttling.ts`'s documented per-replica in-memory store (~4 replicas). Pre-existing API-wide, but it matters more here because this route is unauthenticated and enumeration-capable.
4. **Community and city scoping are client-side** in `ProfileOptions`; the backend has no lookup endpoint.
5. **Existing-account cases untested in production** — verifying `emailExists: true` would mean creating real production accounts.
6. **Photos are not a resume gate** (optional by design); every other step is.
7. **Device walk incomplete** — the last five onboarding screens, the duplicate paths and Discover were not exercised end to end on device.

---

## 11. Architecture Notes

- **Old 13-step CREATE wizard:** `RouteNames.registrationWizard` is referenced only by the route definition, `open_edit_profile.dart` (Edit Profile), `profile_review_page.dart` and two route-restoration lists. **No signup path reaches it**, and `PostAuthDestination` has no branch into it. Edit Profile is untouched.
- **No duplicate systems:** one authentication implementation, one registration repository, one OTP seam, one account-availability checker.
