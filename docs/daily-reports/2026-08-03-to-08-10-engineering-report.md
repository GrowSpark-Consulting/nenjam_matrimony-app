# Engineering report — 3 to 10 August 2026

Work merged across four pull requests: **#22, #23, #25, #27**.

Written for someone who wasn't here. It covers what shipped, why each decision
was made, what was measured rather than assumed, and — at the end, in detail —
**what is still not done**.

`main` is at `664a44b`, CI green.

---

## Contents

1. [Merged pull requests](#1-merged-pull-requests)
2. [New features](#2-new-features)
3. [Bugs fixed](#3-bugs-fixed)
4. [Security](#4-security)
5. [Infrastructure](#5-infrastructure)
6. [Verification](#6-verification)
7. [Not done — read before shipping](#7-not-done--read-before-shipping)
8. [Process findings](#8-process-findings)
9. [Command reference](#9-command-reference)

---

## 1. Merged pull requests

| PR | Merged | Size | Title |
|---|---|---|---|
| [#22](https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/pull/22) | 3 Aug | +5254 / −541, 97 files | feat(mail): transactional email infrastructure and workflow wiring |
| [#23](https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/pull/23) | 10 Aug | +363 / −1, 4 files | ci: add GitHub Actions |
| [#25](https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/pull/25) | 10 Aug | +34 / −1, 4 files | chore: standardize the project on Flutter 3.44.6 |
| [#27](https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/pull/27) | 10 Aug | +1006 / −10, 17 files | Prisma P2028 + server timestamps + chat push suppression |

---

## 2. New features

### 2.1 Transactional email system (#22)

```
MailService  →  BullMQ (Redis)  →  worker EmailProcessor  →  EmailProvider
```

Business logic never touches Resend. Callers name an `EmailType`; the
`EMAIL_PROVIDER` token resolves the vendor. Swapping to SES / SendGrid /
Postmark is **one new class plus one `case`** in `MailModule`'s factory — no
change to `MailService`, the processor, callers, or tests.

**`libs/queue` was implemented for real.** It had been empty scaffolding:
`QUEUE_NAMES` was `{}`, `QueueModule` was `@Module({})`, all 7 processors and
producers were `// TODO` stubs, and BullMQ was not installed. Email is its
first consumer; the other stubs now have a foundation.

BullMQ gets its **own Redis connection**, not the shared cache client. The
cache client sets `maxRetriesPerRequest: 1` so a blip fails an HTTP request
fast; BullMQ workers hold blocking reads and throw unless it is `null`. The two
requirements are incompatible on one client.

**`libs/mail`** — 12 `EmailType`s → 13 Handlebars templates (12 + shared
layout). Table-based, 600px, mobile media queries, inline styles, bulletproof
CTAs, brand colours matching `app_colors.dart`. Plus plaintext alternatives,
retry/backoff, four priority tiers, dedupe keys, and an `EmailLog` audit row
per send.

**Wiring** — all enqueued *after* the DB transaction commits:

| Workflow | Trigger | Behaviour |
|---|---|---|
| Welcome | `ProfileService.finalize()` | once, after every write commits |
| Match found | `InterestsService.respond(accept=true)` | acceptance only — no email on decline |
| New message | `MessagesService.send()` | **offline recipients only** |
| Weekly digest | new `WeeklyDigestCron` | per-week dedupe key; skips members with no candidates |

The new-message email gates on `presence.isOnline` — a value `send()` already
computes, so it costs no extra query. Media messages send no preview: their
content is a signed S3 URL that expires long before the email is read.

The digest also required **activating the scheduler app** — `@nestjs/schedule`
was not installed and all four crons were 2-line stubs.

**Design decisions worth knowing:**

- **`RESEND_API_KEY` is optional**, matching how Firebase and AWS already
  behave here. Without it a no-op provider is bound: queue, worker, render and
  `EmailLog` write all still run; only the HTTP call is skipped. Requiring it
  would block every developer and every CI run on a third-party secret.
- **Quota errors are non-retryable.** `daily_quota_exceeded` resolves over
  hours; the backoff ladder spans ~80s. Retrying burns all 5 attempts to reach
  the same conclusion, so it dead-letters immediately for later replay.
- **Subjects are not HTML-escaped.** A subject is a mail header, not markup —
  escaping turns `O'Brien` into `O&#x27;Brien` in the inbox list. The real
  threat, header injection, is handled by stripping CR/LF.

**Dead-lettering, precisely:** there is **no separate DLQ queue**. Exhausted
jobs live in BullMQ's `failed` set (7-day retention) plus an `EmailLog` row at
status `DEAD_LETTER`. Recoverable, but not a queue.

### 2.2 Chat push suppression (#27)

No push while the recipient has that exact conversation on screen — they are
watching the message arrive over the socket, so a lock-screen buzz is noise.

| Recipient state | Push |
|---|---|
| Viewing the exact conversation | ❌ No |
| Online, another screen | ✅ Yes |
| Online, **another chat** | ✅ Yes |
| App backgrounded | ✅ Yes |
| Offline | ✅ Yes (unchanged) |
| Sender themselves | ❌ Never |

**Scoped to the thread deliberately.** "Online" is far too broad a signal to
suppress a notification: someone browsing Discover, or sitting in a different
conversation, is online and still needs telling.

`ActiveConversationService` is a sibling of `PresenceService`, reusing its
pattern: Redis primary so the decision is correct whichever API instance the
two sockets landed on, with a transparent in-process mirror when Redis is not
ready. **No new table, no new infrastructure** — the state is ephemeral and
belongs with the socket lifecycle.

One entry per device (`deviceKey → conversationId + timestamp`), so switching
threads **replaces** rather than accumulates and the previous conversation
cannot keep swallowing its pushes.

**Entries expire on the same 60s window presence uses.** That is the safety
valve: suppression is the dangerous direction, so a client that crashes or
drops its network inside a chat resumes receiving pushes on its own, with no
cleanup event required. `presence.ping` refreshes the entry, so a member
genuinely sitting in a conversation never ages out. Cleared on **disconnect**,
on **background**, and on **leaving the screen** — three independent paths.

Only the **push** is skipped. The notification row is written inside the send
transaction and is untouched, so the notification centre and unread count stay
correct. Socket delivery, title/body, `truncateForPush(120)`, the `Nenjam`
fallback and sender-device exclusion are all unchanged.

**Known limitation — the decision is user-level, not per-device.** Nothing maps
a socket to an FCM token: `DevicePushToken` keys on `fcmToken`/`platform`,
presence on `socket.id`. So "is ANY device viewing this thread" is the only
question the current schema can answer. Reading on your phone therefore also
stops your tablet buzzing — which matches how messaging apps behave, but it is
a constraint rather than a choice.

---

## 3. Bugs fixed

### 3.1 Prisma P2028 transaction timeout (#27)

Deterministic, not flaky. Opening a fresh connection to the **direct** Neon
endpoint measures **2.4–2.6s**:

```
2575 ms   2415 ms   2473 ms   2471 ms   2428 ms
```

Prisma's default transaction `maxWait` is **2000 ms**, and the pool keeps only
`min: 1` warm — so the moment two requests overlap, the second must open a new
connection and any `$transaction` on that path fails **before the connection is
even ready**. First seen on message send.

Reproduced with the exact pool config against live Neon, 8 concurrent
transactions:

```
maxWait  2000ms  →  0/8 succeeded,  8 × P2028
maxWait 12000ms  →  8/8 succeeded,  0 × P2028
```

Note `0/8`, not `7/8` — under contention even the first transaction fails,
which is why this hit real usage so readily.

Fix: `transactionOptions: { maxWait: 12_000, timeout: 15_000 }`. `maxWait` sits
deliberately **above** the pool's `connectionTimeoutMillis` (10s) so the pool's
own, more specific error surfaces instead of Prisma giving up first.

### 3.2 Two Prisma migration drifts

**`20260724120000_add_user_settings`** — applied to the shared Neon database
from a developer machine and **never committed to any branch**. Consequences:
`prisma migrate dev` demanded a **full reset of the shared database**, and the
auto-generated diff contained `DROP TABLE "user_settings"` (1 live row).

Used `--create-only` and hand-wrote an additive-only migration. The
reconstructed SQL is **byte-identical to the recorded checksum**. Per decision,
the table was adopted into `schema.prisma` rather than dropped.

**`20260803120000_add_chat_message_reply`** — appeared mid-session, applied by
a teammate at 11:12 UTC while this work was in progress. Deliberately left
untouched; "fixing" it would have dropped their column and 2 rows of data. They
later pushed it, and its checksum matched byte-for-byte.

**Two lessons:**

1. **`prisma migrate status` cannot detect a database ahead of the repository.**
   It reported "Database schema is up to date!" in *both* instances. Use
   `migrate diff --from-config-datasource --to-schema`.
2. **The root cause is process, not schema.** Two occurrences in ten days from
   two developers.

### 3.3 UTC timestamp day-bucketing (#27)

The chat fix (`parseServerTime`) had never been applied to four other features
parsing server timestamps with a bare `DateTime.parse`: **Notification Centre,
Interests, Support Tickets, Blocked Users**.

Relative strings ("2 min ago") were always correct — `difference()` works on
absolute instants. The bug is in **day comparisons**: `_isSameDay` reads
`.year/.month/.day`, so east of UTC anything sent between local midnight and
the offset (00:00–05:30 IST) has a UTC date of *yesterday* and files under
"Yesterday".

Reused the existing utility — no second parser introduced. Four out-of-scope
raw parses were deliberately left: `profile.dart` / `profile_draft.dart` `dob`
(user-entered dates), and Psychology `completedAt` / Verification date (**same
bug, different features**).

### 3.4 The API would not boot

`NotificationsModule` was missing `AppConfigModule`, so `EmailDispatchService`
could not resolve `AppConfigService`.

```
UnknownDependenciesException: Nest can't resolve dependencies of the
EmailDispatchService (PrismaService, MailService, ?)
```

**Neither existing gate could catch it.** `nest build` uses
`tsconfig.app.json`, which excludes spec files, and it never constructs the
Nest container. The specs construct services directly with mocks, so they do
not exercise DI either. A green build and 403 passing tests coexisted with an
API that refused to start.

### 3.5 Duplicate `MailModule`

Imported in both `AppModule` and `NotificationsModule`, instantiating it twice.
Measured, not guessed:

```
before:  MailModule x2,  API-owned Redis connections: 5
after:   MailModule x1,  API-owned Redis connections: 4
```

### 3.6 Fail-closed push suppression — found by its own test

A test named *"a lookup failure sends the push"* originally asserted the
opposite. Investigating why revealed the lookup sat **inside** the existing
best-effort `try/catch`, so a Redis error skipped `dispatchPush` entirely and
**silently dropped a real notification** — fail-*closed*, the one direction
this feature must never fail in. The `.catch(() => false)` at the call site is
load-bearing, not defensive noise.

### 3.7 Test isolation, caught by CI's first run

`configuration.spec.ts` asserted `toEqual` on `config.database`/`config.redis`
while never clearing `DATABASE_URL`/`REDIS_URL`. It passed locally only by
luck — jest loads no `.env` and a plain shell exports neither — and would have
broken for **any developer who happened to export `DATABASE_URL`**. Fixed at
the root: `beforeEach` now clears the ambient-sensitive vars.

---

## 4. Security

**`backend/.env.example` — which git tracks — contained live credentials**
(Neon password, Firebase private key, AWS keys, Elasticsearch password). It is
the single `!.env.example` exception in `.gitignore`, so the next `git add -A`
would have published them.

**History audit: all 121 commits, every local and remote branch. No live
credential has ever been committed.** Two apparent hits were false positives —
`.env.example` @ `c504466` contains a literal `CHANGEME` key, and three
`*.spec.ts` use `\nMOCKKEY\n`. One real but low-impact exposure: `backend/.env`
was committed in 5 commits (6–9 Jul) containing `DATABASE_URL`,
`DATABASE_PASSWORD`, `JWT_SECRET` — all pointing at **`localhost`**.

**Added `scripts/git-hooks/pre-commit`** — a dependency-free secret guard,
chosen over gitleaks to avoid pinning a third-party binary. Scans staged
additions only. Two layers: file-level (real env files, service-account JSON,
keys/keystores — covering the `git add -f` and tracked-before-ignored gaps
`.gitignore` cannot) and content-level (AWS keys, PEM keys with real material,
DB/Redis URLs with inline passwords, Google API keys, GitHub/Stripe/Slack
tokens, JWTs).

Exempts placeholders and public-by-design Firebase client config. Patterns
target structured, high-entropy credentials on purpose — a rule that fires on
the word "password" trains people to reflexively `--no-verify`.

**It has since blocked commits twice, correctly both times**, and each was
fixed by tuning the rule rather than bypassing it.

---

## 5. Infrastructure

### 5.1 CI (#23) — the repo had none

Every check was previously run by hand. Three real defects reached `main` as a
direct result (§3.4, §3.7, and the `ChatMessage` fixture break).

Backend job runs against real `postgres:16` and `redis:7` services:

| Step | Catches |
|---|---|
| `migrate deploy` | replays all 19 migrations onto an **empty** database |
| `migrate diff` | schema ↔ migration-history disagreement |
| `tsc --noEmit` | spec-file type errors |
| `test` | jest |
| `build:all` | all four apps |
| **smoke boot** | an app that builds but will not start |
| `lint` | non-blocking — 38 pre-existing errors |

**No repository secrets required.** Firebase, AWS and `RESEND_API_KEY` are
deliberately absent; their absence is part of what CI proves.

**The migration replay produced new information.** Nothing had ever tested
it — Neon was built incrementally and never rebuilt from zero. A fresh replay
produces a schema structurally identical to the shared instance: **36 tables,
139 indexes, 23 enums**.

`backend/scripts/smoke-boot.mjs` is standalone and cross-platform, runnable
locally after `pnpm build:all`. **Verified in both directions** — it passes on a
healthy tree, and against a deliberately reintroduced `AppConfigModule`
removal it failed with exit 1, naming the API and the exact DI error.

### 5.2 Flutter version standardization (#25)

CI had been moved to Flutter 3.35.3 while local development was on 3.44.6 —
inverting the point of the gate. The divergence had already cost four commits:
`CupertinoPageTransitionsBuilder` is re-exported by `material.dart` on 3.35.x
but only by `cupertino.dart` on 3.44.x.

**Nothing pinned the Flutter version anywhere** — no `.fvmrc`, no
`.tool-versions`, no `environment.flutter`, no README mention.

Pinned in three places at different strengths: a **tool-enforced floor** in
`pubspec.yaml` (`flutter: ">=3.44.6"`), the **exact version** in CI, and the
**why** in the README. Verified enforced by temporarily setting an impossible
floor — `flutter pub get` fails with a clear version-solving error.

---

## 6. Verification

All figures are actual command output, not estimates.

```
Backend tests    51 suites · 453 total · 441 passed · 12 todo · 0 failed
                 (session start: 42 suites · 299 tests)
TypeScript       tsc --noEmit  exit 0
Smoke boot       api · worker · scheduler · websocket  all OK
Prisma           19 folders = 19 applied · 0 pending · 0 orphaned
                 0 checksum mismatches · migrate diff "No difference detected"
Flutter analyze  exit 0 · 5 pre-existing deprecation infos
CI               green on main
```

**External services, verified by real round-trips:** Neon PostgreSQL 18.4,
Redis Cloud (PING + SET/GET/DEL), Firebase Admin (service account
authenticated against Google), AWS S3 (bucket + upload + presigned GET 200 +
delete). Elasticsearch fails — no local cluster — and degrades gracefully in
development by design.

**Real email delivery confirmed.** OTP and Welcome sent through Resend with
genuine message ids, `EmailLog` rows at `status=SENT, provider=resend`. The
provider abstraction was proven in both directions: with a deliberately invalid
key, the error was classified **non-retryable** and dead-lettered on attempt 1
of 5 rather than burning all five. Logs showed `qa*****@example.com` — the
recipient masked, the key never printed.

---

## 7. Not done — read before shipping

### 7.1 Blocking for email reaching real users

**1. `MAIL_FROM` is still `onboarding@resend.dev`.** That address only delivers
to the Resend account owner (`nenjammatrimony@gmail.com`). **Every wired
workflow will dead-letter for every real member** — welcome, match-found,
new-message, weekly digest — with clean logs and correct errors, and nobody
receiving anything.

Fix: verify a domain at resend.com/domains, then update `MAIL_FROM` in
`backend/.env`.

**2. Redis eviction policy is `volatile-lru`; it should be `noeviction`.**
BullMQ warns on every connect. Under memory pressure Redis can silently evict
queued jobs — an OTP would simply vanish. Infrastructure change, not code.

### 7.2 Unverified

**Chat push suppression has no on-device test.** Automated coverage is
thorough (all ten required cases plus staleness, heartbeat refresh,
multi-device and member isolation), but no Android device or emulator is
attached, so the two-account end-to-end path is genuinely unverified on a
handset.

### 7.3 Built but unwired — needs product decisions

Four email workflows are implemented and tested but have no trigger point,
because the features they would hook into do not exist:

| Workflow | Blocked on |
|---|---|
| OTP, forgot-password, verify-email | Firebase owns auth entirely; the backend has zero code. Wiring our own would create a **second competing auth path**. |
| Subscription / payment emails | Razorpay integration — `checkout.service.ts`, `razorpay.service.ts`, `razorpay-webhook.controller.ts` are 4 lines each |
| Profile viewed | Nothing anywhere writes `ProfileView` — needs view tracking built |

### 7.4 Pre-existing, untouched

- **38 ESLint errors.** Repo-wide lint is **not green**. Zero are in files
  changed by this work. Mostly `@typescript-eslint` rules that `--fix` cannot
  resolve.
- **13 Flutter test failures**, all in `profile_detail_scroll_diagnostic_test.dart`
  and `tab_bar_scroll_reset_test.dart`, every one a `TimeoutException after
  0:10:00`. These are **hangs, not compile errors** — a distinction that
  matters, since a hanging suite costs 130 minutes and cannot run in CI.
- Psychology `completedAt` and Verification date still use raw timestamp parsing.
- Neon remains on the **direct** endpoint. A `-pooler` migration would remove
  the per-connection handshake cost entirely, but needs a PgBouncer
  compatibility review (prepared statements, session state).
- Kotlin 2.1.0 loses Flutter support soon — bump to ≥ 2.2.20.
- Two junk files tracked at repo root (`-server`, one mojibake-named).
- Windows Developer Mode is off — blocks the Flutter **desktop** target only.

### 7.5 Requested, not started

**Live unread badge** (red count on the Messages tab, updating over the
existing socket). Requested but not begun.

---

## 8. Process findings

**`prisma migrate status` has a blind spot.** It cannot detect a database ahead
of the repository — it only looks for unapplied local folders. It reported "up
to date" during *both* drift incidents. `migrate diff` is now a CI gate.

**`nest build` excludes spec files and never runs DI.** Two type errors and a
DI failure reached `main` through a green build. `tsc --noEmit` and smoke boot
are now CI gates.

**`flutter analyze` exits 1 on infos.** Its output can read entirely clean —
"5 issues found", zero errors, zero warnings — while the command still fails.
Read severities, not the exit code.

**PR #27 was merged 9 seconds after opening**, so CI did not gate it. It passed
afterwards, but that was luck rather than process. A branch-protection rule
requiring checks would make it safe by default.

---

## 9. Command reference

```bash
# Backend
cd backend
pnpm install
pnpm start:dev              # API
pnpm start:worker           # worker — consumes the email queue
pnpm start:scheduler        # scheduler — weekly digest cron
pnpm test
pnpm verify:email <addr>    # end-to-end email pipeline check
node scripts/smoke-boot.mjs # after pnpm build:all — boots all four apps

# Prisma
pnpm prisma:migrate:status
pnpm prisma:migrate:deploy                       # safe; never resets
npx prisma migrate diff --from-config-datasource \
    --to-schema libs/database/prisma/schema.prisma   # the real drift check

# Secret guard (automatic via backend's `prepare`)
git config core.hooksPath scripts/git-hooks

# Frontend — Flutter 3.44.6 required
cd Frontend && flutter pub get && flutter run
flutter analyze --no-fatal-infos
```

### Switching Resend → AWS SES

Three steps; nothing above the interface changes:

1. Write `SesEmailProvider implements EmailProvider` — one method. Map
   `ThrottlingException`/`ServiceUnavailable` to `retryable: true`;
   `MessageRejected`/`MailFromDomainNotVerified` to `false`.
2. Add `case 'ses':` to the factory in `libs/mail/src/mail.module.ts` and widen
   the `provider` union in `configuration.ts`.
3. Set the env var.

`MailService`, `EmailQueue`, `EmailProcessor`, every caller, every template and
every test are untouched. `EmailLog.provider` is a plain string precisely so
this needs no migration.
