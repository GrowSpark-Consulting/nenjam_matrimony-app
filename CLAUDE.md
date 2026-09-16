# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository — **Nenjam Matrimony** ("Find Your Forever").

It was produced by directly inspecting the current codebase (package files, source, Prisma schema, CI config, git history) on 2026-09-16, not by trusting other docs in this repo at face value. Where something could not be verified with confidence, it is marked **Needs verification** rather than guessed.

> **Read this before trusting any other doc in this repo.** `Frontend/BRAIN.md` and `Frontend/PROJECT_RULES.md` describe an **aspirational** architecture (Riverpod code generation, `freezed` DTOs, a UseCase layer, a `Result<Success, Failure>` functional error model, a Laravel/MySQL backend, a navy-and-gold theme, `flutter_secure_storage` for tokens, golden tests, mandatory `Nm`-prefixed widgets) that **does not match the real, working code** in numerous material ways (documented inline below). `PROJECT_DOCUMENTATION.md` at the repo root is a detailed snapshot from **2026-07-11** — useful for historical structure, but stale on CI, module-registration counts, routing guards, the color palette, FCM, and the API base URL; a lot has shipped since (chat, real-time delivery, location & religion master data, interests/shortlist/profile-views, push notifications). **When any of these docs conflicts with the actual source under `Frontend/lib/` or `backend/`, the source wins.** Follow the real, current patterns described below, not those documents' prescriptions.

---

## 1. Project Overview

**Nenjam Matrimony** is a premium Indian matrimony app: a 12-step profile-registration wizard plus a "Relationship Intelligence" layer (profile prompts, an OCEAN personality quiz, Vedic horoscope compatibility), discover/matches/interests/shortlist, real-time chat, and push notifications.

| Layer | Technology |
|---|---|
| Mobile client | **Flutter** (Dart `^3.9.2`, Flutter floor `>=3.44.6` — hard-enforced, `flutter pub get` refuses an older SDK) |
| State management | **Riverpod** (`flutter_riverpod ^2.6.1`), **hand-written providers** — no `riverpod_generator`/`@riverpod` codegen anywhere despite what `BRAIN.md`/`PROJECT_RULES.md` claim |
| Routing | **go_router** `^14.8.1`, with a real centralized auth `redirect:` guard (see §5) |
| Backend framework | **NestJS `^11`**, a 4-app Nest-CLI monorepo (`apps/api` real; `worker`/`scheduler` partially real; `websocket` dead code — see §7) |
| ORM / DB | **Prisma** (`@prisma/client` + `@prisma/adapter-pg`, driver-adapter mode) → **PostgreSQL** (shared Neon instance in practice — see §17) |
| Auth | **Firebase Auth only** (email/password + phone OTP + Google Sign-In), verified server-side via Firebase Admin SDK. No custom JWT issuance despite a required `JWT_SECRET` env var (Joi-validated but not consumed by any token logic — see §5/§7.5) |
| Firebase (client) | `firebase_core`, `firebase_auth`, `firebase_messaging` (FCM), `google_sign_in`. **Not used**: Firestore, Firebase Storage, Crashlytics, Analytics |
| API comms | Dio HTTP client + a native Socket.IO connection for real-time delivery (interests/notifications/shortlist events + chat) |
| Cache / real-time transport | **Redis** (`ioredis`) — genuinely used: Discover-feed caching (`FeedCacheModule`, `@Global`), Firebase-UID→User lookup cache, and the Socket.IO Redis adapter for horizontal scale |
| Search | **Elasticsearch** — connected/health-checked only; `search` module is unregistered (not wired into `AppModule`) |
| Queue | **BullMQ** — real, but only one processor is actually registered (the mail queue in `libs/mail`); the other 7 processor files under `apps/worker` are unregistered stubs |
| Email | **Resend** via `libs/mail` (real: templates, queue, `EmailLog` audit table, no-op provider fallback when `RESEND_API_KEY` is absent) |
| Photo storage | **AWS S3** via `libs/storage`'s `S3Service` (real — presigned GET/PUT URLs, wired into `ProfilesModule`/`PhotoService`). `CloudFrontService` is a 4-line stub |
| Package manager | **pnpm** (backend) |
| Deployment | **Railway** (Nixpacks, no Dockerfile) — see §15 |

Target users: Indian matrimony seekers (Tamil-first; `en`/`ta` shipped, more languages on the roadmap per `AppConstants`).

---

## 2. Repository Structure

```
nenjam_matrimony_app/
├── Frontend/                # Flutter app — see §3/§4
│   ├── lib/{core,features,l10n}/
│   ├── test/                # ~70 test files — see §10
│   ├── android/, ios/, web/, windows/, linux/, macos/
│   └── BRAIN.md, PROJECT_RULES.md   # aspirational docs — see the warning above
├── backend/                 # NestJS pnpm monorepo — see §7/§8
│   ├── apps/{api,worker,scheduler,websocket}/
│   ├── libs/{common,config,logger,database,cache,search,queue,firebase,storage,mail}/
│   ├── scripts/             # ops/verification scripts — see §14
│   └── railway.toml, prisma.config.ts
├── docs/                    # architecture notes, API reference, dev handoffs, daily reports
│   ├── api/, architecture/, development/, discover/, registration/, daily-reports/
├── scripts/
│   ├── dev/                 # start_dev.ps1, stop_dev.ps1, USB/adb helpers (Windows)
│   └── git-hooks/           # opt-in pre-commit secret scanner — see §12/§13
├── seed-data/                # ISO country/subdivision/city + religion source data, consumed by backend seeders
├── .github/workflows/ci.yml # single CI workflow, backend + frontend jobs — see §10/§13
├── PROJECT_DOCUMENTATION.md  # 2026-07-11 snapshot — historical context only, see warning above
├── auth-architecture.md      # root design doc: Firebase-auth-only decision (still broadly accurate)
└── registration-wizard-integration.md
```

### `Frontend/lib/` layout

```
lib/
├── main.dart                 # the only real entrypoint (no flavor entrypoints exist despite BRAIN.md)
├── firebase_options.dart
├── core/                     # cross-cutting: config, constants, errors, network, permissions,
│                              # providers, realtime, router, services, theme, utils, widgets
└── features/<name>/           # 30+ feature modules; most follow domain/data/presentation,
                                # thinner features (help, language, onboarding, premium, splash, ...)
                                # have presentation/ only
```

Each `core/widgets/` subfolder (`buttons/`, `cards/`, `chips/`, `dialogs/`, `sheets/`, `avatars/`, `badges/`, `indicators/`, `images/`, `navigation/`, `feedback/`, `layout/`, `permissions/`, `system_ui/`, `relationship_intelligence/`) holds the reusable component library — reuse from here before writing a new widget. Widget names are **not** consistently `Nm`-prefixed (only a handful are); most are plain names like `gradient_button.dart`, `empty_state.dart`.

### `backend/apps/api/src/modules/<name>/` layout

```
modules/<name>/
├── <name>.module.ts
├── controllers/ services/ dto/
├── repositories/ entities/     # optional, per module
└── tests/                      # *.spec.ts
```

18 module directories exist. **Only 13 are imported into `AppModule`** (`apps/api/src/app.module.ts`): `reference-data`, `profiles`, `matches` (+ its `cache/feed-cache` submodule), `interests`, `notifications`, `chat`, `realtime`, `settings`, `users`, `support`, `blocks`, `reports`. **Not wired anywhere** (files exist, dead from the running app's perspective): `admin`, `astro`, `search`, `subscription`, `trust-score`, `verification`. Before assuming a module works, check whether it's actually in that `imports` array.

---

## 3. Flutter Development Rules

**State management**: Riverpod, hand-written (`Provider`, `StateProvider`, `FutureProvider`/`.autoDispose`, `StreamProvider`, `NotifierProvider`/`.autoDispose`). Do **not** introduce `riverpod_generator`/`@riverpod` codegen, `get_it`/`injectable`, `provider` (legacy), `flutter_bloc`, or `GetX` — none are dependencies, and DI is done entirely through Riverpod's own provider graph (`ref.watch()` chains, e.g. `firebaseAuthProvider → firebaseAuthServiceProvider → authRepositoryProvider`).

**Feature organization**: one folder per vertical under `lib/features/`. Larger features use `domain/{models,repositories}`, `data/repositories` (some newer features pair a `Mock*Repository` with an `Api*Repository` behind one `Provider`, so flipping mock→real is a one-line override), and `presentation/{providers,pages,widgets}`. There is **no `usecases/` layer anywhere** in the codebase — providers call repositories directly. Do not add a UseCase layer; it isn't the established pattern here.

**Routing**: `go_router`, single config in `lib/core/router/app_router.dart`, route constants in `route_names.dart`. `StatefulShellRoute.indexedStack` powers the 4-tab bottom nav (discover/matches/messages/premium). See §5 for the auth guard.

**API layer**: `lib/core/network/` — `ApiClient` (Dio), `ApiEndpoints`, `ApiException`, `api_interceptor.dart` (`AuthInterceptor` → `LoggingInterceptor` → `ErrorInterceptor`), `network_error_mapper.dart`. Errors surface as a thrown `ApiException` caught at the repository/provider boundary, or as Riverpod's native `AsyncValue.error` for `FutureProvider`/`AsyncNotifier` — there is **no** project-wide `sealed Failure`/`Result<Success, Failure>` type despite `PROJECT_RULES.md` §11 mandating one. Don't build new error handling against that pattern; follow the existing throw/catch + `AsyncValue` convention.

**Models/DTOs**: plain Dart classes with **hand-written** `fromJson`/`toJson`/`copyWith`. No `freezed`, `json_serializable`, or `json_annotation` — none are dependencies. Don't introduce them for new models; match the existing hand-written style.

**Form validation**: centralized in `lib/core/utils/validators.dart` (`Validators.name`, `.username`, `.email`, ...), static functions returning `String?` for `TextFormField.validator`. Messages come from `AppL10n.current` (not `AppLocalizations` directly) because validators are used as bare tear-offs with no `BuildContext`.

**Image/photo handling**: `image_picker` → crop (`core/services/media/crop_service.dart`) → compress (`core/services/media/image_compressor.dart`, pure-Dart JPEG via `package:image`, dispatched through `compute()` off the UI isolate) → multipart upload via `ApiClient.upload()`. Display via `cached_network_image` + `shimmer` placeholders — never raw `Image.network`. Chat attachments/voice notes use a separate `core/services/media/attachment_picker.dart` + `record`/`audioplayers` (voice is local-record/preview only — no chat media-upload endpoint exists yet, see `docs/development/chat-backend-handoff.md`).

**Environment configuration**: `flutter_dotenv` loads one of `.env.dev`/`.env.qa`/`.env.staging`/`.env.production`, but in practice `main.dart` only ever picks `kReleaseMode ? AppEnvironment.production : AppEnvironment.dev` — there's no code path for `qa`/`staging` at runtime and no Flutter product-flavor setup (`android/app/build.gradle.kts` has no `productFlavors`). **The API base URL does not come from these `.env` files at all** — see §9. Never hardcode API URLs or secrets in Dart source; the `.env.example` files only cover `ENABLE_LOGGING`, `S3_BUCKET_NAME`, `STRIPE_PUBLISHABLE_KEY`.

**Naming**: `snake_case.dart` files, `UpperCamelCase` classes, `lowerCamelCase` methods/variables/providers — this part of `PROJECT_RULES.md` §15 does match the real code.

---

## 4. Flutter UI / Design Rules

The **real** design system (verify against `lib/core/theme/app_colors.dart` before trusting any other doc — `BRAIN.md`'s "navy `#1B2B4B` + gold `#C9A84C`" palette is stale):

- **Palette**: Plum + Magenta + Rose, a documented 60/25/10/5 system. Primary `#6B21A8` (plum/purple, 25%), secondary `#D4147D` / accent `#E95793` (magenta 10% / rose 5%), neutrals `#FFF9FC`/`#FFFFFF` (60%). Status colors: success `#17754D`, warning `#9A5A00`, error `#D92D3F`, info `#3462D6`.
- **Light-mode only, by design**: `main.dart` hard-codes `themeMode: ThemeMode.light` with no dark `ThemeData` supplied at all — this is enforced by a dedicated `test/light_mode_only_test.dart`. Do not add dark-mode theming without an explicit product decision.
- **Typography**: Google Fonts — **Poppins** for display/headings, **Inter** for body, with `GoogleFonts.notoSansTamil()` as a `fontFamilyFallback` (not a family swap) so mixed Tamil/English strings don't flip fonts.
- **Spacing/radius**: `lib/core/constants/app_spacing.dart` (4px grid: `xs=4` … `xl8=96`; radii `radiusXs=4` … `radiusFull=999`) and `lib/core/theme/tokens/` (`app_radius.dart`, `app_touch_target.dart`, `app_animation_tokens.dart`). Use these tokens, not literal `EdgeInsets`/`BorderRadius` values.
- **Responsive**: `flutter_screenutil` (`ScreenUtilInit(designSize: Size(375, 812), minTextAdapt: true, splitScreenMode: true)` in `main.dart`) plus `core/utils/responsive_utils.dart`. CI's frontend test suite specifically covers the 320–480dp matrix in portrait/landscape, `en`/`ta`, with a keyboard open — treat new screens as needing the same coverage.
- **Component reuse**: search `lib/core/widgets/**` before creating a new button/card/chip/dialog/sheet. Extend an existing widget with an optional parameter rather than duplicating it.
- **No golden-test infrastructure exists** (`test/goldens/` doesn't exist) despite `PROJECT_RULES.md`/`BRAIN.md` describing one — don't assume golden tests are part of the pipeline.

---

## 5. Routing & Authentication

**Router-level guard is real** (this supersedes `PROJECT_DOCUMENTATION.md`'s July claim that none existed). `createRouter(ref)` in `lib/core/router/app_router.dart` installs a single `redirect:` callback:
- Routes in `RouteNames.publicRoutes` bypass the guard.
- Otherwise it **awaits** `authStateChangesProvider.future` (Firebase's first-emission signal, not a synchronous `currentUser` read, to avoid racing session restore).
- If there's no Firebase user, it still allows access when `_signedInLocally()` is true — a documented **temporary bridge** for two cases: `storageService.onboardingCompleted` (new-signup users who finished onboarding before minting a Firebase credential) and `hasLocalAuthSession()` (the dummy-OTP / local-password login path, which mints no Firebase session — see backend note below). Otherwise it redirects to `RouteNames.registrationLanding` (not `/login`).
- `refreshListenable: GoRouterRefreshStream(authRepositoryProvider.authStateChanges())` re-runs the redirect on every Firebase auth-state emission, so a logout from anywhere bounces the user automatically.

`main.dart`'s `NenjamMatrimonyApp` additionally: re-checks the session on `AppLifecycleState.resumed` (`_checkSessionOnResume`), and centrally tears down/rebuilds per-user provider state (`myPhotosProvider`, `myProfileProvider`, `profileDraftResponseProvider`, nav-state storage) on every sign-out/sign-in transition via one `ref.listen(authStateChangesProvider, ...)` — this is the single place that logic lives; don't duplicate it in individual screens.

**Backend**: `FirebaseAuthGuard` (`libs/common/src/guards/firebase-auth.guard.ts`, real) verifies the `Authorization: Bearer <Firebase ID token>` header via `firebase-admin`, JIT-provisions/reconciles the internal `User` row by `firebaseUid`, and caches the `firebaseUid → User.id` lookup in Redis. It is applied **per-controller** via `@UseGuards(FirebaseAuthGuard)`, **not** globally as an `APP_GUARD` — every new protected controller must add this decorator explicitly; there is no default-deny.

`@Public()` and `@Roles()` decorators exist (`libs/common/src/decorators/`) but are unfinished `SetMetadata` stubs with no guard reading their metadata — using them today has **no effect**. `RolesGuard` and `AdminOnlyGuard` are empty stub classes. Don't rely on any of these for authorization; there is currently no role-based access control mechanism actually wired up.

⚠️ **`libs/common/src/auth/dev-auth.ts` — a real, currently-live authentication bypass.** When `DUMMY_OTP_ENABLED=true` (any environment, including production) or `DEV_AUTH_ENABLED=true` (non-production), `FirebaseAuthGuard` accepts a request with **no** `Authorization` header as any well-formed E.164 phone number, with no credential at all — this exists because real Firebase Phone Auth needs SMS billing that isn't enabled yet, and the app's signup flow otherwise has no way to mint a session. It is scoped down by an optional `DUMMY_OTP_PHONES` allowlist, and fully closed by `USE_REAL_OTP=true` (which restores real Firebase Phone Auth) or a non-empty `DUMMY_OTP_PHONES`. **Never enable `DUMMY_OTP_ENABLED`/`DEV_AUTH_ENABLED` against a database containing real user accounts.** A prior incident (`fix/dev-auth-header-bypass`) already hardened this once — treat any change here as security-sensitive and read the file's header comment in full before touching it.

JWT: `JWT_SECRET` is a required, Joi-validated env var, but **no `@nestjs/jwt`/`jsonwebtoken`/`passport-jwt` dependency exists and nothing reads it for token issuance or verification** — auth is Firebase-ID-token-only, end to end. `RefreshToken` is a modeled-but-unused Prisma table.

---

## 6. Firebase

- **Client**: `firebase_core`, `firebase_auth` (email/password, phone OTP, Google Sign-In via `google_sign_in`), `firebase_messaging` (FCM, wired through `push_notification_service.dart` and a Riverpod provider watched for the whole session in `main.dart`) + `flutter_local_notifications` for local display. Project id `matrimony-platform-30b50` (from `firebase.json`/`firebase_options.dart` — not a secret, Firebase client config is public by design; the pre-commit hook explicitly exempts it). **Not used**: Firestore, Firebase Storage, Crashlytics, Analytics.
- **Server**: `firebase-admin` in `libs/firebase` (`FirebaseService`), used only to `verifyIdToken()` inside `FirebaseAuthGuard`. `FIREBASE_PROJECT_ID`/`FIREBASE_CLIENT_EMAIL`/`FIREBASE_PRIVATE_KEY` are optional at boot (the app still starts without them) but every Firebase-guarded route fails without them.
- Per `auth-architecture.md` (root): Firebase is deliberately **auth-only** — the real profile lives in Postgres via NestJS, keyed on `User.firebaseUid`. This decision still holds.
- Never commit `google-services.json`/`GoogleService-Info.plist` contents as if secret (they're public client config and the pre-commit hook knows this) — but never commit a Firebase **service-account** JSON, which the same hook explicitly blocks.

---

## 7. Backend — NestJS

**Monorepo shape** (`nest-cli.json`, `monorepo: true`): 4 apps, 10 shared `@app/*` libs.

- **`apps/api`** — the real HTTP API + WebSocket gateway (Socket.IO mounted on the same HTTP server via a Redis-backed adapter). This is where almost all real logic lives.
- **`apps/worker`** — BullMQ consumer; only `MailModule.forWorker()` (the email queue processor) is actually registered. 7 other processor files (photo compression/moderation, push fanout, search indexing, recommendation recompute, Prokerala/astrology lookup, OTP dispatch) exist but are **not wired into `worker.module.ts`**.
- **`apps/scheduler`** — cron via `@nestjs/schedule`; only `WeeklyDigestCron` is registered. 4 other cron files (inactive-profile nudge, search-reindex sweep, subscription expiry, trust-score decay) are unregistered stubs.
- **`apps/websocket`** — exists but is explicitly **not deployed** (per `railway.toml`'s comments) and every file in it is a one-line TODO stub. Real-time chat/presence actually runs inside `apps/api`'s `RealtimeModule`/`ChatModule` — don't build against `apps/websocket`.

**Modules**: see the wired/unwired list in §2. Controllers are thin and delegate to services (spot-checked in `interests`, `chat`, `profiles`); business logic belongs in services, matching existing style. Controllers are heavily annotated with `@nestjs/swagger` (`@ApiTags`/`@ApiOperation`/...) — Swagger UI is mounted at `/api/docs` in development only (`main.ts`).

**Guards/Interceptors/Pipes/Filters** — know which are real before relying on them:
| Real | Stub / unwired |
|---|---|
| `FirebaseAuthGuard` | `RolesGuard`, `AdminOnlyGuard`, `WsJwtGuard` (websocket app) |
| `@CurrentUser()` decorator | `@Public()`, `@Roles()` decorators (no reader) |
| Global `ValidationPipe` (whitelist/transform/forbidNonWhitelisted) | `ZodValidationPipe` (empty; `zod` unused anywhere) |
| `ThrottlerGuard` (global `APP_GUARD`, real rate limiting) | `transform-response.interceptor.ts`, `request-timing.interceptor.ts` (neither registered) |
| module-local `conversation-participant.guard.ts` (chat) | `AllExceptionsFilter` (empty `@Catch()`, **not registered** — Nest's default exception handling is what actually runs) |
| NestJS's built-in `Logger` (per-class, the real logging mechanism) | the entire `@app/logger` lib (`LoggerModule`/`LoggerService`/`RequestContextMiddleware` are all no-ops; nothing consumes it) |

**Validation**: `class-validator`/`class-transformer` via the global `ValidationPipe`. DTO quality is inconsistent across modules — some are fully decorated (`chat/dto/send-message.dto.ts`), others are empty stub classes (e.g. `interests/dto/send-interest.dto.ts`). When adding a DTO, decorate every field; don't copy an empty stub.

**Error handling**: no active global exception filter — rely on Nest's built-in `HttpException` subclasses (`UnauthorizedException`, etc.) thrown from guards/services. No custom domain exception hierarchy was found; **needs verification** if you're about to add one — check for `extends HttpException` usage first so you don't duplicate an existing pattern.

**API versioning**: none. Routes are unversioned (`/profiles`, `/interests`, `/chat/messages`, ...).

---

## 8. Prisma / PostgreSQL

- `libs/database/prisma/schema.prisma` — `datasource db { provider = "postgresql" }`, `generator client { provider = "prisma-client-js", output = "../generated/client" }` (client is generated into `libs/database/generated/client`, **committed alongside source**, not `node_modules` — driver-adapter mode via `@prisma/adapter-pg`, not the default engine binary).
- **41 models / 23 enums**, spanning: identity (`User`, `AdminAccount`), the registration wizard (`RegistrationStep`, `UserProfile`, `PartnerPreference`, `AstrologyProfile`, `ProfilePhoto`), interactions (`ExpressInterest`, `Shortlist`, `ProfileView`, `HoroscopeMatch`), Relationship Intelligence (`PsychologyQuiz`/`QuizQuestion`/`UserQuizResponse`, `PromptBankItem`/`UserProfilePrompt`), subscriptions/payments (`SubscriptionPlan`, `UserSubscription`, `PaymentTransaction` — Razorpay-shaped), chat (`ChatRoom`, `ChatParticipantState`, `ChatMessage`, `MessageReaction`), verification/trust (`KycVerification`, `FaceVerification`, `TrustScoreLog`), notifications (`Notification`, `DevicePushToken`), moderation (`UserReport`, `UserBlock`, `SupportTicket`, `AuditLog`), location master data (`Country`→`Subdivision`→`City`, ISO-keyed), religion master data (`Religion`→`Community`), `UserSettings`, `EmailLog`.
- **Migrations**: `libs/database/prisma/migrations/`, 26 folders dated 2026-07-07 through 2026-09-15. CI (`ci.yml`) both replays every migration onto an empty database **and** runs `prisma migrate diff --from-config-datasource --to-schema ...` to catch schema/migration drift — this check exists because that exact failure mode (a schema change applied to the shared DB but never committed as a migration) has happened before. **Always generate a real migration for a schema change** (`pnpm prisma:migrate:dev`); never hand-edit the shared database and skip the migration.
- Two config surfaces for the same database exist and must be kept in sync: `DATABASE_URL` (what Prisma CLI/the adapter actually reads) vs. discrete `DATABASE_HOST/PORT/USER/PASSWORD/NAME` fields (both accepted by Joi validation; `DATABASE_URL` is preferred for the shared managed Postgres).
- Seed scripts (`pnpm db:seed`, `pnpm seed:locations`, `pnpm seed:religions`) are upsert-based and safe to re-run.
- **Never run destructive Prisma commands (`prisma migrate reset`, `db push` against a real environment) without explicit approval** — the actual dev/shared database is a Neon Postgres instance (see §17), not a disposable local one.

---

## 9. API Development (Flutter ↔ NestJS)

- **Base URL is a compile-time Dart constant, not an `.env` value**: `AppConstants.apiBaseUrl` = `String.fromEnvironment('API_BASE_URL', defaultValue: 'https://<production-railway-host>')` (`lib/core/constants/app_constants.dart`). **The production Railway API is the default even in debug builds** — to point at a local backend, override at build/run time with `--dart-define=API_BASE_URL=http://127.0.0.1:3000` (physical Android device: pair with `adb reverse tcp:3000 tcp:3000`, or use `scripts/dev/start_dev.ps1`; emulator: use `10.0.2.2` instead). `.env.dev`/`.env.qa`/etc. do **not** carry the API URL.
- **HTTP client**: Dio, 20s connect/receive/send timeouts (8s for the startup health probe), `validateStatus: status < 500` (4xx responses resolve normally so callers inspect the body themselves).
- **Auth header**: `AuthInterceptor` injects `Authorization: Bearer <Firebase ID token>` from `AuthTokenService.getFirebaseToken()`. On a 401 it force-refreshes the token and retries **once**; a second failure calls the real sign-out teardown. Retry is skipped for `FormData` bodies (single-use streams) and dummy-OTP sessions (no Firebase token to refresh).
- **DTOs**: hand-written `fromJson`/`toJson` on the client; `class-validator`-decorated DTOs on the server behind a global `ValidationPipe({whitelist, transform, forbidNonWhitelisted})`. Keep both sides in sync manually when a wizard/section shape changes — there's no shared-schema codegen between them.
- **Never log tokens or passwords**: `LoggingInterceptor` deliberately logs method+URL only, never headers/body, specifically so a bearer token can't leak into logs.
- **CORS**: `CORS_ORIGINS` (comma-separated) is the explicit allowlist; unset, it falls back to reflecting the request origin in development and rejecting all cross-origin requests in production — fail-closed, never a hardcoded domain.
- **Rate limiting**: `ThrottlerModule` is global (`APP_GUARD`), counted per client IP with `trust proxy` set to 1 (correct for Railway's single proxy hop). New high-traffic endpoints inherit this by default; opt into a different tier with `@Throttle` rather than bypassing it.

---

## 10. Testing

**Frontend** (`Frontend/test/`, ~70 files, `flutter_test` only — **no `mockito`/`mocktail`**, hand-written fakes with `noSuchMethod` forwarding + `ProviderScope(overrides: [...])` for DI substitution):
- Organized mirroring `lib/features/<feature>/`, named after the behavior under test (e.g. `onboarding_religion_cascade_test.dart`), not a strict unit/widget/golden split.
- Cross-cutting regression suites worth knowing about: `responsive_audit_test.dart`, `responsive_pages_audit_test.dart`, `light_mode_only_test.dart`, `bottom_nav_clearance_test.dart`, `no_trust_score_references_test.dart`.
- No `integration_test/` directory and no golden tests exist despite other docs describing them — don't assume that infrastructure is there.
- Commands: `flutter analyze --no-fatal-infos` (matches CI — `--no-fatal-infos` because of pre-existing deprecation infos; errors/warnings are still fatal), `flutter test` (single test file: `flutter test test/path/to/file_test.dart`).

**Backend** (`backend/`, Jest): 75 `*.spec.ts` unit specs colocated per module/lib, plus 3 e2e specs (`apps/api/test/*.e2e-spec.ts`, run via a separate `jest-e2e.json` config) including `profile-ownership.e2e-spec.ts` (auth rejection, cross-user data isolation, mass-assignment protection, idempotent finalize). Commands: `pnpm test`, `pnpm test:watch`, `pnpm test:cov`, `pnpm test:e2e`. Single spec: `pnpm test -- path/to/file.spec.ts`.

**CI** (`.github/workflows/ci.yml`, runs on every PR + push to `main`, cancels superseded runs for the same ref):
- **Backend job**: real Postgres 16 + Redis 7 service containers → `pnpm install --frozen-lockfile` → `prisma generate` → `prisma migrate deploy` (replay all migrations on an empty DB) → **schema-drift check** (`prisma migrate diff`, fails the build on any difference — see §8) → `tsc --noEmit` (type-checks spec files too, unlike `nest build`) → `pnpm test` → `pnpm build:all` → `node scripts/smoke-boot.mjs` (actually boots every built app — catches DI-graph breakage that unit tests can't) → `eslint` (**non-blocking**, `continue-on-error: true`, 38 pre-existing errors tracked toward zero). Firebase/AWS/Resend secrets are deliberately absent — proving the app boots without any third-party credential.
- **Frontend job**: seeds `.env.*` from `.env.example` (no secrets) → `flutter pub get` → `flutter analyze --no-fatal-infos` → `flutter test`. No `flutter build` (would add Gradle/AGP cost for little extra signal).

Before finishing a change: run the formatter/analyzer/linter for the side you touched, run the relevant tests, and — for auth, registration, routing, API, or profile-flow changes — check whether an existing test already covers the behavior before adding a new one.

---

## 11. Code Quality

**Flutter**: `analysis_options.yaml` extends `flutter_lints/flutter.yaml` plus `strict-casts`/`strict-inference`/`strict-raw-types`, and an explicit rule list (`avoid_print`, `prefer_const_constructors`, `prefer_single_quotes`, `require_trailing_commas`, `use_key_in_widget_constructors`, `cancel_subscriptions`, `close_sinks`, ...). Run `dart format`/`flutter analyze` before considering Dart work done; fix analyzer issues rather than suppressing them.

**Backend**: ESLint flat config (`eslint.config.mjs`) — `typescript-eslint` `recommendedTypeChecked` + Prettier integration. `@typescript-eslint/no-explicit-any` is **off**; `no-floating-promises`/`no-unsafe-argument` are `warn`, not `error`. Prettier: single quotes, trailing commas everywhere (`.prettierrc`). Lint is currently non-blocking in CI (38 pre-existing errors) — don't add to that count; new code should lint clean.

---

## 12. Security

- **A pre-commit secret scanner exists but is opt-in per clone**: `scripts/git-hooks/pre-commit` blocks staged AWS keys, Postgres/Redis/MongoDB URLs with inline passwords, Neon passwords, Google API keys, GitHub/Stripe/Resend/Slack tokens, JWTs, and private keys — written after a real incident where live secrets were pasted into `backend/.env.example` (the one `.env*` file git actually tracks). **Enable it**: `git config core.hooksPath scripts/git-hooks`. It exempts public Firebase client config (`google-services.json`, `firebase_options.dart`, etc.) and loopback-only connection strings.
- **The dummy-OTP/dev-auth bypass** (§5) is a real, intentional authentication hole gated by env flags — never enable it against real user data, and treat any change to `libs/common/src/auth/dev-auth.ts` or `firebase-auth.guard.ts` as security-sensitive.
- `FirebaseAuthGuard` is applied **per-controller**, not globally — a new controller with no `@UseGuards(FirebaseAuthGuard)` is unauthenticated by default. Always add it explicitly for anything touching user data.
- `AllExceptionsFilter`, `RolesGuard`, `@Public()`/`@Roles()`, `ZodValidationPipe`, and the response-transform/request-timing interceptors are non-functional stubs (§7) — don't rely on them for anything security-relevant; verify the real mechanism (Nest's default exception handling, `FirebaseAuthGuard`, the global `ValidationPipe`) is what's actually protecting a given path.
- Never log Firebase ID tokens, passwords, or full request/response bodies (`LoggingInterceptor` deliberately avoids this — match that convention).
- Before committing: check `git status`/`git diff` for anything that looks like a real credential, especially in `.env.example` files (the one place a real secret has leaked here before) and any generated/config file.

---

## 13. Git / GitHub Workflow

- **Default branch**: `main`. PRs merge into `main` via GitHub PR (not `staging`/`dev` — despite `PROJECT_RULES.md` §16 claiming otherwise).
- **Branch naming actually used**: `type/short-description` — `feat/…`, `fix/…`, `perf/…`, `chore/…`, `docs/…`, `test/…`, `seed/…` (no ticket-number prefix like `PROJECT_RULES.md`'s `feature/NM-104-...` example).
- **Commit messages**: Conventional Commits, `type(scope): short description` (e.g. `fix(profiles): accept the location master-data codes the client already sends`, `perf(location): stop loading the whole hierarchy at boot`). Match this style.
- **CI** (`.github/workflows/ci.yml`) gates every PR and push to `main` — see §10.
- Never force-push, rewrite shared history, or bypass hooks (`--no-verify`) without the user explicitly asking.

---

## 14. Development Environments

**Frontend**:
```bash
cd Frontend
flutter pub get      # also runs flutter gen-l10n (generate: true in pubspec.yaml)
flutter run          # defaults to the production Railway API — see §9 to point at a local backend
```
Windows dev helpers: `scripts/dev/start_dev.ps1` / `stop_dev.ps1` (starts the backend + sets up `adb reverse tcp:3000 tcp:3000` for a physical device over USB), `scripts/dev/setup_android_usb.bat` / `remove_android_usb.bat`. See `docs/development/android-usb-debugging.md`.

**Backend**:
```bash
cd backend
pnpm install                  # postinstall runs `prisma generate` automatically
cp .env.example .env          # fill in real values; .env.local overrides .env (git-ignored, takes precedence)
pnpm prisma:migrate:dev        # or prisma:migrate:deploy in a non-dev environment
pnpm db:seed                    # subscription plans + OCEAN quiz + default admin
pnpm seed:locations              # ISO country/subdivision/city master data
pnpm seed:religions               # religion/community master data
pnpm start:dev                     # nest start api --watch, port 3000 (Socket.IO shares this port)
```
Required external services (none containerized locally — provision manually or point at the shared Neon/Redis/Elasticsearch instances): PostgreSQL, Redis, Elasticsearch (required at boot — dev tolerates it being unreachable, prod does not), SMTP config (required by Joi even though Resend is the real path), Firebase Admin credentials (optional at boot; every Firebase-guarded route 500s without them).

**Common commands**:
| Task | Command |
|---|---|
| Backend dev server | `pnpm start:dev` |
| Backend build all apps | `pnpm build:all` |
| Backend migrations (dev/deploy) | `pnpm prisma:migrate:dev` / `pnpm prisma:migrate:deploy` |
| Backend Prisma Studio | `pnpm prisma:studio` |
| Backend lint / unit / e2e | `pnpm lint` / `pnpm test` / `pnpm test:e2e` |
| Frontend analyze / test | `flutter analyze --no-fatal-infos` / `flutter test` |
| Frontend build APK | `flutter build apk` |

---

## 15. Deployment

- **Backend**: Railway, Nixpacks builder (**no Dockerfile anywhere in the repo**). `railway.toml`: `buildCommand = "pnpm build:api && pnpm build:worker && pnpm build:scheduler"` (deliberately excludes `websocket` — it's unused, see §7), `startCommand = "pnpm run start:prod"`, `healthcheckPath = "/health"`. `worker` and `scheduler` each need their **own** Railway service (same repo, Root Directory set to `backend`) with an overridden start command (`start:worker:prod` / `start:scheduler:prod`) — Railway can't run multiple start commands from one config in one directory.
- **Database**: a shared **Neon** Postgres instance in practice (referenced by CI's own comments about "the shared Neon database"). Treat it as shared infrastructure, not a disposable local DB — never run destructive Prisma commands against it without explicit approval, and use a disposable branch for any exploratory schema testing.
- **Frontend deployment**: no CI/CD pipeline for building or publishing the Flutter app was found (no fastlane, no store-upload workflow). **Needs verification** if one exists outside this repo.
- Never place real production secrets in this file or in `.env.example`.

---

## 16. Performance

Known performance-sensitive areas, already addressed in the current code — understand the existing mechanism before changing it:
- **Discover feed**: Redis-cached (`FeedCacheModule`, `@Global`, feed version + invalidation) plus a tunable **progressive fallback strategy** (`FALLBACK_ENABLED`, `AGE_RELAX_STEP_1/2`, `MAX_FALLBACK_TIER` env vars) that relaxes match criteria in steps rather than returning an empty feed.
- **Real-time delivery**: events carry only `{ id, at }` signals over Socket.IO; the client re-fetches through existing authenticated REST endpoints. This keeps payloads tiny and delivery idempotent — don't start putting full payloads on the socket.
- **API response compression**: gzip via `compression({ threshold: 1024 })` in `main.ts` — measured 75–86% size reduction on real feed/chat/notification pages on Indian mobile networks. Keep new endpoints JSON-shaped so this keeps working.
- **Firebase-UID lookup caching**: `FirebaseAuthGuard` caches `firebaseUid → User.id` in Redis rather than hitting Postgres on every authenticated request.
- **Photo pipeline**: compression happens off the UI isolate (`compute()`) on Android/iOS; falls back to inline on web (no isolates there).
- **Location data**: loaded lazily rather than fetching the whole country/subdivision/city hierarchy at boot (`perf/location-lazy-loading`).
- Always check whether Redis/Elasticsearch is *actually* used for a given concern before assuming caching/search exists for it — both are connected, but Elasticsearch itself is unused (the `search` module isn't wired in).

---

## 17. Existing Project Constraints

- **Shared Neon Postgres** is the real dev/staging database — not local Docker/Postgres. Never point destructive tooling at it without confirming which branch/instance you're on.
- **Existing Firebase project** (`matrimony-platform-30b50`) and **existing Railway deployment** — don't create parallel projects/services; reuse what's configured.
- **`PROJECT_DOCUMENTATION.md`** (root) is a detailed but dated (2026-07-11) snapshot — good for historical structure/DB-design narrative, but its CI status, module-registration counts, routing-guard claims, color palette, and "no FCM" claim are all superseded by the current code. Cross-check anything load-bearing against the live source.
- **`Frontend/BRAIN.md` and `Frontend/PROJECT_RULES.md`** describe an aspirational architecture that materially diverges from the real code (see the warning at the top of this file and §3/§4/§10). Don't cite them as authority when they conflict with what's actually in `lib/`.
- The **dummy-OTP auth bypass** (§5/§12) is a live, intentional exception to normal auth — it exists because SMS billing for real Firebase Phone Auth isn't enabled yet, not because the design intends a permanent bypass.
- A large fraction of "enterprise NestJS scaffolding" (global exception filter, response/timing interceptors, Zod pipe, roles guard/decorators, the whole `@app/logger` lib, and 6 of 18 feature modules) is present as files but inert — see the table in §7. Don't assume a file's existence means it's wired in; check `AppModule`/`main.ts`.

---

## 18. How Claude Should Work

1. Understand the request; check whether it touches Flutter, NestJS, or both.
2. Read the relevant existing feature/module before writing anything — this repo has a real/aspirational-docs split (§ warning at top) and a real/stub split in the backend (§7); assumptions from either direction will be wrong.
3. Confirm a module is actually wired (`AppModule` imports, `pubspec.yaml`/`package.json` dependencies) before building on it.
4. Match existing patterns exactly: hand-written Riverpod providers (not codegen), hand-written DTOs (not `freezed`), thin Nest controllers delegating to services, `class-validator`-decorated DTOs.
5. Make the smallest change that satisfies the request. Don't add a UseCase layer, a `Result<Success,Failure>` type, or Riverpod codegen because another doc in this repo says to — the working code doesn't use them.
6. Run the formatter/analyzer/tests for whatever you touched (§10/§11) before calling anything done.
7. Review the diff; report exactly what changed, what you verified, and what you couldn't verify.

---

## 19. Skills / MCP Usage

Use the project's installed Flutter/Dart and NestJS/Prisma skills when the task matches (Flutter architecture, responsive layout, layout fixing, widget/integration testing, routing, static analysis, runtime debugging, package conflicts, JSON serialization for the frontend; NestJS backend and Prisma/PostgreSQL skills for the backend). Use MCP tools (Firebase, Dart/Flutter dev tools) when they provide authoritative, live project information — not merely because they're available.

---

## 20. Important Behavior

**Never**: invent files, APIs, database models, or env vars; assume a backend module works because its folder exists; assume `PROJECT_RULES.md`/`BRAIN.md` reflect the real architecture; bypass `FirebaseAuthGuard` or enable the dummy-OTP bypass against real data; commit secrets (the pre-commit hook helps, but isn't enabled by default — turn it on); run destructive Prisma/DB commands against the shared Neon instance without approval; add a UseCase/Result-type layer or Riverpod codegen that doesn't already exist in the code you're editing.

**Always**: verify against the live source in `Frontend/lib/` or `backend/` when a doc's claim matters; check `AppModule`/`app_router.dart`/`pubspec.yaml`/`package.json` before assuming something is wired up; keep changes minimal and matching existing patterns; run the relevant formatter/analyzer/tests; flag anything you couldn't verify instead of guessing.
