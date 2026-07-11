# Registration Wizard — Backend + Frontend Integration

**Last updated:** 2026-07-09

Summary of everything implemented to take the 12-step registration wizard from
"UI-only mockup" to a working, Firebase-authenticated, ownership-isolated
feature backed by Postgres. Covers backend (NestJS) and frontend (Flutter)
work in this pass.

---

## 1. Backend — Database

- Expanded `backend/libs/database/prisma/schema.prisma` from a single bare
  `User` model to the full 30-model domain design (auth, profiles,
  astrology, matching, quiz, subscriptions, chat, verification,
  notifications, moderation).
- Added `RegistrationStep.draftData` (JSON column) — holds the wizard's
  in-progress, per-section state until `finalize()` maps it into the real
  tables. The schema already tracked step *progress*
  (`currentStep`/`completedSteps`) but had nowhere to hold the actual
  values being typed in.
- `User.firebaseUid` is `@unique` (was already in the 30-model schema) —
  the 1:1 anchor between a verified Firebase identity and an internal user
  row.
- Migrations: `20260707062025_init`, `20260708141027_add_registration_step_draft_data`.
- Seeders: `admin.seeder.ts`, `plans.seeder.ts`, `quiz.seeder.ts`
  (`pnpm run db:seed`).

## 2. Backend — Registration Wizard API

`backend/apps/api/src/modules/profiles/` — real implementation (not
scaffolding) for steps 1–11:

| Endpoint | Purpose |
|---|---|
| `GET /profiles/draft` | Current user's in-progress draft + completion % |
| `PATCH /profiles/draft/basic-details` | Step 1 |
| `PATCH /profiles/draft/religion-details` | Step 2 |
| `PATCH /profiles/draft/language-details` | Step 3 |
| `PATCH /profiles/draft/location-details` | Step 4 |
| `PATCH /profiles/draft/education-details` | Step 5 |
| `PATCH /profiles/draft/physical-details` | Step 6 |
| `PATCH /profiles/draft/lifestyle-details` | Step 7 |
| `PATCH /profiles/draft/family-details` | Step 8 |
| `PATCH /profiles/draft/horoscope-details` | Step 9 |
| `PATCH /profiles/draft/partner-preference` | Step 10 |
| `POST /profiles/me/photos` | Step 11 (metadata only — see gaps) |
| `POST /profiles/finalize` | Maps the draft into `UserProfile` / `AstrologyProfile` / `PartnerPreference` |
| `GET /profiles/me` | The caller's own finalized profile |

Key pieces:
- 10 `class-validator` DTOs, one per step, field names matching the
  Flutter `ProfileDraft` model exactly.
- `ProfileDraftService` — per-section merge into `RegistrationStep.draftData`,
  completion-percentage calculation (mirrors the Flutter model's own logic).
- `ProfileService.finalize()` — maps the draft to the finalized tables,
  including cross-field mapping the schema doesn't make obvious
  (`gothra`→`gotram`, `rashi`→`rasi`, `manglik`→`AstrologyProfile.dosham`
  enum, `brothers + sisters`→`siblings`). Idempotent (upsert, not create) —
  re-finalizing updates rather than erroring or duplicating.
- Fields the wizard collects with no dedicated column yet
  (`denomination`, `familyValues`, `hobbies`, etc.) stay in `draftData` for
  reference but aren't carried into the finalized row — flagged as a
  known schema gap.

## 3. Backend — Firebase Authentication & Ownership

- `libs/firebase/` — real Firebase Admin SDK integration
  (`FirebaseService.verifyIdToken()`), initialized from
  `FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY`.
- `libs/common/src/guards/firebase-auth.guard.ts` (`FirebaseAuthGuard`) —
  verifies the `Authorization: Bearer <Firebase ID Token>` header, rejects
  invalid/expired tokens with 401, and just-in-time provisions the matching
  `User` row (upsert by `firebaseUid`).
- `@CurrentUser()` decorator — returns `{ id, uid, email, phone_number }`
  from the verified token. **No `x-user-id` header fallback remains
  anywhere in the codebase** (grepped clean).
- All three profiles controllers are `@UseGuards(FirebaseAuthGuard)`.
  Ownership is always: verified Firebase `uid` → internal `User.id` (1:1,
  enforced by the unique constraint) → every query filtered by that id.
  Removed `GET /profiles/:id` (arbitrary lookup) since it doesn't belong to
  an "own data only" contract.
- **Verified against your real Firebase project**
  (`matrimony-platform-30b50`): started the API with real credentials in
  `backend/.env.local`, confirmed `Firebase Admin SDK initialized for
  project "matrimony-platform-30b50"` in the boot log, and confirmed a
  fake token gets a genuine Firebase-originated rejection (not a generic
  error), mapped to a real 401.
- `apps/api/test/profile-ownership.e2e-spec.ts` — new, permanent
  automated test. 9 assertions over real HTTP + real Postgres (only
  Firebase's `verifyIdToken` is mocked, since minting a real token needs a
  live client) proving: no-token/bad-token → 401, a client-supplied
  `userId` in the request body is rejected outright, two users' drafts stay
  fully isolated through interleaved writes, re-using the same token
  resumes the same draft, repeat sign-ins never duplicate the `User` row,
  both users finalize into separate profile rows, re-finalizing doesn't
  duplicate.

## 4. Frontend — Wizard Wired to the Backend

Previously: the wizard held everything in local Riverpod state only and
discarded it on submit — confirmed nothing in `lib/` called any backend
endpoint. Now:

- `lib/main.dart` — now calls `AppConfig().init(AppEnvironment.dev)`
  (was never called at all — would have crashed `ApiClient` with a
  `LateInitializationError` the first time anything touched it).
- `lib/core/network/api_client.dart` — added `patch()` (only had
  get/post/put/delete).
- `lib/core/network/api_providers.dart` (new) — builds the shared
  `ApiClient`, wires `AuthInterceptor` to
  `AuthTokenService.getFirebaseToken()` so every request carries a real
  Firebase ID token.
- `lib/core/network/api_endpoints.dart` — added the 13 real endpoint
  constants matching the backend routes above.
- `lib/features/registration/domain/models/profile_draft.dart` — added
  `toJson()` to all 10 step models, including a `gender`/`maritalStatus`
  mapper (`"Male"` → `"MALE"`, `"Never Married"` → `"NEVER_MARRIED"`) since
  the UI's display values don't match the backend's enum values.
- `lib/features/registration/data/repositories/registration_repository.dart`
  (new) — the 10 PATCH calls + `finalize()`, with a typed
  `RegistrationApiException` carrying the backend's own error message.
- `registration_provider.dart` — `syncCurrentStepToBackend()` and
  `finalizeToBackend()` on `RegistrationNotifier`.
- `profile_wizard_page.dart` — "Continue" now awaits the sync before
  advancing, with a loading spinner and an error snackbar on failure.
- `profile_review_page.dart` — "Enter App" now awaits `finalize()` before
  navigating home, same loading/error handling.
- `.env.dev` — `API_BASE_URL` pointed at `http://localhost:3000` (was
  pointing at a nonexistent `api.dev.nenjammatrimony.com`).

**Not verified by running the app** — there's no Flutter SDK in this
environment, so this was reviewed by hand (imports, types, braces) rather
than compiled. One real bug was caught and fixed this way: a `switch`
statement missing required `return`/`break` terminators (Dart compile
error, not just a lint issue).

## 5. Known gaps / what's next

- **`AppConfig.devBypassAuth = true`** (set by a teammate, "Firebase Auth
  temporarily unavailable — suspended API key") skips real Firebase
  sign-in entirely. While it's on, `getIdToken()` returns `null` and every
  wizard request will 401. Needs to be off, with a working Firebase API
  key, before the wired flow can be exercised end-to-end from the app.
- Run `flutter pub get` / `flutter analyze` — not done here (no SDK
  available in this environment).
- Photo upload (step 11) is metadata-only — no S3 SDK installed yet, so
  there's no real file transfer.
- Several wizard fields have no column in the current schema
  (`denomination`, `familyValues`, `hobbies`, `occupationPref`,
  `motherTonguePref`) — preserved in `draftData` but not in the finalized
  profile. Flagged, not fixed — needs a schema decision.
- Elasticsearch is not running in this dev environment (flagged
  repeatedly throughout this project's setup) — unrelated to the
  registration wizard, but blocks the full `AppModule` (and the
  pre-existing `app.e2e-spec.ts`) from booting locally.
