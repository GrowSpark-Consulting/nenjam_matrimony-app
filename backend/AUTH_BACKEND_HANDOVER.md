# Firebase Authentication Backend Handover

## Overview

The backend uses **Firebase Authentication as the single identity provider**. Firebase handles all phone/OTP verification; the NestJS backend never sees or validates an OTP — it only ever verifies a **Firebase ID Token** that Flutter obtains after a successful Firebase sign-in.

PostgreSQL (via Prisma) is the single source of truth for application data. Firebase stores no application data (no Firestore, no Firebase user profiles) — it exists purely to authenticate the user and hand the backend a signed token.

**Final authentication flow:**

```
Phone Login (Firebase)
        │
        ▼
Firebase ID Token
        │
        ▼
NestJS verifies token (Firebase Admin SDK)
        │
        ▼
Find/Create User (PostgreSQL)
        │
        ▼
Generate Backend JWT (access + refresh)
        │
        ▼
Return needsEmailVerification
        │
        ▼
Flutter decides navigation (Dashboard vs. Email Verification Screen)
```

The backend never makes a navigation decision — it only returns a boolean flag (`needsEmailVerification`) and lets the client decide what screen to show.

---

## Current Status

✅ Firebase Admin SDK integrated

✅ Firebase ID Token verification implemented

✅ User synchronization with PostgreSQL completed

✅ Backend JWT generation completed

✅ /auth/firebase endpoint implemented

✅ needsEmailVerification implemented

✅ Unit tests passing

⏳ Flutter integration pending

⏳ Firebase Email Linking flow (client side)

⏳ Protected API routes (future phase)

⏳ Refresh token endpoint (future phase)
## Backend Components Implemented

| File | Responsibility |
|---|---|
| `libs/firebase/src/firebase.service.ts` | Initializes the Firebase Admin SDK exactly once (checks `getApps()` before initializing), using ENV-only credentials (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`). Exposes `getAuth()`, `verifyIdToken()`, `createCustomToken()`. |
| `libs/firebase/src/firebase.module.ts` | Global NestJS module exporting `FirebaseService` so it's injectable app-wide. Must be imported into `AppModule` (or any bootstrapped app) to actually be loaded. |
| `apps/api/src/modules/auth/services/firebase-token.service.ts` | Thin wrapper around `FirebaseService.verifyIdToken()`. Returns the decoded Firebase token (`uid`, `email`, `phone_number`, `email_verified`, etc.). |
| `apps/api/src/modules/auth/repositories/auth.repository.ts` | Prisma-only data access for the `User` model: `findByFirebaseUid()`, `create()`, `update()`. No business logic. |
| `apps/api/src/modules/auth/services/auth.service.ts` | Core orchestrator. `findOrCreateUser()` syncs the Prisma user from a decoded Firebase token; `authenticateWithFirebase()` runs the full pipeline (verify → sync → issue JWTs → compute `needsEmailVerification`). |
| `apps/api/src/modules/auth/services/token.service.ts` | Issues backend JWTs via `@nestjs/jwt`. Payload: `{ userId, firebaseUid, phoneNumber, type }` where `type` is `'access'` or `'refresh'`. Access tokens expire in 15m, refresh tokens in 7d. |
| `apps/api/src/modules/auth/controllers/auth.controller.ts` | Exposes `POST /auth/firebase`. Validates the request body and delegates directly to `AuthService.authenticateWithFirebase()` — no business logic in the controller. |
| `apps/api/src/modules/auth/dto/login.dto.ts` | Request DTO: `{ idToken: string }`, validated with `class-validator` (`@IsString`, `@IsNotEmpty`). |
| `apps/api/src/modules/auth/dto/auth-tokens.response.dto.ts` | Response DTO describing the shape returned by `AuthService`: `accessToken`, `refreshToken`, `user`, `needsEmailVerification`. |
| `apps/api/src/modules/auth/auth.module.ts` | Wires up `JwtModule` (secret sourced from `AppConfigService`), registers `AuthController`, and provides `AuthRepository`, `AuthService`, `FirebaseTokenService`, `TokenService`. |
| `apps/api/src/app.module.ts` | Root module — imports `FirebaseModule` and `AuthModule` so the above is actually loaded and the route is live. |
| `libs/database/prisma/schema.prisma` (`User` model) | `firebaseUid` is the permanent identity anchor; `email` is nullable; `emailVerified` boolean added. See [Database Changes](#database-changes). |
| `libs/database/prisma/migrations/20260709130540_email_nullable_and_verified_flag/` | Migration making `email` nullable and adding `email_verified` (default `false`). |

---

## API Endpoint

### `POST /auth/firebase`

The only endpoint the Flutter app needs to call to complete authentication.

**Request body**

```json
{
  "idToken": "eyJhbGciOiJSUzI1NiIsImtpZCI6..."
}
```

- `idToken` — the Firebase ID token obtained on-device after a successful Firebase phone (or email) sign-in. Required, non-empty string.

**Response — `200 OK`**

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "user": {
    "id": "b3f1...",
    "firebaseUid": "aBcD1234...",
    "email": null,
    "emailVerified": false,
    "phone": "+919999999999",
    "role": "USER",
    "status": "PENDING_VERIFICATION",
    "trustScore": 0,
    "createdAt": "2026-07-09T12:00:00.000Z",
    "updatedAt": "2026-07-09T12:00:00.000Z",
    "deletedAt": null
  },
  "needsEmailVerification": true
}
```

| Field | Meaning |
|---|---|
| `accessToken` | Short-lived (15m) backend JWT. Send as `Authorization: Bearer <accessToken>` on subsequent API calls (once auth guards are added in a later phase). |
| `refreshToken` | Longer-lived (7d) backend JWT, used to obtain a new access token when it expires (refresh endpoint is a future phase). |
| `user` | The full PostgreSQL `User` record — the source of truth for application data. |
| `needsEmailVerification` | `true` if the user still needs to link/verify an email. Drives Flutter's post-login navigation — see [needsEmailVerification](#needsemailverification). |

**Validation errors — `400 Bad Request`** if `idToken` is missing or empty.

**Auth failures** — if Firebase rejects the token (expired, malformed, revoked), `FirebaseService.verifyIdToken()` throws and the request fails; no user record is created or modified.

---

## Authentication Flow

Step by step, what happens after Flutter calls `POST /auth/firebase` with a Firebase ID token:

1. **Validation** — `LoginDto` ensures `idToken` is a non-empty string before anything else runs.
2. **Firebase verification** — `AuthController` calls `AuthService.authenticateWithFirebase(idToken)`, which calls `FirebaseTokenService.verifyIdToken(idToken)`. This delegates to `FirebaseService`, which calls the Firebase Admin SDK's `verifyIdToken()`. If the token is invalid/expired, this throws and the flow stops here — no database access happens.
3. **User synchronization** — `AuthService.findOrCreateUser(decodedToken)` looks up the user by `firebaseUid` (the permanent identity):
   - **User exists** → updates `phone` (if the token carries one) and `email`/`emailVerified` (only if the token carries an email — an existing email is never cleared by a token that doesn't have one, e.g. a later phone-only re-login). Returns the updated user.
   - **User does not exist** → creates a new user with `firebaseUid`, `phone`, `email` (nullable), and `emailVerified` from the token. A concurrent double-submission (two requests creating the same `firebaseUid` at once) is handled by catching the unique-constraint violation and re-fetching the winning row — no duplicate users are ever created.
4. **JWT generation** — `TokenService.generateTokenPair(user)` signs an access token and a refresh token from the synced Prisma `User` record (not from Firebase claims).
5. **Response creation** — `AuthService` assembles `{ accessToken, refreshToken, user, needsEmailVerification }` and the controller returns it as-is.

---

## Database Changes

`User` model (`libs/database/prisma/schema.prisma`), migration `20260709130540_email_nullable_and_verified_flag`:

| Field | Type | Change | Why |
|---|---|---|---|
| `firebaseUid` | `String @unique` | Already existed | The **permanent identity anchor**. Every user is looked up by this field first; it never changes for a given Firebase account. |
| `phone` | `String? @unique` | Unchanged | The primary login credential in the phone-first flow. Kept nullable since not every auth provider guarantees a phone number. |
| `email` | `String? @unique` | **Changed from required to nullable** | Phone-only sign-ups have no email at first. Email is added later via Firebase's email-linking flow, so the column must allow `NULL`. |
| `emailVerified` | `Boolean @default(false)` | **New column** | Mirrors Firebase's `email_verified` claim. Only meaningful once `email` is set; drives `needsEmailVerification`. |

No other tables were changed or added.

---

## `needsEmailVerification`

Calculated in `AuthService.authenticateWithFirebase()`:

```ts
needsEmailVerification: !user.email || !user.emailVerified
```

It is `true` when **either**:
- the user has no email on file (`user.email` is `null`), **or**
- the user has an email but it isn't verified (`user.emailVerified` is `false`)

It is `false` only when the user has a verified email.

**This flag is the only signal Flutter should use to decide navigation.** The backend does not — and will not — return a route, screen name, or redirect. Flutter should:
- `needsEmailVerification === true` → navigate to the Email Verification Screen.
- `needsEmailVerification === false` → navigate to the Dashboard.

Once the user later links and verifies an email through Firebase and calls `POST /auth/firebase` again with the updated ID token, `email`/`emailVerified` are updated in PostgreSQL (step 3 above) and the flag flips to `false` on that response.

---

## Responsibilities

**Backend responsibilities:**
- Verify the Firebase ID token (Firebase Admin SDK)
- Find or create the PostgreSQL user, keyed by `firebaseUid`
- Keep `phone` / `email` / `emailVerified` in sync with what Firebase reports
- Generate the backend JWT pair (access + refresh)
- Return `needsEmailVerification`

**Flutter responsibilities:**
- Perform phone authentication with Firebase (including OTP entry — the backend is never involved in this step)
- Obtain the Firebase ID Token after a successful sign-in
- Call `POST /auth/firebase` with that token
- Store the returned `accessToken` / `refreshToken`
- Navigate to Dashboard or Email Verification Screen based **only** on `needsEmailVerification`
- Later, when linking an email: perform Firebase's email verification flow, then call `POST /auth/firebase` again with the refreshed ID token so the backend picks up the new email

---

## Testing Performed

- `pnpm build` — succeeds
- `pnpm exec jest` (full suite) — all suites pass
- Verified via a real application boot (not just mocked unit tests) that dependency injection resolves correctly end-to-end and the following all initialize successfully:
  - PostgreSQL connection (Prisma)
  - Redis connection
  - Elasticsearch connection
  - Firebase Admin SDK initialization (`FIREBASE ADMIN ... Initialized: SUCCESS`)
- Confirmed `POST /auth/firebase` is mapped and reachable (`AuthController {/auth}: Mapped {/auth/firebase, POST} route`) in the real Nest routing table, not just in unit tests

---

## Notes

- **Firebase is the sole source of truth for authentication.** The backend never generates, stores, or validates an OTP.
- OTP delivery and verification are handled entirely by Firebase Authentication on the client side.
- The backend's only job on the auth side is to trust and verify the **Firebase ID Token** it's given — it never talks to Firebase to initiate a sign-in.
- Backend JWTs are independent of Firebase tokens: once issued, the Flutter app authenticates future API calls with the backend's own `accessToken`, not the Firebase ID token.

## Future Work

The following items are intentionally outside this implementation:

- Flutter phone authentication
- Firebase email linking UI
- Refresh token endpoint
- JWT authentication guards
- Protected routes
- Logout
- Token revocation