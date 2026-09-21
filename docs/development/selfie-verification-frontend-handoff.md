# Selfie Verification: Frontend Handoff (Flutter, Android)

**For:** Dhatri (Flutter / Android frontend)
**Date:** 2026-09-21
**Status:**
- The **backend is implemented** and ships **switched off** (`FACE_VERIFICATION_ENABLED=false`). §4 is the real contract.
- The AWS IAM resources don't exist yet, so every endpoint answers `503 NOT_AVAILABLE` until the backend team enables the feature on dev.
- Start with the **mock repository** (§6) and the **Android spike** (§10).

**Scope:** Android only. iOS is out of scope.

---

## 1. What we're building

"Selfie Verification" is two AWS checks:

- **Face Liveness** proves a live person is in front of the camera.
- **CompareFaces** proves that person is the one in the member's **current primary profile photo**.

When both pass, the backend records the member as **Face Verified** and the existing badges light up.

```
Flutter (member signed in with Firebase)
  │ 1. POST /verification/face/sessions   { consent: true }
  ▼
NestJS ──► checks eligibility, creates the AWS liveness session, mints 15-minute AWS
  │        credentials that allow ONE action (rekognition:StartFaceLivenessSession)
  ▼
Flutter ──MethodChannel──► native LivenessActivity (Kotlin, Amplify FaceLivenessDetector)
                              │ 2. streams camera video DIRECTLY to AWS Rekognition
                              ▼
                           onComplete / onError   (NO pass/fail result)
  │ 3. POST /verification/face/complete   { attemptId, clientOutcome }   (immediately)
  ▼
NestJS ──► GetFaceLivenessSessionResults ──► reads the primary photo from S3
       ──► CompareFaces(reference selfie vs primary photo) ──► decides ──► PostgreSQL
  ▼
Flutter shows the backend's decision. Badges update from the backend.
```

**The three rules that matter most:**

1. **The app never decides the result.** The native `onComplete` only means the capture finished. Always call `/complete` and show only what the backend returns.
2. **No AWS keys in the app, ever.**
   - Not in `.env.*`, assets, `BuildConfig`, `SharedPreferences` or `StorageService`.
   - The only AWS credentials the app ever holds are the short-lived ones from `POST /verification/face/sessions`.
   - Hold them in memory for one attempt. Never log them, never save them.
3. **Call `/complete` right away.** AWS deletes a liveness session **3 minutes** after it's created (`expiresAt` in the response). After that the attempt can only end as `EXPIRED`, and the member has to start again.

---

## 2. Why a native bridge (not a pub.dev package)

- AWS has **no official Flutter Face Liveness SDK** (open request: aws-amplify/amplify-flutter#6556). The AWS-supported Android component is `com.amplifyframework.ui:liveness`, a **Jetpack Compose** composable. Latest checked: **1.11.0**, which depends on Kotlin stdlib 2.2.0, Compose BOM 2026.03.00, CameraX 1.4.2 and LiteRT.
- The only pub.dev wrapper (`face_liveness_detector`) comes from an unverified publisher, needs Amplify/Cognito config files, and requires changing `MainActivity`. **Don't use it.**
- **Keep `MainActivity : FlutterActivity()`.** The Compose UI runs in its own small native `ComponentActivity`, which Flutter launches through a `MethodChannel`.
- Use the component's **custom `credentialsProvider`** with the backend-issued credentials. That means **no Amplify Auth, no Cognito, no `amplifyconfiguration.json`**.
  - The Amplify docs say `fetchAWSCredentials` is called **once at start, with no refresh**.
  - That's fine here: the credentials last 15 minutes and a session lasts 3.

---

## 3. Android build changes

All additive. Current toolchain: AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14.3, Java 17, desugaring already on.

| File | Change |
|---|---|
| `Frontend/android/settings.gradle.kts` | Add `id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false`. With Kotlin 2.x this replaces the `composeOptions { kotlinCompilerExtensionVersion }` block in the Amplify docs. **Don't use that block.** |
| `Frontend/android/app/build.gradle.kts` | Apply `id("org.jetbrains.kotlin.plugin.compose")`. Add `buildFeatures { compose = true }`. Add `com.amplifyframework.ui:liveness:1.11.0` (pin exactly; 1.8.2 and 1.9.0 are flagged by AWS) and `androidx.activity:activity-compose`. Make minSdk explicit: `minSdk = maxOf(24, flutter.minSdkVersion)`. **Don't** add `aws-auth-cognito`. If the AAR-metadata check asks for a higher compileSdk, use `compileSdk = maxOf(36, flutter.compileSdkVersion)`. |
| `Frontend/android/app/src/main/AndroidManifest.xml` | Register `.liveness.LivenessActivity` with `android:exported="false"`, `android:screenOrientation="portrait"` and a no-action-bar theme. `CAMERA` is **already declared**. |
| `Frontend/android/app/src/main/kotlin/com/growspark/nenjam/MainActivity.kt` | **Keep `FlutterActivity`.** Only add `configureFlutterEngine` to register the channel (§5). |
| `Frontend/android/app/proguard-rules.pro` | R8 is on for release. Build a **release** APK and run a full check on a real device. Add keep rules (likely `com.amplifyframework.**`, `aws.sdk.kotlin.**`, `aws.smithy.kotlin.**`, LiteRT) **only if release breaks**, with a comment saying what broke. |

The spike also has to check these, because 1.11.0 bundles LiteRT native libraries, CameraX and media3:
- APK size increase
- **16 KB page alignment** (a Play requirement)
- duplicate-class or protobuf clashes with Firebase

---

## 4. Backend contract (implemented)

- Every endpoint uses `FirebaseAuthGuard`. The normal `ApiClient` / `AuthInterceptor` sends the Firebase ID token.
- Every endpoint acts **only on the signed-in member's own data**.
- These are **not** the `/verification/status` or `/verification/documents` endpoints (those are for income/asset/Aadhaar/NRI documents and don't exist yet).

### 4.1 `GET /verification/face`: current state

```json
{
  "status": "UNVERIFIED" | "VERIFIED" | "REVOKED",
  "verifiedAt": "2026-09-21T10:00:00.000Z" | null,
  "canStart": true,
  "blockedReason": null | "NOT_AVAILABLE" | "ALREADY_VERIFIED" | "NO_PRIMARY_PHOTO" | "UNSUPPORTED_PHOTO" | "ATTEMPT_LIMIT",
  "attemptsRemainingToday": 3,
  "retryAfter": null | "2026-09-22T09:14:00.000Z"
}
```

- `REVOKED` means the member was verified, but the photo they were matched against is **no longer their primary photo** (replaced, deleted, or another photo made primary). Show **"Re-verify"**, and `canStart` will be true again.
- `NOT_AVAILABLE` means the feature is off, not configured, or at today's global limit. Hide or disable the entry point.
- `attemptsRemainingToday` counts a **rolling 24 hours** (3 per member by default).

### 4.2 `POST /verification/face/sessions`: start an attempt

Request: `{ "consent": true }`. Send this only after the member ticks the consent box (§6.2). Any other value gets `400`.

`201` response:

```json
{
  "attemptId": "uuid",
  "sessionId": "uuid",
  "region": "ap-south-1",
  "expiresAt": "2026-09-21T10:03:00.000Z",
  "credentials": {
    "accessKeyId": "ASIA...",
    "secretAccessKey": "...",
    "sessionToken": "...",
    "expiration": "2026-09-21T10:15:00.000Z"
  }
}
```

Before anything costs money, the backend checks:
- the feature is enabled
- the member isn't already verified
- a primary photo exists and is a **JPEG or PNG under 5 MB** (checked on the real bytes, so a WebP renamed `.jpg` is still caught)
- the per-member and global limits

### 4.3 `POST /verification/face/complete`: backend decides

Request:

```json
{ "attemptId": "uuid", "clientOutcome": "COMPLETED" | "CANCELLED" | "ERROR", "clientErrorCode": "CAMERA_PERMISSION_DENIED" }
```

- `clientOutcome` and `clientErrorCode` are optional.
- They're **stored for audit only**. They can close an attempt AWS still reports as unfinished; they never make it pass.
- `clientErrorCode` allows letters, digits and `_ . : -` only, up to 100 characters.
- The call is **idempotent**: calling it again for a decided attempt returns the same decision.

`200` response:

```json
{
  "attemptId": "uuid",
  "status": "VERIFIED" | "FAILED",
  "reason": null | "FAILED_LIVENESS" | "FAILED_MATCH" | "NO_FACE_IN_PHOTO" | "MULTIPLE_FACES_IN_PHOTO"
                 | "UNSUPPORTED_PHOTO" | "NO_REFERENCE_IMAGE" | "PHOTO_CHANGED" | "EXPIRED" | "CANCELLED" | "ERROR",
  "canRetry": true,
  "attemptsRemainingToday": 2
}
```

The backend **never returns confidence or similarity numbers**. Don't show scores.

### 4.4 Error responses

Error bodies are Nest's `{ statusCode, message }` plus a stable **`code`**. Branch on `code`, never on `message`.

| HTTP | `code` | Meaning | UI |
|---|---|---|---|
| 503 | `NOT_AVAILABLE` | Off, not configured, or global daily limit reached | "Verification is unavailable right now" |
| 409 | `ALREADY_VERIFIED` | Already verified against the current primary photo | Refresh state, show verified |
| 422 | `NO_PRIMARY_PHOTO` | No primary photo (or its file is missing) | "Add a clear photo of your face first" + button to the photo manager |
| 422 | `UNSUPPORTED_PHOTO` | Primary photo isn't a JPEG/PNG under 5 MB | "Update your main photo" + photo manager |
| 429 | `ATTEMPT_LIMIT` | Daily limit; body also has `retryAfter` (ISO) | "You've reached today's limit — try again after …" |
| 503 | `PROVIDER_UNAVAILABLE` | AWS failed to create the session or credentials | "Temporarily unavailable, please try again" |
| 404 | `ATTEMPT_NOT_FOUND` | Unknown attempt, or not this member's | Restart the flow |
| 409 | `ATTEMPT_IN_PROGRESS` | Another `/complete` for this attempt is running | **Retry `/complete`** after a short delay |
| 409 | `RESULT_NOT_READY` | AWS hasn't finished processing | **Retry `/complete`** after a short delay |
| 400 | *(none)* | Validation error (e.g. `consent` not `true`) | Developer error; fix the request |
| 429 | *(none)* | Normal rate limiter (not the daily limit) | Back off and retry |
| 401 | *(none)* | Existing interceptor flow | Don't handle specially |

**`ApiException.code` is already implemented** in `lib/core/network/api_exception.dart`. `unwrapOrThrow` fills it from the body's `code` field, so your repository just throws the usual `ApiException` and the flow controller switches on `e.statusCode` + `e.code`. Existing callers are unaffected (it's an optional named parameter). Covered by `test/core/network/api_exception_test.dart`.

### 4.5 Where the badge comes from: no client work needed

- The backend works out "verified" **when it's read**: verified only while the matched photo is still the member's primary photo, with the same stored image.
- It's calculated once, in the **shared profile-card query** (`FEED_PROFILE_SELECT` + `ProfileFeedMapper`). So `isVerified` is consistent on every card surface: Discover, Search, Nearby, profile views, shortlist, interests, chat conversations and blocked members.
- The Flutter widgets already render `isVerified`. They light up on their own, and the badge disappears on every surface as soon as the member changes their primary photo.

---

## 5. Native bridge contract

**Channel:** `com.growspark.nenjam/face_liveness`
**Method:** `startLiveness`

Args:
```
{ sessionId, region, accessKeyId, secretAccessKey, sessionToken, expirationEpochSeconds }
```

Result, always a map; never throw a PlatformException for expected outcomes:
```
{ "outcome": "COMPLETED" | "CANCELLED" | "ERROR", "errorCode": String?, "errorMessage": String? }
```

**New Kotlin files** under `android/app/src/main/kotlin/com/growspark/nenjam/liveness/`:

| File | Role |
|---|---|
| `LivenessActivity.kt` | A `ComponentActivity` with `setContent { FaceLivenessDetector(...) }` |
| `FaceLivenessChannel.kt` | Registers the channel and launches the activity. Keeps one pending `MethodChannel.Result`; a second concurrent call gets `ERROR` / `ALREADY_RUNNING` |
| `LivenessCredentialsHolder.kt` | In-memory, single-use holder |
| `BackendIssuedCredentialsProvider.kt` | Implements Amplify's `AWSCredentialsProvider<AWSCredentials>` and returns `AWSTemporaryCredentials` from the holder |

Rules for the Kotlin side:
- **Credentials never go in the Intent.** Put them in `LivenessCredentialsHolder` and pass only `sessionId`/`region` as extras. Clear the holder in `onDestroy` and after `onComplete`/`onError`.
- Call `FaceLivenessDetector(sessionId, region, credentialsProvider = ..., disableStartView = false, onComplete = { COMPLETED }, onError = { e -> ERROR + exception type as errorCode })`.
- Map the library's user-cancel exception to `CANCELLED`. Check exception class names against the pinned version.
- Back press counts as `CANCELLED`.
- **Never log** any credential field. Logging `sessionId` is fine.
- The activity is portrait-locked. If the process dies mid-capture, Flutter gets no result; that's fine, the backend expires the attempt.

**Dart side:** `lib/core/services/face_liveness/face_liveness_launcher.dart`
- An abstract `FaceLivenessLauncher` with `Future<LivenessCaptureResult> start(LivenessSessionTicket ticket)`.
- `MethodChannelFaceLivenessLauncher` implements it behind a hand-written `Provider`.
- Guard with `!kIsWeb && defaultTargetPlatform == TargetPlatform.android`. Anywhere else it returns `ERROR` / `UNSUPPORTED_PLATFORM` and the UI hides the entry point.

---

## 6. Flutter work

Follow the repo's real conventions (see `CLAUDE.md`):
- hand-written Riverpod providers; no codegen, freezed, json_serializable or UseCase layer
- hand-written `fromJson`
- `ApiClient` + `ApiEndpoints`
- design tokens
- reuse `core/widgets/**`

### 6.1 Files

**Modify:**

| File | Change |
|---|---|
| `lib/core/network/api_endpoints.dart` | `faceVerification = '/verification/face'`, `faceVerificationSessions = '/verification/face/sessions'`, `faceVerificationComplete = '/verification/face/complete'` |
| `lib/core/router/route_names.dart`, `app_router.dart` | New route `/verification/face` (name `faceVerification`). **Not** a public route |
| `lib/features/verification/presentation/pages/verification_page.dart` | Add a `FaceVerificationCard` **above** `StepVerification`. Not inside it: that widget is also registration step 13, and face verification is deliberately not part of registration |
| `lib/features/profile/presentation/pages/profile_page.dart` (~line 390, "Face Match" tile) | Read `faceVerificationStatusProvider` instead of `draft?.verificationStatus.faceVerified`, which nothing sets. `REVOKED` / loading / error = incomplete; `onTap` → `/verification/face` |
| `lib/main.dart` (auth-transition reset, next to `ref.invalidate(myPhotosProvider)`) | `ref.invalidate(faceVerificationStatusProvider)` in both the sign-out and sign-in branches |
| `lib/l10n/app_en.arb` + `app_ta.arb` | All new strings in both files; get the Tamil copy reviewed |
| Photo manager (`features/profile_photos/...`) | After a successful replace/delete/set-primary, `ref.invalidate(faceVerificationStatusProvider)`, since the backend now reports `REVOKED` |

**Already done:** `lib/core/network/api_exception.dart` (`code`). **No change needed:** the badges on Discover, Nearby, inbox and `ProfileCard` (§4.5), and `profile_draft.dart`'s `faceVerified` field (don't delete it).

**Add** (under `lib/features/verification/`):

| File | Contents |
|---|---|
| `domain/models/face_verification.dart` | `FaceVerificationState`, `LivenessSessionTicket` (**no `toJson`; a `toString` that hides secrets**), `FaceVerificationResult`. Unknown enum strings map to a safe default |
| `domain/repositories/face_verification_repository.dart` | `getState()`, `startSession({required bool consent})`, `complete(attemptId, clientOutcome, clientErrorCode)` |
| `data/repositories/api_face_verification_repository.dart` | Real implementation over `ApiClient` + `unwrapOrThrow` |
| `data/repositories/mock_face_verification_repository.dart` | For building the UI while AWS isn't set up. Same `Mock*`/`Api*`-behind-one-`Provider` pattern the repo already uses |
| `presentation/providers/face_verification_providers.dart` | `faceVerificationRepositoryProvider`, `faceVerificationStatusProvider` (AsyncNotifier + `refresh()`), and a flow controller (`AutoDisposeNotifier`) holding the §6.3 state machine |
| `presentation/pages/face_verification_page.dart` | Intro + consent → running → result |
| `presentation/widgets/face_verification_card.dart` | Verification Center card |

### 6.2 Screens and copy

**1. Intro and consent** (Flutter screen):
- What happens: a short video selfie, checked for liveness and compared with the member's **main profile photo** (show its thumbnail from `myPhotosProvider`).
- **Consent wording** (final text from product/legal; use this meaning):
  > "Your video selfie is sent to Amazon Web Services only to check that you are a real person and that you match your main profile photo. Nenjam does **not** store your selfie video or selfie image — we keep only the result (verified or not)."
- Tips: good light, no mask or sunglasses, face the camera; the main photo should clearly show only you.
- A **photosensitivity warning**: the check flashes coloured lights on the screen.
- A consent checkbox; the CTA stays disabled until it's ticked, and the request sends `consent: true`.

**2. Camera permission:** request through `AppPermissionService` (`NmPermission.camera`) **before** calling `/sessions`, so no paid session is created for someone who then denies the camera. Handle permanently-denied with the existing "open settings" pattern.

**3. Running:** the native screen, then a blocking "Checking…" state while `/complete` runs.

**4. Result:**
- Success: badge + "Done".
- Failure: a message per `reason`, and **Retry** only when `canRetry`, with `attemptsRemainingToday`.
- For `FAILED_MATCH`, `NO_FACE_IN_PHOTO`, `MULTIPLE_FACES_IN_PHOTO`, `UNSUPPORTED_PHOTO` and `PHOTO_CHANGED`, offer "Update main photo".

**Entry-point gating:**
- A real Firebase user is signed in (`authRepositoryProvider.currentAuthUser != null`). Every current login path produces a Firebase session, so there's no separate "local session" case to handle.
- `canStart == true` from `GET /verification/face`, otherwise show the `blockedReason` message.
- Android, not web.

### 6.3 Flow state machine (flow controller)

```
idle → checkingPermission → creatingSession → capturing → completing → verified | failed
                    ↘ permissionDenied        ↘ blocked (409/422/429/503 codes)
```

- `capturing → completing`: call `/complete` on **every** native outcome (COMPLETED, CANCELLED, ERROR) so the backend can close the attempt.
- **Retry `/complete`** with short backoff (e.g. 1s, 2s, 4s) on:
  - `RESULT_NOT_READY`
  - `ATTEMPT_IN_PROGRESS`
  - network failure

  Stop at `expiresAt` plus about 60s. After that, show "We couldn't confirm your result"; a later `GET /verification/face` shows the real state.
- Drop the `LivenessSessionTicket` from memory as soon as `start()` returns.
- **Double-tap protection:** each start can create a **paid** AWS session, and the backend closes any earlier unfinished attempt.
- On `verified`: `ref.invalidate(faceVerificationStatusProvider)` and `ref.invalidate(myProfileProvider)`.

---

## 7. Security checklist (checked in PR review)

- [ ] No AWS credentials in any `.env*`, asset, `BuildConfig`, `SharedPreferences` or `StorageService`
- [ ] Ticket/credential objects have no `toJson` and a secret-hiding `toString`; nothing logs them (Dart or Kotlin)
- [ ] Credentials reach the activity through the in-memory holder, not Intent extras, and are cleared after use
- [ ] "Verified" is shown **only** from a backend response (`/complete` or `GET /verification/face`), never from `onComplete`
- [ ] No confidence or similarity scores shown
- [ ] `LivenessActivity` is `exported="false"`
- [ ] Camera permission is requested before session creation
- [ ] `LoggingInterceptor` is left as is (method + URL only)

---

## 8. Tests

Use `flutter_test` with hand-written fakes and `ProviderScope(overrides: [...])`. No mockito.

- **Models:** `fromJson` for every status, reason and blocked reason; unknown values; `toString` hides secrets.
- **Flow**, with a fake repository and a fake `FaceLivenessLauncher`:
  - happy path
  - cancel → `/complete` still called
  - native ERROR
  - `RESULT_NOT_READY` retry → success
  - `/complete` gives up after the window
  - each 409/422/429/503 `code`
  - permission denied → **no** session created
  - double-tap → one session
- **Page:** at **320–480dp, portrait + landscape, `en` + `ta`, keyboard open**, matching the existing responsive audit suites.
- **Profile tile:** `VERIFIED` → verified; `REVOKED`, loading and error → incomplete.
- **Manual, on real devices** (liveness can't run on an emulator):
  - a low-end API 24–26 device
  - a recent device
  - a **release** build
  - Tamil locale
  - bad lighting
  - backgrounding mid-capture
  - a WebP / group-photo primary photo

Before handing back: `dart format`, `flutter analyze --no-fatal-infos` clean, `flutter test` green.

---

## 9. Out of scope

- iOS
- the registration wizard (step 13 unchanged)
- backend, AWS and IAM setup
- admin review
- document verification

---

## 10. Order of work

1. **Android build changes + spike.** A native `LivenessActivity` opened from a debug button, using a session and credentials from a backend dev once the AWS IAM resources exist. Pasted at runtime, **never committed**. Confirm capture works on a real device in a **release** build, plus the §3 size and alignment checks.
2. **Dart side:** launcher, models, mock repository, flow controller, tests.
3. **UI:** screens, card, route, profile tile, l10n, `main.dart` reset.
4. **Switch mock → API** once the backend team enables the feature on dev. Walk through every §4.4 `code` end to end.
5. **Release-build QA** on real devices (§8).
