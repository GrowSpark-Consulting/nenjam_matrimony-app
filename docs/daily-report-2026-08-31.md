# Nenjam Matrimony — Daily Development Report

**Date:** 31 August 2026
**Project:** Nenjam Matrimony
**Developer:** Dhatri Patel
**Branch:** `feat/profile-detail-hero-redesign`

---

## 0. Scope note (read first)

This report documents the **registration / authentication session** carried out today. Two accuracy caveats, both verified against Git:

1. **No commits were made during this session.** The only commit dated today is `2385a7f` (12:27:58 +0530, *"feat(profile-detail): photo-first hero sharing the Matches presentation"*), which was already `HEAD` when this session began. All work below is **uncommitted**.
2. **The working tree contains a large body of pre-existing uncommitted work** unrelated to this session — trust-score removal, the profile menu page, profile-detail changes, and others. `git diff --stat` reports **164 files changed, 1429 insertions, 4549 deletions** across the whole tree. Only the subset listed in sections 4–6 belongs to this session. Several files (e.g. `onboarding_page.dart`, `login_page.dart`, `splash_page.dart`) carry **both** this session's edits and earlier uncommitted changes, so per-file line counts do not isolate today's session.

---

## 1. Today's Summary

- Built a new **Registration Landing screen** as the first screen a logged-out user sees after Splash, offering Email / Mobile / Google sign-up plus a distinct Login action.
- Introduced **`PostAuthDestination`**, a single centralised resolver that decides where an authenticated user goes, replacing four hardcoded destinations scattered across the auth screens.
- Connected the pre-existing but **orphaned `CreateProfileForPage`** ("This Profile is for") into the flow — it had a registered route that nothing navigated to.
- **Removed the "Registering for" selection** from the initial signup form and from `SignupState`; the value is now collected only after authentication.
- Fixed a real defect: `profileCreatedFor` defaulted to `'Myself'`, making an unanswered draft indistinguishable from a deliberate choice. It now defaults to empty (= "not chosen").
- Fixed a latent overflow bug in the shared `NmSocialButton` (unconstrained `Text` in a `Row`).
- Added **21 new regression tests** across two files; `flutter analyze` reports **No issues found**.

---

## 2. Major Changes Completed

### 2.1 Registration Landing screen

**What:** New screen at `/registration-landing` — brand gradient hero (logo, app name, "Your story starts here") over a light panel containing three sign-up CTAs and a Login action.

**Why:** The app previously sent logged-out users to `AuthSelectionPage`, which offered only "Login" and "Create Account" — no per-method sign-up entry.

**How:** Reuses the existing design system throughout: `NmSocialButton` ×3, `NmOutlinedButton`, `AppColors`, `AppTypography`, `AppSpacing`, `AppGradients.splash`, `AppAnimations`, `NmPageStatusBar`. No new theme, button, or provider was introduced. Google sign-in runs the existing `GoogleSignInController`; cancellation is silent, failure shows a Nenjam snackbar.

**Files:** `registration_landing_page.dart` (new), `app_router.dart`, `route_names.dart`.

### 2.2 Centralised post-authentication routing

**What:** New `PostAuthDestination.resolve()` returning one of: landing / verify-email / Profile For / registration wizard / Discover.

**Why:** Each auth path hardcoded its own destination — `discover` after email login, `registrationWizard` after OTP — so a brand-new Google user could land in Discover with no profile at all.

**How:** Order of precedence — signed out → landing; email present but unverified → verify-email; backend draft `isComplete` → Discover; `profileCreatedFor` empty → Profile For; otherwise rehydrate the draft from the backend and resume the wizard at its saved step. A failed draft lookup falls back to Profile For for a brand-new account (detected via Firebase `creationTime` vs `lastSignInTime`) and to Discover for an established one.

**Files:** `post_auth_destination.dart` (new); consumed by `login_page.dart`, `login_otp_screen.dart`, `splash_provider.dart`, `registration_landing_page.dart`.

### 2.3 "Registering for" removed from account creation

**What:** Deleted the chip row, its options list, labeller, the `_RegisterChip` widget, and the pre-auth `setProfileCreatedFor(...)` write.

**Why:** Besides being the wrong place to ask, the answer **never survived** — `email_verify_screen.dart` calls `startCreateMode()` after verification, which reset the draft and discarded it. Users answered a question that was thrown away.

**How:** `_SignUpForm` became a plain `StatelessWidget` (the chips were its only Riverpod use). The form now reads Username → Email → Password → Mobile Number, with a single 24 dp gap before "Create Account" — matching the rhythm of the other sections, so no blank space was left behind.

**Files:** `login_page.dart`, `signup_controller.dart`, `registration_page.dart`, both `.arb` files.

### 2.4 `profileCreatedFor` default corrected to "not chosen"

**What:** `BasicDetails.profileCreatedFor` now defaults to `''` instead of `'Myself'`, in both the constructor and `fromJson`.

**Why:** A non-empty default is indistinguishable from a real answer. Any check against the parsed model would conclude a brand-new user had already chosen "Myself", letting them bypass the Profile For screen and silently register as themselves.

**How:** `toJson()` already omitted the field when empty, so an unset value is never sent to the backend as a choice. `BasicDetails.isComplete` now correctly reports `false` until the question is answered. The Profile For **UI is unchanged** — it still highlights "Myself" as its default selection; only the draft's stored value differs until Continue is tapped.

A second bypass was closed in `splash_provider.dart`: a restored local snapshot was the one route into the wizard that did not pass through `PostAuthDestination`. CREATE-mode sessions with no recorded answer are now redirected to Profile For. EDIT sessions are exempt — they act on an already-finalised profile.

**Files:** `profile_draft.dart`, `post_auth_destination.dart`, `splash_provider.dart`, `registration_success_page.dart` (stale comment only).

### 2.5 `NmSocialButton` overflow fix

**What:** Wrapped the label in `Flexible` with `maxLines: 1` and ellipsis.

**Why:** The `Row` had an unconstrained `Text`, unlike its sibling buttons. The longer landing-screen labels ("Sign Up with Mobile") exposed a `RenderFlex overflowed by 68 pixels` at 320 dp.

**How:** Applies the same treatment `NmGradientButton` and `NmOutlinedButton` already document. Fixes it for every consumer, including the Login page's Google button under large text scaling or Tamil.

**Files:** `core/widgets/buttons/social_button.dart`.

---

## 3. Registration / Authentication Flow

Flow as implemented after today's changes:

```
Splash
  ↓
Registration Landing  ──────────────► Login (existing user)
  ↓                                       ↓
Email / Mobile / Google            PostAuthDestination
  ↓                                       ↓
Authentication                    ┌───────┼────────┐
  ↓                               ↓       ↓        ↓
PostAuthDestination          Verify   Resume    Discover
  ↓                          Email    Wizard   (complete)
Profile For  ("This Profile is for")
  ↓
Registration Wizard
  ↓
Psychology Quiz → Profile Review → Completing → Success
  ↓
Discover
```

Per-path detail:

| Path | Route after auth | Status |
|---|---|---|
| Email | Create Account → verify email → welcome → **Profile For** → wizard | Implemented |
| Google | sign-in → backend sync → resolver → **Profile For** (new) / wizard (incomplete) / Discover (complete) | Implemented |
| Mobile | opens the existing signup form with the mobile field focused | **Partial — see below** |
| Existing user login | resolver → Discover / resume wizard / Profile For | Implemented |

**Not implemented / mocked — stated plainly:**

- **Phone-first signup does not exist.** "Sign Up with Mobile" opens the same email-based signup form (username / email / password / mobile) with the mobile field focused. There is no `mobile → OTP → account` path. Building one requires a backend decision about accounts with no email address.
- **`OtpPage` (`/otp`) is a mock** — it uses `Future.delayed` and performs no real verification.
- **`/registration` (`RegistrationPage`) is a dead legacy stub** — nothing navigates to it and its submit handler is a mock that jumps to Discover.
- The real, working OTP screens are `login_otp_screen.dart` (phone login) and `phone_verify_screen.dart` (post-signup verification); both now route through Profile For / the resolver.

---

## 4. Files Created

| File | Purpose |
|------|---------|
| `Frontend/lib/features/authentication/presentation/pages/registration_landing_page.dart` | Sign-up landing screen: brand hero, three sign-up CTAs, Login action |
| `Frontend/lib/features/authentication/presentation/utils/post_auth_destination.dart` | Single source of truth for where an authenticated user goes next |
| `Frontend/test/features/authentication/post_auth_destination_test.dart` | 17 tests covering the resolver and the `profileCreatedFor` "unset" contract |
| `Frontend/test/features/registration/profile_for_source_test.dart` | 4 tests proving Profile For is the only writer of `profileCreatedFor` |
| `docs/daily-report-2026-08-31.md` | This report |

All five are **untracked** (`??`).

---

## 5. Files Modified

Scoped to this session (`git diff --stat` over these paths: **20 files, 375 insertions, 792 deletions**):

| File | Change |
|------|--------|
| `core/router/route_names.dart` | Added `registrationLanding` path + name; added to `publicRoutes` |
| `core/router/app_router.dart` | Registered the landing route; `/auth-selection` now redirects to it; logged-out redirect target changed from Login to the landing screen; Login route parses a `focus` hint |
| `core/widgets/buttons/social_button.dart` | Label wrapped in `Flexible` + ellipsis (overflow fix) |
| `features/authentication/presentation/pages/login_page.dart` | Removed the "Registering for" section and chip widget; `_SignUpForm` → `StatelessWidget`; added `initialSignUpFocus`; routes via `PostAuthDestination` |
| `features/authentication/presentation/controllers/signup_controller.dart` | Removed `registeringFor` field and `setRegisteringFor()` |
| `features/authentication/presentation/pages/login_otp_screen.dart` | Success path routes via the resolver instead of straight to Discover |
| `features/authentication/presentation/pages/otp_page.dart` | Signup branch targets Profile For |
| `features/authentication/presentation/pages/phone_verify_screen.dart` | Targets Profile For instead of the wizard |
| `features/authentication/presentation/utils/logout_flow.dart` | Logout returns to the landing screen |
| `features/onboarding/presentation/pages/onboarding_page.dart` | Post-onboarding target changed to the landing route (one line) |
| `features/registration/domain/models/profile_draft.dart` | `profileCreatedFor` defaults to `''` in constructor and `fromJson`; documented as the "not chosen" sentinel |
| `features/registration/presentation/pages/create_profile_for_page.dart` | Pre-selects the relation already stored in the draft instead of always resetting to "Myself" |
| `features/registration/presentation/pages/registration_welcome_page.dart` | CTA now continues to Profile For rather than the wizard |
| `features/registration/presentation/pages/registration_page.dart` | Removed a second, inert relation chip row and its unused labeller |
| `features/registration/presentation/pages/registration_success_page.dart` | Comment only — corrected a note naming the old default |
| `features/splash/presentation/pages/splash_page.dart` | Fallback destination changed to the landing route (plus comment) |
| `features/splash/presentation/providers/splash_provider.dart` | Logged-out target changed; profile check added after verification; snapshot-resume gate for unanswered CREATE sessions |
| `main.dart` | Session-expiry bounce targets the landing route |
| `l10n/app_en.arb`, `l10n/app_ta.arb` | Added 6 landing-screen keys; removed the orphaned `authRegisteringForLabel` |
| `test/responsive_audit_test.dart` | Retargeted the breakpoint test from the deleted screen to `RegistrationLandingPage` |

Generated files `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ta.dart` were regenerated via `flutter gen-l10n`.

---

## 6. Files Deleted

| File | Reason |
|------|--------|
| `Frontend/lib/features/authentication/presentation/pages/auth_selection_page.dart` (330 lines) | Superseded by `RegistrationLandingPage`. Keeping it would have left two competing landing screens. `/auth-selection` now redirects to `/registration-landing`, so any deep link or restored session still resolves. Its responsive regression test was retargeted, not dropped. |

*(The tree also shows 10 other deletions — trust-score files and similar — which belong to the pre-existing uncommitted work described in section 0, not to this session.)*

---

## 7. State Management Changes

- **`SignupState`** — `registeringFor` field and `setRegisteringFor()` removed. Authentication state no longer carries any profile concept.
- **`ProfileDraft` / `BasicDetails`** — `profileCreatedFor` default changed `'Myself'` → `''`. Empty now means "not yet chosen". `toJson()` omits the field while empty; `isComplete` requires it.
- **`RegistrationNotifier`** — unchanged in shape. `setProfileCreatedFor()` now has exactly **one** caller: `create_profile_for_page.dart:123`.
- **Post-auth routing** — new `postAuthDestinationProvider` (a plain `Provider`). No new state-management package, no new providers for auth or registration.

The value moved **layers** rather than being duplicated: it left auth state and now lives only in registration state.

---

## 8. Navigation Changes

**New route:** `/registration-landing` (`registrationLandingName`), added to `publicRoutes`.

**Modified routes:**
- `/auth-selection` — now a pure redirect to `/registration-landing`.
- `/login` — accepts a `focus` value in `extra` to pre-focus the email or mobile field on the Sign Up tab.

**Redirect / guard changes:**
- Router `redirect` for protected routes when signed out: Login → **landing**.
- `main.dart` session-expiry bounce: Login → **landing**.
- `logout_flow.dart`: Login → **landing**.
- `splash_provider.dart`: logged-out target → **landing**; after email verification, the profile state is now checked.

**New user routing:** authentication → `PostAuthDestination` → Profile For → wizard.
**Existing user routing:** authentication → `PostAuthDestination` → Discover when the backend reports the profile complete.
**Resume behaviour:** the local nav snapshot still wins when present; when absent (reinstall, new device, process killed before the debounced save), the backend draft now decides, rehydrating the wizard at its saved step. A CREATE-mode snapshot with no recorded relation is redirected to Profile For rather than resumed.

---

## 9. UI / UX Changes

- **"Registering for" removed** from the signup form; the form reflows to Username → Email → Password → Mobile Number with a single 24 dp gap before the button. No blank space, no redesign.
- **Registration Landing** — gradient hero over a light actions panel; portrait uses a 7:13 `Expanded` split, landscape (≥600 dp) switches to a side-by-side 5:6 `Row`. Content is scrollable with a min-height floor so large system fonts cannot cause overflow.
- **Logo** — reuses the app's existing code-drawn mark (rounded badge + `Icons.favorite_rounded` + app name), the same lockup used by Splash and Registration Welcome. **No logo image asset exists in the project**; none was invented.
- **Shared component fix** — `NmSocialButton` label truncation (section 2.5).
- **Design system reuse** — no new colors, typography, radii, spacing tokens, buttons, or icons were introduced. The Google CTA uses `NmSocialButton`'s existing default Google mark.
- **Accessibility** — `Semantics(button: true)` on the three sign-up CTAs; `NmSocialButton` keeps its 54 dp height.

---

## 10. Localization Changes

**Added (6 keys, English + Tamil):**

| Key | English |
|---|---|
| `registrationLandingHeadline` | Your story starts here |
| `registrationLandingNewTo` | New to Nenjam? |
| `registrationLandingSignUpEmail` | Sign Up with Email |
| `registrationLandingSignUpMobile` | Sign Up with Mobile |
| `registrationLandingSignUpGoogle` | Sign Up with Google |
| `registrationLandingHaveAccount` | Already have an account? |

**Removed:** `authRegisteringForLabel` ("Registering for" / "யாருக்காகப் பதிவு செய்கிறீர்கள்") — orphaned once the chip row was deleted.

**Retained:** `authRegForMyself` / `Son` / `Daughter` / `Brother` / `Sister` / `Friend` — still used by the Profile For screen.

**Regenerated:** `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ta.dart` via `flutter gen-l10n`.

*Note: the Tamil strings were initially written with a double-encoding bug (UTF-8 bytes stored as Latin-1) and were corrected before regeneration; the committed `.arb` holds correct Tamil.*

---

## 11. Testing & Validation

```
flutter analyze
→ No issues found! (ran in 22.8s)

flutter test --reporter failures-only
→ +294 -1: Some tests failed.   (exit code 1)
```

| Metric | Count |
|---|---|
| Passed | **294** |
| Failed | **1** |
| Skipped | Not reported by `failures-only`; none observed |

### Passed

- 294 tests, including **21 new regression tests** added today:
  - `post_auth_destination_test.dart` — **17 tests**. Covers: a fresh draft holds no choice; an absent field stays empty; explicit choices survive a round trip; an unset value is never sent to the backend; basic details are incomplete until answered; and the resolver's routing for a missing `basicDetails` section, an omitted relation, empty string, whitespace-only, an empty response body, a mid-wizard draft that never answered, and a brand-new account whose lookup fails — all → Profile For. Plus: explicit `"Myself"` and every other relation resume the wizard, a completed profile goes to Discover, unverified email wins, signed-out goes to the landing screen.
  - `profile_for_source_test.dart` — **4 tests**. `SignupState` carries no relation field; all seven options render; Continue writes the relation **and** navigates to the wizard; reopening preserves the stored choice.
- `responsive_audit_test.dart` — 13 tests pass, including the retargeted `RegistrationLandingPage` breakpoint sweep across 9 sizes (320×640 through 1024×768, portrait and landscape).

### Failed

```
test/widget_test.dart: App smoke test

[core/no-app] No Firebase App '[DEFAULT]' has been created
  - call Firebase.initializeApp()
  at createRouter (lib/core/router/app_router.dart:139)
Expected: exactly one matching candidate
  Actual: Found 0 widgets with type "NenjamMatrimonyApp"
```

**Verified pre-existing.** Evidence:

1. `git status --short -- Frontend/test/widget_test.dart` reports the file as **unmodified** — byte-identical to committed `HEAD`.
2. The test contains **0 occurrences** of `Firebase.initializeApp` — it pumps `NenjamMatrimonyApp` directly, bypassing `main()`, which is where Firebase is initialised.
3. The crashing line, `app_router.dart:139` (`ref.read(authRepositoryProvider).authStateChanges()`), is present at **the same line 139 in committed `HEAD`** — it is not code added today.

The test file is untouched and the code path it crashes on is untouched, so this failure is structural and predates this session.

### One failure introduced and fixed during the session

An earlier full run reported `+293 -2`. The second failure was in a test written today, `profile_for_source_test.dart`, which still asserted `profileCreatedFor == 'Myself'` — an assertion authored **before** the default was changed to `''`. The application behaved correctly (`Expected: 'Myself' / Actual: ''`); only the stale assertion was updated. No application code was changed to make it pass. The subsequent run confirmed `+294 -1`.

---

## 12. Known Issues / Pending Work

| Item | Status |
|---|---|
| Phone-first signup (`mobile → OTP → account`) | **Not implemented.** "Sign Up with Mobile" opens the email-based form with the mobile field focused. Needs a backend decision on email-less accounts. |
| `OtpPage` (`/otp`) | **Mocked** — `Future.delayed`, no real verification. Route registered but nothing navigates to it. |
| `RegistrationPage` (`/registration`) | **Dead legacy stub** — unreachable; submit handler is a mock jumping to Discover. Left in place per instruction, for a separate cleanup task. |
| `test/widget_test.dart` | Pre-existing Firebase-initialisation failure (section 11). Needs either a Firebase mock or removal of the whole-app pump. |
| Uncommitted working tree | 164 files changed across this session **and** substantial earlier work. Needs review and separation before committing. |
| Orphaned processes | Five stale `flutter_tester` processes from interrupted test runs were observed during the session. |

---

## 13. Technical Decisions Made Today

1. **Authentication state must not contain `profileCreatedFor`.** Removed from `SignupState`; it is a registration concern.
2. **`profileCreatedFor` belongs to registration state**, with exactly one writer — `CreateProfileForPage`.
3. **The unset state must be representable.** An empty string means "not chosen"; a non-empty default cannot be distinguished from a real answer.
4. **Profile For is collected only after authentication**, never on an account-creation form.
5. **Post-auth routing uses a centralised resolver** rather than per-screen hardcoded destinations.
6. **One landing screen, not two** — `AuthSelectionPage` was deleted and its path redirected, rather than leaving a duplicate.
7. **Reuse over recreation** — the pre-existing `CreateProfileForPage` was wired in rather than rebuilt; the existing Personality Quiz, Psychology module, Profile Intelligence, and Discover flows were left untouched.
8. **Fix shared components at the source** — the `NmSocialButton` overflow was fixed in the widget, not worked around at the call site.

---

## 14. Before vs After

**OLD**

```
Signup form (Username, Email, Password, Mobile, Registering For)
  ↓
profileCreatedFor written pre-auth
  ↓
Create Account → verify email → startCreateMode()  ← answer discarded here
  ↓
Registration Wizard  (Profile For screen never shown)
```

**NEW**

```
Signup form (Username, Email, Password, Mobile)
  ↓
Create Account → Authentication
  ↓
PostAuthDestination
  ↓
Profile For  →  profileCreatedFor written (only writer)
  ↓
Registration Wizard
```

The old order asked for the relation before the account existed and then destroyed the answer during `startCreateMode()`, so the wizard never received it. The new order asks once, after authentication, at the point where the value can actually persist. Because the draft now distinguishes "unset" from "Myself", a brand-new user cannot bypass the question, while an existing user with a completed profile is never asked again.

---

## 15. Git Status at End of Day

```
git log --since="2026-08-31 00:00:00" --until="2026-09-01 00:00:00" --oneline
2385a7f feat(profile-detail): photo-first hero sharing the Matches presentation
```

**Commits made during this session:** none. `2385a7f` (12:27:58 +0530) was already `HEAD` when the session began.

**Working tree summary** (`git status --short`):

| Status | Count |
|---|---|
| Modified (` M`) | 153 |
| Deleted (` D`) | 10 |
| Untracked (`??`) | 13 |
| Staged added (`A `) | 1 |
| Staged added + modified (`AM`) | 1 |

`git diff --stat` → **164 files changed, 1429 insertions(+), 4549 deletions(-)** (whole tree — this session plus pre-existing work).

**Staged** (pre-existing, not from this session):
- `A  Frontend/lib/features/profile_detail/presentation/widgets/verification_section.dart`
- `AM Frontend/lib/features/profile_menu/presentation/pages/profile_menu_page.dart`

**Untracked — this session:**
- `Frontend/lib/features/authentication/presentation/pages/registration_landing_page.dart`
- `Frontend/lib/features/authentication/presentation/utils/post_auth_destination.dart`
- `Frontend/test/features/authentication/post_auth_destination_test.dart`
- `Frontend/test/features/registration/profile_for_source_test.dart`
- `docs/daily-report-2026-08-31.md` *(this report — untracked)*

**Untracked — pre-existing, not from this session:**
`Frontend/lib/core/widgets/system_ui/`, `verification_checklist_entity.dart`, `test/bottom_nav_clearance_test.dart`, `test/features/profile/`, `test/features/profile_completion/profile_completion_page_test.dart`, `test/features/profile_detail/profile_detail_no_trust_score_test.dart`, `test/features/profile_menu/`, `test/light_mode_only_test.dart`, `test/no_trust_score_references_test.dart`

**Nothing was staged, committed, or pushed during this session.**

---

## 16. Next Steps

1. **Separate and commit the registration/auth work.** The tree mixes this session's ~20 files with a large body of earlier uncommitted changes. Isolating them into a focused commit is the highest priority — the work is currently unprotected.
2. **Decide the phone-first signup approach.** "Sign Up with Mobile" is the one advertised path that does not do what its label implies. Requires a backend decision on accounts with no email address.
3. **Fix or retire `test/widget_test.dart`.** It is the only failing test and has been failing independently of this work; either mock Firebase or drop the whole-app pump.
4. **Clean up the dead `/registration` and `/otp` routes** (deferred to a separate task by instruction). Both are unreachable mocks that navigate straight to Discover.
5. **Verify the three flows on a device** — the changes are covered by unit and widget tests, but Google sign-in and the OTP screens have not been exercised on real hardware this session.
