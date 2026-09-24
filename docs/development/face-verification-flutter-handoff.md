# Nenjam Matrimony — Face Verification Flutter/Android Handoff

**Status:** Backend implemented, tested, and merged to `main`. Deployed to Railway with `FACE_VERIFICATION_ENABLED=false`. AWS IAM configured but not yet exercised with a real Rekognition call. Flutter/Android integration has not started.

---

## What We Changed & Why

This section orients a new reader (or future-you) to what landed in the codebase for this feature, and the reasoning behind it, before diving into the API reference below.

**What was added** (all backend, one commit — `feat: add face verification foundation`, already on `main`):
- A new, self-contained slice of the existing `verification` module: `controllers/face-verification.controller.ts`, `services/face-verification.service.ts`, `repositories/face-verification.repository.ts`, `gateways/{face-liveness.gateway.ts, aws-face-liveness.gateway.ts}`, `domain/{face-verification-state.ts, face-verification-decision.ts, face-verification.constants.ts}`, and `dto/face-verification.dto.ts`. See the file map below for exact locations.
- A Prisma schema extension: new optional/defaulted columns on the existing `FaceVerification` model, plus a brand-new `FaceVerificationAttempt` model for per-attempt history. The migration (`20260921120000_add_face_verification_attempts`) is additive only — nothing was dropped or renamed — and has already been applied to the production Neon database.
- One new method on the existing `S3Service`: `getObjectBytes()` (`libs/storage/src/s3.service.ts`), a read-only, size/format-checked read used to fetch the member's primary photo for CompareFaces. Upload/delete/presign behavior was not touched.
- New `FACE_VERIFICATION_*`/`FACE_LIVENESS_*` config keys in `libs/config/src/{configuration,validation,config.service}.ts`, additive to the existing config pattern — nothing existing was renamed or removed.
- A small wiring change to the shared profile-card query (`apps/api/src/modules/matches/repositories/feed.repository.ts` and `.../mappers/profile-feed.mapper.ts`) so the existing `isVerified` field on every profile card is now backed by real data instead of a hardcoded value.
- On the Flutter side, one small, already-completed, backward-compatible change: `Frontend/lib/core/network/api_exception.dart` gained an optional `code` field, populated from the backend's structured error responses (see §10). This was done in the same historical commit as the backend work, purely so error codes like `NOT_AVAILABLE`/`ATTEMPT_LIMIT`/etc. are parseable — it is *not* part of "the Flutter integration" this document hands off, and nothing else in Flutter was touched.

**Why this exists:** matrimony platforms are a common target for fake/impersonated profiles. Face Verification lets a member prove, with a live camera check plus a match against their own stated profile photo, that the person behind the account is a real, present human who matches their photo — feeding the existing `isVerified` badge that already appears across the app's profile-card surfaces.

**Why the existing document-verification stubs were left alone:** the `verification` module already contained unrelated, still-unimplemented scaffolding for income/asset/Aadhaar/NRI document checks (`services/document-check.service.ts`, `services/verification.service.ts`, `controllers/verification.controller.ts`, etc.). That is a separate, still-empty feature. Face Verification was added as new, parallel files rather than by extending those stubs, precisely so the two efforts don't collide later.

**Why authentication was not touched:** this feature reuses the app's existing `FirebaseAuthGuard`/`@CurrentUser` pattern exactly as every other protected endpoint does. The dummy-OTP mechanism is upstream of this feature (it's how a Firebase session gets minted in the first place) and was correctly treated as out of scope throughout this work.

**Why the feature ships disabled:** `FACE_VERIFICATION_ENABLED=false` because no real AWS Rekognition call has been made yet against the live IAM setup, and because every `/sessions` call is a billed AWS operation. It's meant to be enabled only for a controlled smoke test, then for real use once Flutter integration is ready — see §16.

## DO NOT REIMPLEMENT

The following already exist, are unit-tested, and must not be rebuilt, duplicated, or worked around from Flutter or in a future backend change:

- **The verification decision itself.** `apps/api/src/modules/verification/domain/face-verification-decision.ts` (`evaluateLiveness`/`evaluateMatch`) and its use inside `services/face-verification.service.ts`'s `decide()` method are the *only* place a pass/fail verdict is computed. Do not add any client-side "did it probably work" heuristic.
- **The "is this member currently verified" derivation.** `domain/face-verification-state.ts` (`isFaceVerified`, `faceVerificationDisplayStatus`, `primaryPhotoOf`) is the single source of truth, reused by both `GET /verification/face` and the shared profile-card mapper (`apps/api/src/modules/matches/mappers/profile-feed.mapper.ts`). Don't write a second copy of "is the matched photo still primary" logic anywhere else, including in Flutter.
- **The AWS gateway.** `gateways/aws-face-liveness.gateway.ts` is the only code that calls `CreateFaceLivenessSession`, `GetFaceLivenessSessionResults`, `CompareFaces`, or `AssumeRole`. There is no reason for Flutter (or any other backend module) to call AWS Rekognition/STS directly — every interaction goes through this one gateway, behind the service.
- **STS credential issuance.** `issueClientCredentials()` in the same gateway file is the only place temporary device credentials are minted. Do not attempt to derive, cache, or refresh AWS credentials from within Flutter; request a fresh set from `POST /verification/face/sessions` every time.
- **The Prisma schema/migration.** `libs/database/prisma/schema.prisma`'s `FaceVerification`/`FaceVerificationAttempt` models and the applied migration are final for phase 1. Don't hand-alter the schema or the database to "add" a field this document doesn't mention — extend the existing pattern (a new migration) if a real requirement appears.
- **The S3 read path.** `S3Service.getObjectBytes()` already exists, is format/size-checked, and is the only way the backend reads the primary photo for comparison. Don't introduce a second S3 read path for this feature.
- **Authentication/dummy-OTP.** Explicitly out of scope — see §3. Do not replace, "fix," or add a parallel auth mechanism for this feature specifically.
- **The document-verification stub module** (income/asset/Aadhaar/NRI checks) — unrelated, still unimplemented, and not to be conflated with or extended for face verification.
- **Config plumbing.** `AppConfigService.faceVerification` and the `FACE_VERIFICATION_*`/`FACE_LIVENESS_*` Joi validation already exist in `libs/config/`. Don't add a second, ad hoc way of reading these env vars.

## Backend File & Module Map

Every file that is part of this feature, and what it's responsible for. All paths are relative to `backend/`.

```
apps/api/src/modules/verification/
├── verification.module.ts                     # Wires FaceVerification* into AppModule;
│                                                # the pre-existing document-verification
│                                                # stubs (controllers/verification.controller.ts,
│                                                # services/verification.service.ts, etc.) live
│                                                # in this same module directory but are
│                                                # UNRELATED and still unregistered/empty.
├── controllers/
│   └── face-verification.controller.ts         # GET /verification/face
│                                                #   POST /verification/face/sessions
│                                                #   POST /verification/face/complete
├── dto/
│   └── face-verification.dto.ts                 # Request/response shapes for all 3 routes
├── services/
│   └── face-verification.service.ts              # All business logic: availability gating,
│                                                    # attempt lifecycle, the decide() flow,
│                                                    # error mapping — the file to read first
├── repositories/
│   └── face-verification.repository.ts            # All Prisma access: ownership-scoped
│                                                     # queries, the row-locked attempt
│                                                     # reservation, finalize/transaction logic
├── gateways/
│   ├── face-liveness.gateway.ts                     # The FaceLivenessGateway interface
│   │                                                  # (injection token: FACE_LIVENESS_GATEWAY)
│   └── aws-face-liveness.gateway.ts                   # The real AWS SDK implementation —
│                                                        # the only file that calls Rekognition/STS
└── domain/
    ├── face-verification.constants.ts                 # Timing windows, format allowlist,
    │                                                    # the STS session policy, error codes
    ├── face-verification-decision.ts                    # Pure pass/fail threshold logic
    └── face-verification-state.ts                       # "Is this member currently verified"
                                                            # derivation, shared with the feed mapper

libs/database/prisma/
├── schema.prisma                                # FaceVerification (extended) +
│                                                 # FaceVerificationAttempt (new) models
└── migrations/20260921120000_add_face_verification_attempts/migration.sql

libs/storage/src/s3.service.ts                   # + getObjectBytes() (read-only, additive)
libs/config/src/{configuration,validation,config.service}.ts
                                                  # + FACE_VERIFICATION_*/FACE_LIVENESS_* config

apps/api/src/app.module.ts                       # + VerificationModule import
apps/api/src/modules/matches/
├── repositories/feed.repository.ts               # + faceVerification/photo fields on the
│                                                   #   shared FEED_PROFILE_SELECT
└── mappers/profile-feed.mapper.ts                  # `isVerified` now derived via
                                                       # domain/face-verification-state.ts
```

**Tests** (all under `apps/api/src/modules/verification/tests/`, plus one each in `libs/storage/` and `apps/api/src/modules/matches/tests/`): `face-verification.service.spec.ts`, `face-verification.repository.spec.ts`, `face-verification-domain.spec.ts`, `aws-face-liveness.gateway.spec.ts`, `s3.service.spec.ts`, `profile-feed.mapper.spec.ts` — 133 tests across these 6 files as of the last full run.

**On the Flutter side**, the only existing file touched is `Frontend/lib/core/network/api_exception.dart` (the `code` field — see "What We Changed & Why" above). Everything else described in this document, from §7 onward, is new work you will create.

---

## 1. Purpose

Face Verification proves two things about a member, in order:

1. **Liveness** — a real, live person is in front of the camera right now (AWS Rekognition Face Liveness), not a photo, video replay, or mask.
2. **Match** — that live person is the same person shown in the member's **current primary profile photo** (AWS Rekognition CompareFaces).

Only when both pass does the backend mark the member's profile as face-verified. The result is a badge (`isVerified`) that already renders on every existing profile card (Discover, Search, Nearby, profile views, shortlist, interests, chat, blocks) — nothing new needs to be built for display once the backend says "verified."

**The backend decides, not the device.** The Android app runs the camera/liveness capture UI and nothing else. It never computes, stores, or reports a pass/fail verdict of its own; every verdict is fetched from AWS by the backend and persisted by the backend.

**No permanent AWS credentials ever reach the app.** The backend holds one permanent AWS identity (`nenjam-face-verification-backend`) that it uses to call Rekognition and to assume a second, narrowly-scoped IAM role. What it hands to Flutter is a **short-lived (default 15-minute) STS session** — an access key, secret key, and session token that expire and are useless afterward. These credentials only permit `rekognition:StartFaceLivenessSession` — nothing else.

---

## 2. Current Backend Status

**Implemented, committed, and unit-tested (81 backend test suites / 1010 tests passing as of this review):**
- All three REST endpoints (`GET /verification/face`, `POST /verification/face/sessions`, `POST /verification/face/complete`)
- AWS Rekognition Face Liveness session creation
- STS `AssumeRole` for short-lived device credentials
- Retrieval of the AWS liveness result
- Retrieval and validation of the member's current primary profile photo from S3
- CompareFaces execution and server-side threshold decision
- Attempt history, current-verification-state persistence, and "verification tied to the current primary photo" logic
- Per-member and global daily attempt caps, ownership checks, idempotent completion
- Prisma schema/migration (already applied to the production Neon database)
- AWS IAM (backend identity + `nenjam-face-liveness-client` role) — configured, not yet exercised with a real call

**Not yet done:**
- **No real Rekognition call has been made.** Every AWS interaction is covered by unit tests against a mocked gateway. The first real `CreateFaceLivenessSession`/`CompareFaces` call has not happened.
- **`FACE_VERIFICATION_ENABLED` is `false` in production.** With it `false`, the two state-changing endpoints (`POST /sessions`, `POST /complete`) return `503` with `code: "NOT_AVAILABLE"`. `GET /verification/face` does **not** throw — it returns `200` with `canStart: false, blockedReason: "NOT_AVAILABLE"` (see §5 and the corrected note in §16). It will stay `false` until an end-to-end test (including your Android integration) has been run in a controlled way.
- **No Flutter/Android code exists for this feature.** That is your work.

---

## 3. Authentication

**The existing authentication/dummy OTP system is intentionally unchanged and is OUT OF SCOPE for this feature.**

Do not replace, modify, or work around the app's current authentication. The verification API expects exactly the same authenticated-user mechanism every other protected endpoint in this app already uses: a `Bearer <Firebase ID token>` header, handled by the existing `AuthInterceptor`/`ApiClient` on the Flutter side and `FirebaseAuthGuard` on the backend. If your existing authenticated `ApiClient` can already call, say, `GET /profiles/me`, it can call these three endpoints with no additional auth work.

---

## 4. API Base URL

The app's existing base URL, already defined in the repo (`Frontend/lib/core/constants/app_constants.dart`):

```
https://nenjammatrimony-app-production.up.railway.app
```

This is `AppConstants.apiBaseUrl`'s compile-time default (overridable via `--dart-define=API_BASE_URL=...`, per the existing pattern). No new URL or environment needs to be introduced for this feature.

---

## 5. `GET /verification/face`

**Purpose:** the caller's current face-verification state — call this to decide what the UI should show (a "Verify" prompt, a "Verified" badge, or a reason it can't start).

**Auth:** required (`FirebaseAuthGuard`).

**Request:** no body, no query parameters.

**Response** (`FaceVerificationStateDto`, from `dto/face-verification.dto.ts`):

```json
{
  "status": "UNVERIFIED",
  "verifiedAt": null,
  "canStart": true,
  "blockedReason": null,
  "attemptsRemainingToday": 3,
  "retryAfter": null
}
```

| Field | Type | Meaning |
|---|---|---|
| `status` | `"UNVERIFIED" \| "VERIFIED" \| "REVOKED"` | The derived, current-moment state. `VERIFIED` only holds while the photo that was matched is *still* the member's current primary photo (see §9). `REVOKED` means it *was* verified but no longer is, because the matched photo changed. |
| `verifiedAt` | ISO-8601 string or `null` | Set only when `status === "VERIFIED"`. |
| `canStart` | boolean | Whether `POST /verification/face/sessions` would currently succeed. |
| `blockedReason` | string or `null` | Present when `canStart` is `false`. One of: `"NOT_AVAILABLE"`, `"ALREADY_VERIFIED"`, `"NO_PRIMARY_PHOTO"`, `"UNSUPPORTED_PHOTO"`, `"ATTEMPT_LIMIT"`. |
| `attemptsRemainingToday` | number | Remaining attempts in the current rolling 24-hour window. |
| `retryAfter` | ISO-8601 string or `null` | Present only when `blockedReason === "ATTEMPT_LIMIT"`; the instant the oldest counted attempt ages out of the window. |

**Errors:** none specific to this endpoint beyond the standard `401` (missing/invalid Firebase token) — it does not throw when the feature is disabled; instead it returns `canStart: false, blockedReason: "NOT_AVAILABLE"`.

---

## 6. `POST /verification/face/sessions`

**Purpose:** starts one verification attempt. Creates a real AWS Face Liveness session and mints the temporary credentials Android needs to run it.

**Auth:** required.

**Request body** (`StartFaceSessionDto`):

```json
{ "consent": true }
```

- `consent` is **required** and must be exactly `true` (boolean). The backend rejects `false`, missing, or non-boolean values with `400`.
- Only call this after the user has explicitly agreed on-screen — this call is what the backend treats as the consent record for the attempt (`consentAt`).

**Response, `201 Created`** (`StartFaceSessionResponseDto`):

```json
{
  "attemptId": "b3f1...-uuid",
  "sessionId": "3d9a...-uuid",
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

| Field | Meaning |
|---|---|
| `attemptId` | The backend's internal attempt id. Send this back unchanged to `/complete`. |
| `sessionId` | The AWS Rekognition Face Liveness session id, for the native/Amplify liveness UI. |
| `region` | The AWS region the liveness UI must stream to (`ap-south-1` in the current configuration). |
| `expiresAt` | **The AWS liveness session itself expires 3 minutes after creation.** After this instant, `/complete` can only report the attempt as expired — see §9. |
| `credentials.*` | STS temporary credentials (see below). |

**These are scoped, temporary AWS credentials — NOT permanent AWS credentials.** They are produced by an `AssumeRole` call the backend makes against a dedicated, narrowly-permissioned IAM role (`nenjam-face-liveness-client`), and by default expire in **900 seconds (15 minutes)**. The permitted action is exactly `rekognition:StartFaceLivenessSession` — nothing else. They cannot read S3, list anything, or call any other Rekognition operation.

**How Flutter should use them:** hand them to the native Android liveness UI's credentials provider for the duration of one liveness session, and nothing else.

**Flutter must never:**
- persist these credentials to disk, `SharedPreferences`, or any local storage;
- log them (not even at debug level);
- reuse them beyond this one liveness attempt;
- send them anywhere except the AWS liveness SDK component itself.

Treat them as sensitive, single-use, short-lived data that lives in memory only for the duration of the capture.

**Errors:**

| HTTP | `code` | Meaning |
|---|---|---|
| `503` | `NOT_AVAILABLE` | Feature disabled or misconfigured. |
| `409` | `ALREADY_VERIFIED` | Already verified against the current primary photo. |
| `422` | `NO_PRIMARY_PHOTO` | Member has no primary profile photo set. |
| `422` | `UNSUPPORTED_PHOTO` | Primary photo isn't a JPEG/PNG under 5 MB (checked on real bytes, not the file extension). |
| `429` | `ATTEMPT_LIMIT` | Per-member or global daily cap reached (`retryAfter` included in the error body when it's the per-member cap). |
| `503` | `PROVIDER_UNAVAILABLE` | AWS itself failed to create the session or issue credentials. |
| `400` | *(none)* | `consent` was not `true`, or the body was otherwise invalid. |
| `401` | *(none)* | Missing/invalid Firebase token. |

---

## 7. AWS Face Liveness Flow

1. Flutter asks the backend for a verification session (`POST /verification/face/sessions`).
2. Backend creates the AWS Rekognition Face Liveness session (`CreateFaceLivenessSession`).
3. Backend assumes the `nenjam-face-liveness-client` role via STS and returns the resulting temporary credentials alongside the session id and region.
4. Flutter invokes the AWS/Amplify Face Liveness UI using those temporary credentials, the `sessionId`, and the `region`.
   *(Flutter implementation detail — verify against the current Android/Flutter AWS SDK documentation. This repository contains no existing Face Liveness UI code or dependency to reference.)*
5. Flutter waits for the liveness flow to finish (however the chosen SDK reports completion/cancellation/error).
6. Flutter calls `POST /verification/face/complete` with the `attemptId`, as soon as possible — see §9 for the 3-minute window.
7. Backend retrieves the authoritative liveness result from AWS (`GetFaceLivenessSessionResults`).
8. Backend retrieves the member's current primary profile photo from private S3.
9. Backend performs `CompareFaces` between the AWS-provided liveness reference image and that photo.
10. Backend applies its configured thresholds and decides verification — server-side, final.
11. Flutter displays the result returned by `/complete`. It does not compute or infer a result of its own.

---

## 8. `POST /verification/face/complete`

**Purpose:** tells the backend the device-side capture has finished (or failed/was cancelled), and asks the backend to fetch the real AWS result and decide.

**Auth:** required.

**Request body** (`CompleteFaceSessionDto`):

```json
{
  "attemptId": "b3f1...-uuid",
  "clientOutcome": "COMPLETED",
  "clientErrorCode": "CAMERA_PERMISSION_DENIED"
}
```

| Field | Required | Notes |
|---|---|---|
| `attemptId` | yes | Must be a UUID; must be an attempt owned by the caller (any other value, or another member's attempt id, returns `404`). |
| `clientOutcome` | no | One of `"COMPLETED"`, `"CANCELLED"`, `"ERROR"`. |
| `clientErrorCode` | no | Free-form string (letters/digits/`_`/`.`/`:`/`-` only, max 100 chars), e.g. what local SDK error occurred. |

**What the backend trusts vs. ignores — this is the single most important contract in this document:**
- `clientOutcome`/`clientErrorCode` are stored for audit only.
- They are used **only** to close an attempt that AWS itself still reports as unfinished (e.g. the device cancelled before AWS ever got a result) — never to grant a pass.
- **The backend never marks a member verified because the client said so.** Verification is decided exclusively from what `GetFaceLivenessSessionResults` and `CompareFaces` return, evaluated against the server-side thresholds.

**Response, `200 OK`** (`CompleteFaceSessionResponseDto`):

```json
{
  "attemptId": "b3f1...-uuid",
  "status": "VERIFIED",
  "reason": null,
  "canRetry": false,
  "attemptsRemainingToday": 2
}
```

| Field | Meaning |
|---|---|
| `status` | `"VERIFIED"` or `"FAILED"` — the only two possible values. |
| `reason` | `null` on success. On failure, one of: `FAILED_LIVENESS`, `FAILED_MATCH`, `NO_FACE_IN_PHOTO`, `MULTIPLE_FACES_IN_PHOTO`, `UNSUPPORTED_PHOTO`, `NO_REFERENCE_IMAGE`, `PHOTO_CHANGED`, `EXPIRED`, `CANCELLED`, `ERROR`. |
| `canRetry` | Whether the member has attempts remaining today. |
| `attemptsRemainingToday` | Remaining attempts in the rolling 24h window, after this one. |

**No confidence score, similarity score, or any other AWS metric is ever returned.** This is deliberate (see §11) — do not add UI that expects a numeric score.

**Idempotent:** calling `/complete` again with the same `attemptId` after it's already been decided returns the same stored result, at no additional AWS cost. Safe to retry.

**Errors:**

| HTTP | `code` | Meaning |
|---|---|---|
| `503` | `NOT_AVAILABLE` | Feature disabled. |
| `404` | `ATTEMPT_NOT_FOUND` | Unknown attempt, or belongs to a different member (same response either way). |
| `409` | `ATTEMPT_IN_PROGRESS` | Another `/complete` call for this attempt is currently being processed. |
| `409` | `RESULT_NOT_READY` | AWS hasn't finished processing the liveness session yet. |
| `401` | *(none)* | Missing/invalid Firebase token. |

---

## 9. Verification Rules

All values below are read directly from `backend/libs/config/src/configuration.ts`/`validation.ts` and `backend/apps/api/src/modules/verification/domain/face-verification.constants.ts`; **current defaults**, all configurable via environment variables without a code change:

| Rule | Current default | Source |
|---|---|---|
| Liveness confidence threshold | **90** (0–100 scale) | `FACE_LIVENESS_MIN_CONFIDENCE` |
| Face-match similarity threshold | **90** (0–100 scale) | `FACE_MATCH_MIN_SIMILARITY` |
| Primary photo required | Yes — no primary photo → `NO_PRIMARY_PHOTO`, blocks starting | code |
| Supported image formats | **JPEG and PNG only**, detected from the file's real bytes, not its extension or declared content-type | `COMPARE_FACES_FORMATS` |
| Image size limit | **5 MB** | `COMPARE_FACES_MAX_BYTES` |
| Faces detected in the profile photo | Must be **exactly 1** — zero → `NO_FACE_IN_PHOTO`; more than one → `MULTIPLE_FACES_IN_PHOTO` | code |
| Per-member attempt limit | **3 per rolling 24 hours** | `FACE_VERIFICATION_MAX_ATTEMPTS_PER_DAY` |
| Global daily cap | **500 per UTC day, across all members** | `FACE_VERIFICATION_GLOBAL_DAILY_CAP` |
| AWS liveness session lifetime | **3 minutes** from creation — call `/complete` promptly | `LIVENESS_SESSION_LIFETIME_MS` |
| Device credential lifetime | **900 seconds (15 minutes)** by default | `FACE_LIVENESS_CREDENTIALS_TTL_SECONDS` |

**Current-primary-photo matching behavior:** an attempt is pinned, at the moment it's started, to the exact primary photo (its id *and* its stored file) that existed then. At completion, the backend re-checks that the member's primary photo is still that same photo (same id, same underlying file) before running CompareFaces. If it isn't, the attempt fails with `reason: "PHOTO_CHANGED"` — the member must restart.

**What happens when the primary photo changes after successful verification:** the "verified" badge is not a stored flag that just sits there — it's recomputed every time it's read, from whether the currently-matched photo is still the current primary photo. So:
- **Photo replaced** (same slot, new image uploaded) → badge disappears immediately; `GET /verification/face` reports `status: "REVOKED"`.
- **Photo deleted** → same result; badge disappears.
- **A different existing photo is made primary** → same result; badge disappears.

In every case, `canStart` becomes `true` again and the member can re-verify against their new primary photo. No backend or database change is needed on your side for this — it's automatic.

---

## 10. Error Handling

| Backend condition | Expected backend response/code | Flutter handling |
|---|---|---|
| Feature disabled/misconfigured | `503`, `code: NOT_AVAILABLE` | Hide or disable the verification entry point; show "not available right now." |
| Already verified | `409`, `code: ALREADY_VERIFIED` (on start) | Refresh state via `GET`; show the verified badge instead. |
| No primary photo | `422`, `code: NO_PRIMARY_PHOTO` | Prompt the member to set a primary profile photo first; deep-link to the photo manager. |
| Unsupported/oversized primary photo | `422`, `code: UNSUPPORTED_PHOTO` | Prompt the member to update their main photo (JPEG/PNG, under 5 MB). |
| Per-member or global attempt cap reached | `429`, `code: ATTEMPT_LIMIT` (`retryAfter` may be present) | Show a "try again later" message; use `retryAfter` if present, otherwise a generic message. |
| AWS session/credential creation failed | `503`, `code: PROVIDER_UNAVAILABLE` | Generic "temporarily unavailable, try again" message. |
| Unknown or not-your attempt | `404`, `code: ATTEMPT_NOT_FOUND` | Treat as a dead attempt; restart the flow from the beginning. |
| Concurrent `/complete` in flight | `409`, `code: ATTEMPT_IN_PROGRESS` | Wait briefly and retry `/complete`. |
| AWS liveness result not ready yet | `409`, `code: RESULT_NOT_READY` | Retry `/complete` with a short backoff (e.g. a few seconds), until the 3-minute session window closes. |
| Liveness check failed | `200`, `status: FAILED`, `reason: FAILED_LIVENESS` | Show a retry prompt (if `canRetry`), with liveness tips (lighting, face fully in frame). |
| Face doesn't match primary photo | `200`, `status: FAILED`, `reason: FAILED_MATCH` | Suggest updating the primary photo, or retry. |
| No face detected in primary photo | `200`, `status: FAILED`, `reason: NO_FACE_IN_PHOTO` | Prompt to update the primary photo. |
| More than one face in primary photo | `200`, `status: FAILED`, `reason: MULTIPLE_FACES_IN_PHOTO` | Prompt to use a solo photo as primary. |
| No usable reference image from AWS | `200`, `status: FAILED`, `reason: NO_REFERENCE_IMAGE` | Suggest retry (usually a capture-quality issue). |
| Primary photo changed mid-attempt | `200`, `status: FAILED`, `reason: PHOTO_CHANGED` | Explain the photo changed; restart the flow. |
| Session expired (>3 min without completion) | `200`, `status: FAILED`, `reason: EXPIRED` | "Session expired, please try again"; restart from `POST /sessions`. |
| Device/user cancelled | `200`, `status: FAILED`, `reason: CANCELLED` | No error UI needed — the member chose to stop. |
| Unexpected backend/AWS failure | `200`, `status: FAILED`, `reason: ERROR` | Generic failure message with retry, if `canRetry`. |
| Missing/invalid auth token | `401` | Handled by the app's existing auth-interceptor flow — no feature-specific handling needed. |

---

## 11. Security Requirements for Flutter

- **Never hardcode any permanent AWS credential** (access key, secret key) anywhere in the app.
- **Never store AWS secret access keys** — including the temporary ones — in `SharedPreferences`, files, or any persistent storage. Keep them in memory only, for the duration of one liveness attempt.
- **Never send the user's primary photo to Flutter for local matching.** The backend already has it (via S3) and performs the comparison itself; there is no endpoint that returns the raw photo bytes for this purpose, and none should be requested.
- **Never decide verification locally.** There is no client-side pass/fail logic to write. The only source of truth is the `status`/`reason` fields in the `/complete` response.
- **Never treat `clientOutcome` as proof of anything.** It's an audit field the backend records but does not trust (see §8).
- **Never expose backend secrets** — none are sent to the client in the first place, so this is mostly about not introducing new ones (e.g. don't add API keys of your own).
- **Do not attempt to bypass the backend's verification decision** with a client-only "demo" or "mock success" path in production code.
- **Use HTTPS** — the existing `ApiClient`/base URL already enforces this; do not add an HTTP fallback.
- **Handle temporary credential expiration.** The credentials expire (`credentials.expiration`, default ~15 minutes) and the AWS session itself expires after 3 minutes (`expiresAt`) — well before the credential TTL. Design the UI so a stalled flow fails cleanly (see `EXPIRED` in §10) rather than retrying with dead credentials.
- **Don't log temporary AWS credentials** — not in crash reports, not in debug logs, not in analytics events.

---

## 12. Android/Flutter Integration Notes

From the backend contract alone, Flutter/Android needs to:

1. Call `POST /verification/face/sessions` and receive `sessionId`, `region`, and `credentials`.
2. Pass those three pieces of information into whatever AWS Face Liveness UI component is chosen for Android.
   *(Flutter implementation detail — verify against the current Android/Flutter AWS SDK documentation. No such dependency, package, or native bridge exists yet in this repository — this is new integration work.)*
3. Obtain a completion signal from that UI component (success, user-cancelled, or error), and translate it into the optional `clientOutcome`/`clientErrorCode` fields for `/complete` — again, the exact shape of that native completion callback is a Flutter/Android SDK detail to be confirmed against current AWS documentation, not something this backend prescribes.
4. Call `POST /verification/face/complete` with the `attemptId` and get the backend's decision back.

This document does not name a specific Flutter package, native SDK class, or method signature for step 2/3, because none currently exists in this repository — do not invent one.

---

## One Explicit End-to-End Flutter Implementation Sequence

§7, §12, §13, and §18 each describe part of this feature from a different angle (the AWS flow, the integration contract, the UI, the checklist). This section is the single, linear sequence that ties them together — follow it top to bottom for one verification attempt. Each step links back to the section with full field-level detail.

1. **Check eligibility.** Call `GET /verification/face` (§5). Read `canStart`/`blockedReason`/`status` to decide what to show: an entry point to start, an already-verified state, or a reason it's blocked (no primary photo, unsupported photo, attempt limit, or the feature being unavailable — see the reconciled behavior in §16).
2. **Get explicit consent.** Show the member what's about to happen (§13's Consent step) before calling anything else. Do not call `/sessions` on screen load or implicitly.
3. **Start the session.** Call `POST /verification/face/sessions` with `{ "consent": true }` (§6). On success, you receive `attemptId`, `sessionId`, `region`, `expiresAt`, and `credentials` (a short-lived STS access key/secret/session token). On failure, map the error per §10's table.
4. **Hand credentials to the native liveness UI, in memory only.** Pass `sessionId`, `region`, and `credentials` into the chosen AWS Face Liveness Android component (§12 — implementation detail not prescribed here; verify against current AWS/Amplify documentation). Never persist or log the credentials (§11).
5. **Run the capture and wait for a native completion signal.** The component will report something like success, user-cancellation, or an error — the exact shape is SDK-specific (§12).
6. **Call `POST /verification/face/complete` immediately.** Pass `attemptId`, and optionally `clientOutcome`/`clientErrorCode` translated from the native signal (§8). Do this as soon as the native UI finishes — the AWS liveness session itself dies 3 minutes after creation (`expiresAt` from step 3; see §9).
7. **Handle the response.**
   - If AWS hasn't finished processing yet, the backend answers `409 RESULT_NOT_READY` (§10) — wait briefly and call step 6 again. This is normal, not an error state to surface to the member.
   - Otherwise you get a final `{ status, reason, canRetry, attemptsRemainingToday }` (§8). This is the backend's authoritative decision — nothing computed on-device factors into it.
8. **Display the result** per §13's Verification Result states: verified, retryable failure (with the `reason`-specific message from §10), non-retryable (limit reached), expired, or cancelled.
9. **On success**, refresh whatever screen shows the member's own profile/badge — the `isVerified` field on existing profile-card endpoints will now reflect it automatically (no separate "mark verified" call exists or is needed).
10. **If the member's primary photo later changes**, no action is required from Flutter — a future `GET /verification/face` call will report `status: "REVOKED"` and `canStart: true` on its own (§9). Just make sure the profile/verification screen re-fetches state rather than caching it indefinitely.

Use §18's checklist to track implementation progress against this sequence, and §15 for what to test once it's built.

---

## 13. Suggested UI Flow

```
Profile → Verify Profile → Consent → Liveness → Processing → Verification Result
```

- **Profile → Verify Profile:** entry point, gated on `GET /verification/face`'s `canStart`/`blockedReason`. If `status === "VERIFIED"`, show the verified state instead of an entry point to start.
- **Consent:** explain what's about to happen (a short liveness check, compared with the member's main photo); require an explicit affirmative action before calling `/sessions`.
- **Liveness:** the native AWS liveness capture UI runs.
- **Processing:** a loading state while `/complete` is called (and possibly retried per §10's `RESULT_NOT_READY` handling).
- **Verification Result:**
  - **Success** (`status: "VERIFIED"`) → show the verified badge/confirmation.
  - **Retry-able failure** (`status: "FAILED"`, `canRetry: true`) → offer to try again, with a reason-appropriate message from §10.
  - **Non-retryable failure** (`canRetry: false`, i.e. attempts exhausted) → show the cap message; no retry button.
  - **Expired session** (`reason: "EXPIRED"`) → explain the session timed out; restart from Consent.
  - **Already verified** (discovered via `GET`, e.g. on screen re-entry) → skip straight to the verified state.

---

## 14. Backend vs Flutter Responsibilities

| Responsibility | Backend | Flutter |
|---|---|---|
| Create liveness session | ✓ | |
| Issue scoped temporary credentials | ✓ | |
| Run liveness UI | | ✓ |
| Retrieve authoritative liveness result | ✓ | |
| Retrieve primary photo | ✓ | |
| Face comparison | ✓ | |
| Final verification decision | ✓ | |
| Enforce attempt/global limits | ✓ | |
| Display camera/liveness UI | | ✓ |
| Display result | | ✓ |
| Request camera permission | | ✓ |
| Handle credential expiration in-flight | | ✓ (backend enforces it server-side; client should design UX around it) |

---

## 15. Testing Checklist

### Backend tests already completed

Verified in this review (81 backend test suites / 1010 tests passing, including 11 suites / 133 tests specific to face verification):
- Feature-disabled gating (no AWS call made when `FACE_VERIFICATION_ENABLED=false` or AWS misconfigured)
- Session creation: attempt/session/credential creation, and that the response never contains the permanent backend AWS key
- Already-verified / no-primary-photo / unsupported-photo / oversized-photo rejection before any paid AWS call
- Per-member daily cap and global daily cap enforcement, including the retry-after value
- Ownership: one member cannot read or complete another member's attempt
- Idempotent completion (repeated `/complete` calls return the same stored result, no duplicate AWS calls)
- Liveness failure, low-confidence rejection, missing reference image
- Primary photo changed / replaced / deleted between session start and completion
- No-face / multiple-faces / below-threshold-similarity outcomes
- Session expiry and AWS-reported "session not found" handling
- Concurrent-completion race handling
- Unexpected AWS/DB failures recorded as a clean `ERROR` outcome rather than crashing
- The face-verification badge (`isVerified`) deriving correctly across the shared profile-card query used by Discover/Search/Nearby/etc.

**Not tested:** any real call to AWS Rekognition or STS. Every AWS interaction above is verified against a test double, not a live AWS response.

### Flutter integration tests still required

None of the following have been performed and should not be assumed to work until tested:

- Session creation end-to-end from the Flutter app
- Successful liveness capture (real AWS `SUCCEEDED` result)
- Liveness failure (real AWS `FAILED` result)
- User cancellation mid-capture
- Session timeout/expiry (letting the 3-minute window lapse)
- No-face-in-photo case with a real photo
- Face-mismatch case with a real, different face
- Successful face match end-to-end (real `VERIFIED` result)
- Primary photo changed by the member during an in-flight attempt
- Already-verified member re-opening the verification screen
- Retry behavior after a failure, and behavior once the daily attempt limit is hit
- Network interruption during session creation or completion
- Credential/session expiration handled gracefully mid-flow
- Real device testing (liveness capture cannot be validated on an emulator)

---

## 16. Production Safety

`FACE_VERIFICATION_ENABLED=false` in production is **currently intentional**, not an oversight. With it `false`, no AWS cost is incurred, regardless of what else is configured.

**Correction / clarification (verified directly against `face-verification.service.ts`):** the three endpoints do not all behave the same way when disabled.
- `POST /verification/face/sessions` and `POST /verification/face/complete` both call `assertAvailable()` internally, which **throws `503`, `code: "NOT_AVAILABLE"`**, whenever the feature is off (or AWS/S3 aren't fully configured).
- `GET /verification/face` calls the non-throwing `isAvailable()` check instead. It **always returns `200`**, even when disabled — with `canStart: false, blockedReason: "NOT_AVAILABLE"`. This is deliberate: the status endpoint must always be safely pollable to drive the UI (e.g. "hide the Verify button"), not treated as an error state. See §5 for the exact response shape.

Flutter should treat `GET`'s `200` + `blockedReason: "NOT_AVAILABLE"` and the two `POST` endpoints' `503` as the *same underlying condition* (feature unavailable) surfaced two different ways — don't build UI logic that only checks for one or the other.

**Do not enable it in production without a plan.** It should be switched on only when:
1. The Android/Flutter integration described in this document is implemented and has been tested against a real (non-production, or tightly controlled) environment first.
2. A controlled end-to-end test has confirmed the full flow — real liveness capture through to a real backend decision — works as expected.

Enabling the flag makes every subsequent `/sessions` call a real, billed AWS Rekognition Face Liveness session (plus CompareFaces on completion). Do not flip it on as a way to "just see if it works" against production.

---

## 17. Known Limitations / Future Work

Only what the code and this review actually support:

- **No AWS smoke test has been performed.** The very first real `CreateFaceLivenessSession`/`CompareFaces` call to AWS has not happened; behavior against real AWS responses is unverified.
- **No reference image or liveness video is stored anywhere** (S3 or otherwise) in the current implementation — by design, not as a gap. If a future requirement needs to retain evidence (e.g. for dispute review), that's new work, not a bug.
- **CompareFaces score/similarity is never surfaced to any client** — by design, to avoid helping anyone tune a spoof attempt.
- **The face-verification badge is derived, not cached** — every read re-checks the current primary photo. There is no manual "revoke" admin action implemented; revocation only happens automatically via photo changes.
- **iOS is explicitly out of scope** for this feature (Android-only), per the project's earlier architecture decision.
- **No Flutter package or native bridge exists yet** for the liveness capture UI — this handoff describes the backend contract only.

---

## 18. Final Integration Checklist

- [ ] Confirm the existing authenticated `ApiClient` can reach `GET /verification/face` on a non-production/test environment where `FACE_VERIFICATION_ENABLED=true`
- [ ] Implement the "Verify Profile" entry point gated on `canStart`/`blockedReason`
- [ ] Implement the consent screen and call `POST /verification/face/sessions` only after explicit consent
- [ ] Confirm/choose the Android Face Liveness SDK component (verify against current AWS documentation — not prescribed by this backend)
- [ ] Wire the temporary credentials + `sessionId` + `region` into that component, in memory only
- [ ] Handle the native completion callback (success/cancel/error) and map it to `clientOutcome`/`clientErrorCode`
- [ ] Call `POST /verification/face/complete` and handle every `status`/`reason` combination from §10
- [ ] Implement retry with backoff for `RESULT_NOT_READY` (409)
- [ ] Implement the full result UI: verified, retryable failure, non-retryable (limit reached), expired, cancelled
- [ ] Verify the credential/session expiration UX (session dies at `expiresAt`, well before credential TTL)
- [ ] Confirm no credential, secret, or score value is ever logged
- [ ] Run through the full Flutter integration test list in §15 on a real Android device, against a controlled (non-production) backend with the flag enabled
- [ ] Only after all of the above: discuss enabling `FACE_VERIFICATION_ENABLED` in production with the backend owner




