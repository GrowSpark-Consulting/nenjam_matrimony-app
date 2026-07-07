---
name: auth-architecture
description: "Final Nenjam Matrimony authentication architecture — Firebase auth-only, no Firestore, JWT-ready for a future Node.js + PostgreSQL backend"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2b528d01-d7fd-49a8-a47b-62e178c29b30
---

# Nenjam Matrimony Authentication Architecture

**Last Updated:** 2026-07-07

Everything auth lives in `Frontend/lib/features/authentication`. Firebase is the
**identity provider only**. This doc is enough to understand the whole auth
system in ~10 minutes.

---

## 1. Final Architecture Decision

```
Flutter App
    ↓
Firebase Authentication          ← identity (email/password + phone)
    ↓
Firebase ID Token (JWT)          ← currentUser.getIdToken()
    ↓
Node.js Backend (future)         ← verifies JWT with Firebase Admin SDK
    ↓
PostgreSQL Database (future)     ← single source of truth for business data
```

**Firebase = authentication provider only.**

- ❌ NO Cloud Firestore
- ❌ NO Realtime Database
- ❌ NO Firebase user collections

**Why:** Firebase manages *identity* (who the user is, credentials, verified
email/phone). **PostgreSQL** will manage all *business data* (profiles, the
12-step registration, photos, preferences, matches, subscriptions, chat). This
avoids two competing user stores — PostgreSQL becomes the single source of
truth, reached through the backend using the Firebase JWT as proof of identity.

---

## 2. Current Auth Features Status

### ✅ Username collection
- Collected during signup (form field, validated: 3–20 chars, starts with a
  letter, letters/numbers/underscore).
- Stored **temporarily** on the Firebase user via `displayName`
  (`updateDisplayName`) plus in signup controller state.
- Future storage: PostgreSQL `users` table via `POST /api/auth/register`.

### ✅ Email Signup
- Firebase: `createUserWithEmailAndPassword()`.
- Email validation + strong-password validation (min 8, upper, lower, number,
  symbol) in `core/utils/validators.dart`.
- Firebase account creation + all errors mapped to friendly copy.

### ✅ Email Verification
- `sendEmailVerification()`, `currentUser.reload()`, `emailVerified` check.
- Verification **link** (not an email OTP), resend button, and a refresh/poll
  that re-checks status. Screen: `email_verify_screen.dart`.

### ✅ Login
- Firebase: `signInWithEmailAndPassword()`.
- Checks auth state + verification status, routes to the outstanding step or
  Home. Also supports phone-OTP login (`login_otp_screen.dart`).

### ✅ Phone Authentication
- Firebase: `verifyPhoneNumber()` (real SMS OTP).
- Implemented: send OTP, verify OTP, manual OTP entry, Android auto-verification,
  resend OTP (60s countdown), timeout handling, invalid-OTP handling.
- The phone credential is **linked** to the Firebase account during signup.
- `phoneVerified` is derived from `currentUser.phoneNumber != null` — **no
  database required.**
- The in-flight phone is briefly stashed in SharedPreferences (local only) so a
  cold start mid-signup can still send the OTP; cleared after verify.

### ✅ Forgot Password
- Firebase: `sendPasswordResetEmail()`.
- Forgot-password screen, email validation, reset email, error handling.
- **Account-enumeration safe:** `user-not-found` is surfaced as success, so the
  UI never reveals whether an address is registered.

### ✅ Session Restore
- Firebase: `authStateChanges()`.
```
App Start
    ↓
Check Firebase session
    ↓
No user → Login / Auth selection
    ↓
Existing user → Check verification (emailVerified + linked phone)
    ↓
Continue app (Home) or resume verification step
```

### ✅ Logout
- Firebase: `signOut()`.
- Clears session and navigates back to the login screen with a cleared stack
  (from Settings, with a confirmation dialog).

---

## 3. Project File Structure

```
features/authentication/
├── data/
│   ├── models/
│   │   └── auth_user.dart              Local Firebase user wrapper
│   ├── services/
│   │   ├── firebase_auth_service.dart  All Firebase Auth SDK calls
│   │   └── auth_token_service.dart     Firebase JWT (getIdToken)
│   └── repositories/
│       └── auth_repository_impl.dart   Connects services to the UI layer
└── presentation/
    ├── controllers/
    │   ├── signup_controller.dart
    │   ├── login_controller.dart
    │   ├── phone_auth_controller.dart
    │   └── forgot_password_controller.dart
    ├── providers/
    │   └── auth_providers.dart          Riverpod dependency injection
    └── pages/
        ├── login_page.dart             (login + signup tabs)
        ├── email_verify_screen.dart
        ├── phone_verify_screen.dart
        ├── login_otp_screen.dart       (phone-OTP login)
        └── forgot_password_page.dart
```

**`auth_user.dart`** — local wrapper built from `FirebaseAuth.currentUser`.
Fields: `uid`, `username` (from `displayName`), `email`, `phone` (from
`phoneNumber`), `emailVerified`, `phoneVerified` (= `phoneNumber != null`).

**`firebase_auth_service.dart`** — thin wrapper over the Firebase Auth SDK:
`createAccountWithEmail`, `signInWithEmail`, `updateDisplayName`,
`sendEmailVerification`, `refreshEmailVerified`, `sendPasswordResetEmail`,
`verifyPhoneNumber`, `buildPhoneCredential`, `linkPhoneCredential`,
`signInWithPhoneCredential`, `signOut`.

**`auth_token_service.dart`** — `getFirebaseToken()` →
`currentUser.getIdToken()`, plus `getBearerHeader()`.

**`auth_repository_impl.dart`** — orchestrates flows (signUp, checkEmailVerified,
startPhoneVerification, confirmPhoneForSignup, loginWithEmail,
loginWithPhoneCredential, resetPassword, logout) and returns `AuthUser`.

**`auth_providers.dart`** — DI graph: `firebaseAuthProvider`,
`firebaseAuthServiceProvider`, `authTokenServiceProvider`,
`authRepositoryProvider`, `authStateChangesProvider`, `currentAuthUserProvider`.

State management is **Riverpod** (existing project choice — no GetX/Bloc).

---

## 4. JWT Flow

**Flutter** mints the token:
```dart
final token = await FirebaseAuth.instance.currentUser?.getIdToken();
// via AuthTokenService.getFirebaseToken()
```

**Future API request** attaches it:
```
Authorization: Bearer <firebase_token>
```

**Node.js backend** verifies it:
```js
const decoded = await admin.auth().verifyIdToken(token);
// extract: decoded.uid, decoded.email, decoded.phone_number
```

Then **PostgreSQL** stores the business data keyed by the Firebase `uid`:
user profile, 12-step registration, photos, preferences, matches,
subscriptions, chat metadata.

---

## 5. Removed Firestore Architecture

Removed on 2026-07-07 (do not re-add):

- `cloud_firestore` dependency
- `FirestoreUserService`
- Firestore `UserModel`
- `users/{uid}` collection
- `firestore.rules` (+ the `firestore` block in `firebase.json`)

**Reason:** avoid duplicate user sources. PostgreSQL will be the single source
of truth for all business data; Firebase only proves identity.

---

## 6. Security

- ✅ Password is never stored or logged — handed straight to Firebase.
- ✅ Firebase manages credentials and auth-state persistence.
- ✅ Tokens are short-lived signed JWTs (`getIdToken`), auto-refreshed.
- ✅ No Firebase private/admin keys in the app (Admin SDK lives on the backend).
- ✅ No hardcoded secrets (config via `firebase_options.dart`, generated).
- ✅ Forgot-password is account-enumeration safe.
- ✅ Production-ready for Android and iOS.

---

## 7. Firebase Console Requirements

**Authentication providers — enable:**
- Email/Password
- Phone

**Android:**
- SHA-1 and SHA-256 fingerprints registered
- `android/app/google-services.json` present
- Phone Auth needs the **Blaze** (pay-as-you-go) plan

**iOS:**
- `GoogleService-Info.plist` configured

---

## 8. Current Validation Status

- `flutter analyze` → **No issues found.**
- Authentication layer is complete and ready.
- Backend integration is pending (see next steps).

---

## 9. Next Development Steps

1. Create the Node.js backend.
2. Add the Firebase Admin SDK.
3. Add Firebase JWT verification middleware (`verifyIdToken`).
4. Design the PostgreSQL schema (users keyed by Firebase `uid`).
5. Build user-profile APIs (`POST /api/auth/register`, profile CRUD).
6. Connect the 12-step matrimony registration to the backend.
