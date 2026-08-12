# Nenjam Matrimony — Daily Work Report (12 Aug 2026)

| Field | Value |
|---|---|
| **Project** | Nenjam Matrimony — AI-powered matrimonial platform |
| **Report date** | 12 August 2026 |
| **Prepared by** | Dhatripatel06 |
| **Branch** | `main` → `chore/daily-2026-08-12` |
| **Workstream** | Neon Singapore cutover · Profile Detail tab-scroll fix · Responsive audit · Registration success screen · Google Sign-In |
| **Frontend** | Flutter (Dart SDK ^3.9.2) · Riverpod · Android target |
| **Backend** | NestJS · PostgreSQL · Prisma |
| **Auth** | Firebase Auth only (no Firestore) |

---

## Summary

The backend was moved onto the shared Neon **Singapore** (`ap-southeast-1`) database and verified end to end — Prisma client regenerated, all 19 migrations confirmed applied, and the API restarted with a live connection.

Four pieces of frontend work followed. A regression investigation into the Profile Detail scroll tests found that the failures were **pre-existing, not merge-introduced**, and surfaced a genuine production defect: seven of the eight section tabs did nothing when tapped. A responsive audit across every shipped phone size uncovered three real layout defects, including one that made two registration options unreachable on every device. The registration success screen was moved off local draft estimates onto the finalized backend profile. Finally, "Continue with Google" was implemented against Firebase Auth, then diagnosed on a real device when it failed.

Two of the day's findings were corrections to stated assumptions: the registration success screen was **not** hardcoded (it already read live draft data), and the Google Sign-In fingerprints had **not** taken effect (the regenerated `google-services.json` had never been downloaded into the project).

---

## Tasks Completed

- **Cut the backend over to Neon Singapore** — regenerated the Prisma client, confirmed `migrate status` reported *Database schema is up to date* against `ap-southeast-1`, and restarted the API. `migrate deploy` was not required; no destructive commands were run.
- **Investigated the Profile Detail scroll-test regressions** — established a baseline on `44ccc34` and proved the failures pre-dated the merge (the test file is byte-identical across both commits).
- **Fixed the Profile Detail tab-to-section scroll bug** — tapping any tab other than *About* silently did nothing. Committed as `52542d9`.
- **Rewrote the Profile Detail scroll diagnostics** — 3/15 passing in 40m 25s → 15/15 in 36s.
- **Ran a full responsive audit** — 320/360/375/393/412/480 px, portrait and landscape, English and Tamil, with safe-area insets and a simulated keyboard.
- **Fixed three responsive defects** — registration relation chips, the subscription card, and the profile wizard's fixed chrome.
- **Added a page-level responsive audit suite** covering Discover, Matches, Profile Detail, Registration, Profile Wizard, Inbox, Premium and Settings.
- **Made the registration success screen backend-driven** — real completion percentage, photos and horoscope state from `GET /profiles/me`, with draft-first painting and background refresh.
- **Implemented Google Sign-In** — `google_sign_in 7.2.0`, a new `GoogleAuthService`, Riverpod wiring through the existing `authRepositoryProvider`, and a dedicated loading state.
- **Diagnosed Google Sign-In failing on a physical device** and identified the root cause from on-device logs.
- **Added the INTERNET permission to the main Android manifest** — it was previously declared only for debug and profile builds.

---

## Technical Findings

### 1. Profile Detail — tab taps were a no-op (production defect)

`_scrollToSection` read `_sectionKeys[index].currentContext` and skipped `Scrollable.ensureVisible` when it was `null`. Sections live in a `SliverList`, which mounts only the run near the viewport, so every off-screen section had a null context. On-device instrumentation confirmed the tap fired (`w500 → w700`, tab visibly selected) while scroll offset stayed at `0.0`.

**Only the *About* tab worked** — it is the one section mounted at rest. The other seven were dead.

Fixed by walking the viewport toward the target in bounded steps until the sliver builds it, then handing off to `ensureVisible`. Convergence measured at 2–7 steps against a 40-step cap.

### 2. Four test timeouts were a test defect, not a product one

Four diagnostics awaited `position.animateTo(...)` with nothing pumping frames — a deadlock that ran until the 10-minute harness timeout. That alone accounted for 40 of the suite's 40m 25s.

A second flaw was found in the audit harness itself: Flutter reports a given `RenderFlex` overflow **once per render object**, and `pumpWidget` reuses render objects, so only the first size in a sweep reported. Every later width looked clean until the tree was torn down between configurations.

### 3. Responsive defects found

| Screen | Defect | Impact |
|---|---|---|
| Registration | `Row` of five relation chips, ~673dp intrinsic | 353dp overflow at 320px, 33dp at 640px — 2 of 5 options unreachable on every phone |
| Premium | Subscription card header and price rows had no flexible child | Overflow at 320–375px, worse in Tamil |
| Profile wizard | ~270dp of unshrinkable chrome | 168dp overflow with keyboard; 36dp in landscape with no keyboard at all |

Discover, Matches, Profile Detail, Inbox and Settings passed at every size, orientation and locale.

### 4. Google Sign-In — root cause

The APK was signed with a key whose SHA-1 was not registered in the Firebase project:

```
SHA-1 in google-services.json : 15fe8c7189b3d8f8e11f1f5c99a363ad61cd0a94
SHA-1 of the signing keystore : 6d564e1b88449e09036daece07ca51ed117bab6f
```

The file was still dated 13 July — the fingerprint had been added in the Firebase Console, but the regenerated `google-services.json` was never downloaded into the project. Play Services therefore refused to issue an ID token and Credential Manager returned status `[16]`.

On-device log confirming the failure point:

```
[GSI] initialize() OK
[GSI] authenticate() starting…
I/CredManProvService: GetCredentialResponse error returned from framework
[GSI] authenticate() GoogleSignInException
    code:        GoogleSignInExceptionCode.canceled
    description: [16] Account reauth failed.
```

`google-services.json` has since been replaced and now carries the correct fingerprint. **Awaiting an on-device retest to confirm.**

### 5. A masking bug the device log exposed

`google_sign_in_android` collapses **every** Credential Manager failure into `GoogleSignInExceptionCode.canceled`. The cancellation path treated that as a user dismissal and stayed silent, so a hard failure produced no feedback at all — indistinguishable from a dead button. Failures carrying a bracketed play-services status (`[16]`, `[10]`) are now surfaced as errors; only a description-free cancel stays silent.

### 6. Corrections to stated assumptions

- **The registration success screen was not hardcoded.** `Profile 100% Complete` is a parameterised l10n template, and the screen already read live draft values. The real gap was that it used the client's own estimate rather than the server's computed figure — which is what changed.
- **The Google tab labels were not stale.** `Horoscope`, `Preferences`, `Verification` and `Timeline` all still exist; they matched zero widgets because the tab bar is a lazy horizontal `ListView` and those tabs had never been built.
- **`google_sign_in` 7.x is not API-compatible with the 6.x examples** in most documentation: `signIn()` → `authenticate()`, cancellation throws rather than returning `null`, and `accessToken` is no longer available from `authentication` (ID token only, which is all Firebase requires).

---

## Verification

| Check | Result |
|---|---|
| `pnpm prisma migrate status` (Singapore) | Database schema is up to date — 19 migrations |
| API restart | `Connection : SUCCESS`, 795 ms latency, port 3000 |
| `flutter analyze lib test` | No issues found |
| Profile Detail scroll diagnostics | 15/15 pass (36s, from 3/15 in 40m 25s) |
| Responsive page audit | 8/8 pass across 12 size/orientation configs × 2 locales |
| Registration success screen | 12/12 pass |
| Google Sign-In controller | 8/8 pass |
| Full Flutter suite | **160 passed, 1 failed** |
| `flutter build apk --debug` | Succeeded |

The single failure is `test/widget_test.dart` ("App smoke test"), which dies on a `FirebaseException` during bootstrap. It is pre-existing and unrelated to this work.

---

## Blockers

- **Google Sign-In is unconfirmed on device.** The fingerprint mismatch is fixed in the project, but the end-to-end flow has not yet been re-run on hardware. If `[16]` persists, the remaining cause is the device's own Google account needing re-authentication.
- **`widget_test.dart` remains red** — Firebase is not initialised in the test harness.

---

## Next Actions

1. **Retest "Continue with Google" on the physical device** with the updated `google-services.json`. A `flutter clean` is required so Gradle regenerates the resources.
2. **Re-register any other machine's fingerprint.** The regenerated file contains only this machine's SHA-1; the previous `15fe8c71…` entry is gone, so any teammate or CI runner that previously worked will now fail until their fingerprint is added back.
3. **Replace the debug signing config for release builds.** `release` currently signs with the debug key, and the Play App Signing SHA-1 must also be registered or Google Sign-In will break in production.
4. **Remove the temporary `[GSI]` diagnostic logs** once sign-in is confirmed. They are `kDebugMode`-gated and will not ship, but they are scaffolding.
5. **Fix `DATABASE_HOST` in `backend/.env`** — it still points at the old `us-east-1` host. Prisma reads `DATABASE_URL` so it is currently harmless, but anything building a connection from the discrete vars would hit the wrong region.

### Optional follow-ups

- Extend the responsive harness with touch-target and on-screen-CTA assertions; it currently proves only the absence of layout exceptions.
- Rotate the credentials committed to `backend/.env` — `JWT_SECRET` is still the placeholder value, and the file carries live Neon, AWS and Firebase keys now that the database is shared.
- Confirm **Authentication → Sign-in method → Google** is enabled in the Firebase Console; this cannot be verified from the repository.

---

## Status

🟡 All frontend work verified and green; Google Sign-In fix applied but awaiting on-device confirmation.
