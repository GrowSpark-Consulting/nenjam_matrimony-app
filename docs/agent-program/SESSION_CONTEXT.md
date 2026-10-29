# SESSION_CONTEXT — read this first (for Claude Code)

Audience: the next Claude Code session working on the Nenjam Agent / Partner
Program backend for Ishu. Read this, then `CLAUDE.md`, then continue without
asking Ishu to repeat anything below. Updated 29 Oct 2026 (evening);
`origin/main` was `930626e` (PR #160). Re-verify anything load-bearing against the code —
things move. Statements marked **To be confirmed** could not be checked from
git (GitHub, Render, Neon, Vercel and what other people told Ishu are not
visible there); statements marked **(per Ishu)** or **(per Shaaz)** are what
they said, and are not proven by this repository.

---

## 1. The project in brief

1. Nenjam Matrimony: Flutter app + NestJS pnpm monorepo (`backend/`), Prisma, shared Neon Postgres.
2. Deployed on **Render**: one Free web service on branch `main`, auto-deploys; no worker, scheduler or confirmed Redis (per Ishu; **To be confirmed** — not visible from git). `backend/railway.toml` still exists but is stale.
3. Ishu owns the **Agent / Partner Program backend**: agents, sign-in, applications, NM codes, attribution, commission, payouts.
4. Shaaz owns admin RBAC and audit, `PlatformSetting` + settings service, admin TOTP, the OTP service, `hashIdentifier`, `SecretSealer`, subscriptions, payments, the admin dashboard and the admin web app. Most of his platform work is now **on `main`** (section 6).
5. Dhatri owns Flutter and the Agent Portal website. Never touch frontend code.
6. Agents are not members: own phone + OTP sign-in (purpose `AGENT_SIGN_IN`), own access token (HS256, its own secret `AGENT_JWT_SECRET`), rotating refresh token.
7. Raja's numbers: 10% commission, 14-day hold, 60-day credit window, Rs. 500 minimum payout, 5% first-plan discount, 10 client drafts, PAN before first payout — all settings or policy, never constants.
8. **What is live:** `AgentsModule` is imported in `app.module.ts` (#158) and serves only the staff routes `GET /admin/agents/summary`, `GET /admin/agents`, `GET /admin/agents/:id`, `POST /admin/agents/:id/approve`, `POST /admin/agents/:id/reject`. **No agent-facing or member-facing agent route exists on `main`**: the Agent Portal still gets a 404 on every `/agent/*` call.
9. **Update 29 Oct ~20:00 (per Shaaz, via Ishu):** production has **40 migrations applied**, no drift: #155's `20261029110000_agent_commission_tables` and `20261029110100_agent_commission_policy_seed` (policy v1: 1000 bps, 14-day hold; TRUNCATE and append-only triggers present) and Shaaz's `20261029130000_payment_referral_gst`. **#155 (`ba28426`) and #159 Payments (`c6175d4`) are merged**; `origin/main` has 40 migration folders. **Those two #155 migrations must never change.** The agent settings seed (`feat/agent-settings-seed`: `20261029110200`, `20261029110300`) is NOT merged or applied.
10. The contract is `docs/agent-program/agent-api.openapi.yaml`; the admin contract is `docs/agent-program/agent-admin-api.openapi.yaml`.
11. **Agent Portal** (Dhatri's React + Vite site): live at **https://agent-nenjam-matrimony-app.vercel.app** on **mock data**; that origin is in `CORS_ORIGINS` on Render (per Ishu; **To be confirmed**). The custom domain `agent.nenjammatrimony.com` is planned and not set up. Her CI Flutter check is red on `main` (a `referral_backend_mode` test from #142; not ours).
12. **Admin web Agents page** (Shaaz, #160) is merged and **not deployed yet**: Vercel's free-plan limit, resets around 12:05 UTC on 30 Oct (per Ishu; **To be confirmed**).
13. **A member with no verified phone can never be credited to an agent** (`referral_attributions.phone_hash` is NOT NULL), from any source, including a code entered at payment. `quoteReferral` returns no discount with `rejectedReason: PHONE_NOT_VERIFIED` and payment goes on.

---

## 2. Standing rules

- **Backend only.** Never edit frontend (`Frontend/`, the portal) or Shaaz's files (for example `libs/config/src/validation.ts`, `modules/platform/`, `modules/admin/`, `modules/subscription/`, `libs/common/src/crypto/`). If they need a change, write Ishu a message for that person.
- **Push only the branches Ishu names** (in the prompt). You may **commit yourself**. Plain pushes only, always as `git push -u origin <branch>:<branch>`; never force-push, never merge, never push to `main`, never delete branches. Permission is per task; it does not carry over.
- **No reviewers on normal PRs.** Only a Draft PR gets a reviewer (today: #155, Shaaz). **Ishu merges their own PRs** once CI passes. There is no `gh` CLI: give a compare link and a pasteable title and description; Ishu opens the PR.
- **Merging to `main` deploys to the live Render site.** After every merge, check that the deploy is **Live** (Render dashboard; not visible from git).
- `git fetch --all` first; branch from **`origin/main`** (not local `main`). `git switch -c X origin/main` sets the upstream to `origin/main`: run `git branch --unset-upstream` right after, so no bare `git push` can ever target `main`. Run `git branch --show-current` before every commit (trap 17).
- **Before every batch and every push:** `git fetch --all`, then tell Ishu what changed on `origin/main` and on Shaaz's and Dhatri's branches, and what it means.
- **Each batch of steps = ONE branch, one commit per step, ONE pull request**, unless Ishu says otherwise.
- Small, surgical diffs. Match existing style (see `CLAUDE.md`).
- **No new dependency** without asking Ishu. Node built-ins are fine.
- Business values (rates, windows, hold days, limits, flags, token lifetimes) are **parameters or settings, never constants**, and never defaulted in code.
- Pending business rules live in **one clearly marked place** (`PENDING DECISION (Raja)` comment).
- **Never run any Prisma command against a remote or shared database**, and never with the repo's `prisma.config.ts`. See traps 1 and 2. Use a throwaway local Postgres, print the masked URL before every Prisma command.
- **No migrations or schema edits without approval.** Applying a migration to Neon is Shaaz's production window, approved by Ishu (nothing runs `prisma migrate deploy` on Render). **A migration that has been applied anywhere must never change** (Prisma checksums).
- Never print or store secrets, environment values, real phone numbers, emails, PAN or bank details. Use only the approved fake test values (trap 14).
- Mutation checks use a script that **refuses a mutation whose pattern does not match** (trap 15).
- Verify claims against code on `origin/main`; write "To be confirmed" rather than guess. `CLAUDE.md`, `BRAIN.md` and `PROJECT_RULES.md` have known stale parts.

**Checks for every step** (from `backend/`), and say honestly what was not run:

```
npx tsc --noEmit
pnpm test
AGENT_PRISMA_TEST_DATABASE_URL=postgresql://postgres@127.0.0.1:55432/<throwaway db> pnpm test:agent-db
pnpm build:all
node scripts/smoke-boot.mjs
npx eslint apps/api/src/modules/agents apps/api/src/app.module.ts
```

Also run the new spec alone (`npx jest <spec path>`) to count new tests, and
confirm the full-suite total rose by that count.

---

## 3. Where everything is

| What | Where |
|---|---|
| Agent-program code | `backend/apps/api/src/modules/agents/{adapters,admin,agent,application,auth,commission,config,content,crypto,errors,payout,ports,referral,settings,testing}/` |
| The module | `agents/agents.module.ts` (admin routes only on `main`) |
| Quote token for checkout | `agents/agent-referral-quote.token.ts` (`AGENT_REFERRAL_QUOTE`, type `AgentReferralQuote`) |
| API contract | `docs/agent-program/agent-api.openapi.yaml` |
| Admin contract | `docs/agent-program/agent-admin-api.openapi.yaml` |
| Shared handoff | `docs/agent-program/HANDOFF_SHAAZ_AND_DHATRI.md` |
| Frontend handoff | `docs/agent-program/FRONTEND_HANDOFF_DHATRI.md` |
| Prisma DB-test notes | `docs/agent-program/agent-prisma-db-tests.md` (`pnpm test:agent-db`, config `apps/api/test/jest-agent-db.json`) |
| Schema | `backend/libs/database/prisma/schema.prisma` |
| Shaaz's platform services | `apps/api/src/modules/platform/` (`PlatformSettingsService`, `IdentifierHashService`, `OtpService`) |
| Shaaz's admin RBAC/audit | `apps/api/src/modules/admin/` (`assertAdminPermission`, `AdminAuditService`, `@AdminController`, `@RequirePermissions`, `hasFreshStepUp`) |
| Shared contracts | `libs/common/src/contracts/referral-events.ts`, `libs/common/src/crypto/secret-sealer.ts`, `libs/common/src/pipes/validation-failed.ts` |
| Dummy OTP policy (members) | `backend/libs/common/src/auth/dev-auth.ts`, `POST /auth/dummy-otp/session` |
| Remote | `https://github.com/GrowSpark-Consulting/nenjam_matrimony-app.git` |

---

## 4. State on 29 Oct (evening)

### Merged since the last version (from `git log --merges d4e6291..origin/main`)

| PR | Branch | What |
|---|---|---|
| #116 | `feat/agent-phase1-migration` | Phase 1 agent tables, migration `20261028095916_agent_program_phase1` |
| #129 | `feat/admin-rbac-foundation` | Shaaz: RBAC, staff TOTP, audit; `20261029053600_admin_rbac_foundation`, `20261029053700_plan_drafts` |
| #140 | `docs/agent-admin-contract-fixes` | Shaaz's review fixes to the admin contract |
| #143 | `feat/agent-review-flag-and-doc-fixes` | self-referral kept as REJECTED sets `needsReview` |
| #144 | `docs/agent-raja-decisions-28oct-pm` | Raja's 28 Oct evening decisions |
| #145, #152 | `docs/agent-admin-contract-payer`, `-payee` | payout responses carry the payee; destination only with step-up |
| #146 | `feat/agent-portal-apply-again` | Dhatri: portal re-apply |
| #147, #149 | `fix/referral-live-test-api-client` | Dhatri: referral live test client |
| #148 | `feat/referral-events-contract` | Shaaz: `referral-events.ts` (GST exclusive) |
| #150 | `feat/platform-foundation` | Shaaz: settings, hashing, OTP, `VALIDATION_FAILED`; `20261029100000_platform_foundation` |
| #151 | `docs/agent-raja-and-migration-names` | Raja's 29 Oct answers, corrected migration names |
| #153, #154 | `feat/agent-prisma-core-adapters`, `feat/agent-prisma-attribution-and-stores` | the Prisma adapters for every Phase 1 port |
| #158 | `feat/agent-admin-routes-approval` | PR A: `AgentsModule` + the five admin agent routes |
| #160 | `feat/admin-web-agents` | Shaaz: admin web Agents page (not deployed, see section 1) |

### #155 (merged 29 Oct evening) and the stack on it

- **#155** (MERGED as `ba28426` after Shaaz's production window), branch `feat/agent-commission-tables`, head **`5896821`**: migrations `20261029110000_agent_commission_tables` (TRUNCATE triggers on every money table; partial-refund columns `refunded_paise`, `pre_refund_amount_paise` and `commissions_refund_chk`) and `20261029110100_agent_commission_policy_seed`. **The SQL is FINAL.** It is **not applied anywhere and not merged**: Shaaz runs the production window, tells Ishu, then Ishu merges #155. After the window the SQL must never change.
- Stacked on it: `feat/agent-commission-services` (`a85c69e`), `feat/agent-admin-services` (`e2e0717`), `fix/agent-gst-exclusive` (`3df4e62`), `fix/agent-partial-refund-proportional` (`328541e`). **Merge order after #155:** services, admin-services, gst-exclusive, partial-refund.
- The stack adds `AgentPermissionPort.has()` (and its adapter and fake), the commission/payout services, `runDailyApproval()`, the partial-refund rule and the runbook for pepper rotation (its own copy of this file has a section 8b; when it merges, take this version and re-add 8b).

### What is on `main` under `modules/agents/`

- **Ports** (`ports/`), **fakes** (`testing/`), **pure rules** and the **services** (sign-in, application, me, config, referral list, code validate/attach, quote) — as described in the previous version of this file.
- **Prisma adapters** (`adapters/prisma/`, #153/#154) for every Phase 1 port, the unit of work, bounded purge, unique-violation mapping, and a DB-gated test suite.
- **Platform adapters** (`adapters/admin/agent-admin-platform.adapters.ts`, #158): `AdminPermissionAdapter` (`assert` only on `main`), `AdminAuditAdapter`, `IdentifierHashAdapter`, `SystemClock`. **No settings adapter and no OTP adapter yet.**
- **Admin** (`admin/`, #158): `AgentAdminAgentsService`, `AgentAdminController`, DTOs, an error filter.
- `AesGcmSecretSealer` (`crypto/`) is still our sealer; Shaaz's `SecretSealer` is on `main` (`libs/common/src/crypto/secret-sealer.ts`) and the switch is not done yet.
- `AGENT_REFERRAL_QUOTE` is **declared but not provided**: the module provides nothing under it, so checkout (when Shaaz's Payments PR lands) charges the list price.

### The 18 settings keys (no defaults in code)

**Decided — seed these** (Ishu, 29 Oct): `commission.auto_approve` true, `commission.require_verified_profile` false, `referral.credit_window_days` 60, `referral.member_discount_bps` 500, `referral.discount_stacks_with_coupons` false, `referral.discount_only_in_credit_window` true, `payout.minimum_amount_paise` 50000, `agent.client_draft_limit` 10, `agent.payout_details_wait_hours` 72, `commission.base` `"AMOUNT_PAID_EXCLUDING_GST"`, `commission.base_provisional` false, `payout.tax_withholding` `null` (only if our parser accepts `null` as "not set").

**Undecided — a SEPARATE migration with proposed values, for Ishu's approval:** `agent.access_token_ttl_seconds`, `agent.refresh_token_ttl_seconds`, `agent.otp_resend_after_seconds` (at least 30, Shaaz's OTP floor), `referral.code_validation_ip_limit`, `referral.code_validation_code_limit`, `referral.code_validation_window_seconds`.

**Seed format** (Shaaz's table `platform_settings`): `INSERT INTO "platform_settings" ("key", "value", "description") VALUES ('commission.auto_approve', 'true'::jsonb, '...') ON CONFLICT ("key") DO NOTHING;` — `value` is JSONB NOT NULL (undecided = `'null'::jsonb`, never SQL NULL; numbers `'72'::jsonb`; strings `'"TEXT"'::jsonb`); keys match `^[a-z]+(\.[a-z_]+)+$`; version and timestamps have defaults. **The seed is its own PR after #155, with a timestamp later than `20261029110100`, and must never reach production before #155's migrations.** Shaaz's Payments migration is `20261029130000_payment_referral_gst` (on his branch); pick timestamps that do not collide with it.

---

## 5. Decisions, and what is still open

### Decided (29 Oct)

- **GST is ADDED to prices** (prices exclusive of GST). The company is **not registered for GST yet**, so `payment.gst_rate_bps` (Shaaz's setting, seeded `0` in his Payments migration — verified on `origin/feat/payments-referral-gst`) stays `0` until registration; then a Super Admin sets it (commonly 1800).
- **The commission is 10% of `taxableAmountPaise`.** `quoteReferral` returns `taxableAfterDiscountPaise` (on `main`, `9d05d7f`). `PaymentSucceeded.amountPaidPaise` = taxable + tax (`referral-events.ts`, #148: `addExclusiveTax`, `refundTaxPaise`, `ReferralEventPublisher`, `REFERRAL_EVENT_PUBLISHER`).
- **Prices are not final** and live in Shaaz's plan data (changed through admin drafts, no deploy). Each payment stores its own numbers.
- **A partial refund before approval reduces the commission in proportion**; a full refund cancels it (on the stack, `fix/agent-partial-refund-proportional`).
- **No separate agent KYC** (the PAN is enough). **A rejected agent may re-apply.** **A terminated agent's waiting commission stays frozen.**
- **Roles live** (seeded in `20261029053600_admin_rbac_foundation`, verified): `SUPER_ADMIN` (Raja plus one more, per Ishu), `PARTNER_MANAGER` (`agent.view`, `agent.approve`), `PAYOUT_MANAGER` (`payout.view`, `payout.execute`, step-up).
- The **support contact** for the portal's Help screen was supplied by Raja and lives **only in Dhatri's portal config**, never in this repo.

### Shaaz's design answers (29 Oct; per Shaaz unless noted)

- **Payments PR** (draft 29 Oct evening, ready 30 Oct; branch `feat/payments-referral-gst`, **merged as #159**): payment fields; checkout calls our `quoteReferral` through `AGENT_REFERRAL_QUOTE`, **imported from our file** `modules/agents/agent-referral-quote.token.ts`, injected `@Optional()`. **It must be provided from a `@Global()` module** (SubscriptionModule cannot import AgentsModule: AgentsModule → AdminModule → SubscriptionModule; verified in his commit `c3d7d79`). Without it checkout charges the list price and a typed code gets 422 `PROMO_CODES_UNAVAILABLE`.
- Payment events go through an **outbox** with in-process delivery after commit (at-least-once); our handlers are idempotent by `paymentId` and `refundId`.
- A **daily GitHub Actions job** calls `POST /internal/jobs/daily` (header with `JOBS_SECRET`), which runs his outbox sweep and then our `runDailyApproval()`. It must **catch up**: approve everything past `hold_until` (test a two-day gap). Not in git yet (**To be confirmed** when it lands).
- **Sealer:** `SecretSealer(key: Buffer, purpose)` from `@app/common` with `parseSealingKey(process.env.AGENT_PII_ENCRYPTION_KEY, 'AGENT_PII_ENCRYPTION_KEY')` (returns `Buffer | null`; throws if malformed) — both on `main`, verified. Purposes `agent.pan`, `agent.payout_details`, `agent.applicant_phone`. A **missing** key means 503 on the agent PII routes plus a startup warning (never refuse to start); a **malformed** key stops startup. `AGENT_PII_ENCRYPTION_KEY` is **not** in `libs/config/src/validation.ts` on `main` (that file is Shaaz's).
- **Dummy OTP** (verified in `validation.ts` and `OtpService`): `AGENT_OTP_DUMMY_ENABLED`, `AGENT_OTP_DUMMY_PHONES` (comma-separated E.164), `AGENT_OTP_DUMMY_CODE` (exactly 6 digits). Set CODE and PHONES first and ENABLED last: enabling without a code, or in production without an allow-list, fails Joi and **stops the whole API**. `OtpService` has a 30-second resend floor of its own, so `agent.otp_resend_after_seconds` must be at least 30.
- **Admin routes:** `@AdminController` + `@RequirePermissions` (every route must declare one, or `AdminRouteCheck` stops the API), `@CurrentAdmin`, `@AdminContext`, `hasFreshStepUp(admin)`, `AdminAuditService.record(tx, entry)`, `assertAdminPermission(tx, userId, key)`. The **payout destination** is included only with `payout.execute` AND a fresh step-up; otherwise it is omitted, the answer is still 200, and no audit row is written.

### Open questions (do NOT build around them)

- **Real OTP** will use Firebase pay-as-you-go (not bought yet). Ishu asked Shaaz whether agents use his `OtpService` or Firebase ID tokens: **build no Firebase-specific agent sign-in.**
- GST registration and final prices wait for Raja. TDS (the CA). How an agent pays for a client's plan. Tamil wording for the other labels. The referral link web address. Where scheduled jobs run beyond Shaaz's daily job. How migrations get applied on Render (Shaaz's manual window today).

### Secrets (never ask for them, never print them)

`AGENT_PII_ENCRYPTION_KEY`, `AGENT_JWT_SECRET` and the dummy-OTP values are generated or chosen by Ishu and kept in Ishu's password manager. **None of them is on Render yet** (per Ishu). `IDENTIFIER_HASH_PEPPERS` on Render: **To be confirmed**.

### Marked pending-decision places in the code

| Decision | Place |
|---|---|
| Tax withholding (CA) | `planPayout()` in `payout/plan-payout.ts` refuses any set value with `TAX_RULE_UNSUPPORTED` — **must change when the CA answers** |
| Tamil labels | `AGENT_TAMIL_LABEL_PENDING` in `content/agent-content.ts` |

(Re-apply, frozen commission, commission base and partial refund are decided; see above.)

---

## 6. Shaaz's work on `main` (verified)

- `PlatformSettingsService.getMany(keys)` (only keys that exist, JSON `null` is a value) and `registerValidator(key, fn)` (one validator per key; `fn(value)` returns a problem string or `null`; refused values answer 400 `VALIDATION_FAILED` at admin entry).
- `IdentifierHashService.hashIdentifier` / `hashIdentifierAll`, kinds `PHONE`, `EMAIL`, `PAN`, `IP`; **503 `IDENTIFIER_HASHING_UNAVAILABLE`** until `IDENTIFIER_HASH_PEPPERS` is set; **RangeError** for an empty or malformed value.
- `OtpService.send(purpose, phoneE164)` / `verify(purpose, challengeId, code)`, purpose `AGENT_SIGN_IN`; `OtpRateLimitError.retryAfterSeconds`; **503 `OTP_DELIVERY_UNAVAILABLE`** (`OtpDeliveryUnavailableError`, a Nest `ServiceUnavailableException`) when no code can reach the phone; RangeError for a non-E.164 phone.
- `validationFailed` in `@app/common` (`libs/common/src/pipes/validation-failed.ts`).
- `SecretSealer` and `parseSealingKey` in `@app/common`.
- `referral-events.ts` (#148), see section 5.

---

## 7. Next steps, in order (Ishu's 29 Oct evening prompt)

0. This file (`docs/agent-session-context-29oct-pm`).
1. `feat/agent-platform-adapters`: settings (validators registered in `onModuleInit`), OTP, hashing, permission with `has()`, audit adapters; the settings seed after #155.
2. `feat/agent-routes-flagged` (stacked on 1): the agent and member routes, registered only when `AGENT_PROGRAM_ENABLED=true`; provide `AGENT_REFERRAL_QUOTE` from a `@Global()` module.
3. `feat/agent-sealer-switch` (from `main`): Shaaz's `SecretSealer` replaces `AesGcmSecretSealer`.
4. `feat/agent-admin-routes-rest` (stacked on the commission stack): the remaining admin routes.
5. `docs/agent-contract-conformance`: a route-vs-contract check.
6. `docs/agent-golive-runbook`: the go-live order and checks.

---

## 8. Known traps

1. **`backend/prisma.config.ts` loads `.env.local` with `override: true`.** A `DATABASE_URL` set in the shell is silently replaced. **Never run Prisma with the repo config.** Use a guarded wrapper (trap 2).
2. **Throwaway Postgres procedure.** PostgreSQL 17 is at `C:\Program Files\PostgreSQL\17\bin`; a Windows service already runs on port **5432** — do not touch it. Run the throwaway cluster on **55432** (`initdb -D <dir> -U postgres -A trust -E UTF8 --locale=C`; `pg_ctl ... -o "-p 55432 -c listen_addresses=127.0.0.1" -l <log> -w start`, in the background). Use a **wrapper** (`guarded-prisma.cjs`) that builds `postgresql://postgres@127.0.0.1:55432/<db>`, refuses any non-local host, prints the masked URL, allows only `validate`, `format`, `generate`, `migrate deploy|dev|diff|status`, passes a minimal environment, and uses a **scratch config** (`prisma.scratch.config.cjs`: no `.env`, throws on a non-local host) via `--config`. The helper scripts live in **`D:\claude-scripts\`** (outside the repo; see its README): `guarded-prisma.cjs`, `prisma.scratch.config.cjs`, `smoke-local.sh`, `checkhere.sh`, `checkall.sh`, `mutate-fast.cjs`, `verify155.sh`, `sqlmut155.sh`. Read and verify them before use. CI uses `postgres:16`; keep SQL portable. CI's drift check passes only if the output contains **"No difference detected"**.
3. **Generated Prisma client is gitignored** (`backend/libs/database/generated/`). Regenerate locally after a schema change so `tsc` passes; don't commit it.
4. **`CLAUDE.md` says Railway**; deployment is Render.
5. **`git diff a..b` vs `a...b`**: use three-dot for "what this branch adds".
6. **Prettier reformats files** after you write them; re-read before editing.
7. **ESLint** (typed rules) flags `Object.prototype.hasOwnProperty.call` returns, unnecessary type assertions, trailing unused parameters and `expect.any(...)` assignments. New code must lint clean.
8. **Make your commit step stop on `tsc` failure too**, not just ESLint.
9. Prefer the Write tool for file contents over heredocs.
10. **No `python`, no `gh` CLI.** Use node for scripts; give compare links. `git show origin/main:path` needs `MSYS_NO_PATHCONV=1` in Git Bash.
11. Shell is Windows (Git Bash and PowerShell). Paths: `/d/nenjam_matrimony-app` in bash.
12. `referral.discount_stacks_with_coupons` exists but there is **no coupon feature**. Seed it `false`; don't use it.
13. `POST /agent/devices` only accepts `ANDROID`/`IOS` — the website portal has no push yet.
14. **Approved fake test values:** `+919876543210`, `+919000000001`, `+919000000002`, `+919999999999`, `ABCDE1234F`, `AAAAA1111A`, `HDFC0001234`, `ravi@okbank`, `NM7K2P9X`. Nothing else that looks real.
15. **Mutation checks must use a script that refuses a mutation whose pattern does not match** (`mutate-fast.cjs`: absent or non-unique pattern stops the run). Compare a surviving mutant with an equivalent one before adding a test.
16. **`prisma format` reformats Shaaz's models.** Restore everything outside the agent section byte-for-byte. Prisma 7 `migrate dev` no longer accepts `--skip-generate` / `--skip-seed`.
17. **Check `git branch --show-current` before a merge or commit.** `git checkout -b X` fails if a local `X` exists and the next command runs on the wrong branch.
18. **Nothing runs `prisma migrate deploy` on Render.** A merged migration is not applied until Shaaz's window.
19. Applicants have **no refresh token**. HTTP mappings for refusals are in the service header comments.
20. A **PR's GitHub title and Draft state are not in git**; take them from Ishu.
21. **`git switch -c X origin/main` tracks `origin/main`.** Unset the upstream immediately (section 2).
22. **`backend/scripts/smoke-boot.mjs` boots the built apps in the CURRENT folder, so they load `backend/.env.local` and can reach the REMOTE (Neon) database** (it happened once on 29 Oct; the connection failed, nothing was read or written). Never run it from `backend/`. Always use `D:\claude-scripts\smoke-local.sh <local db>`: it runs from an empty folder (`D:\claude-scripts\smoke-root`, junctions to `dist` and `node_modules` only, no `.env` file) with a cleared environment pointed only at the local throwaway database. The same holds for any `node dist/...` run. **Never print or store a connection string**; mask it (`postgresql://***@127.0.0.1:55432/<db>`).
23. Specs that import `@app/config` need CI's dummy environment (`ELASTICSEARCH_NODE`, `SMTP_HOST`, `SMTP_PORT`, `JWT_SECRET`, local `DATABASE_URL` / `REDIS_URL`) when run outside the main checkout (a worktree has no `.env.local`).

---

## 9. Report format Ishu expects

After each batch:

1. A table: branch, commit, new tests, results (tsc, pnpm test totals, agent-db tests, build:all, smoke boot, ESLint).
2. Extra choices made that were not specified.
3. Decisions to confirm (who: Raja, Shaaz, CA, Dhatri).
4. Honest limits: what was not run or not verified, and any mutation checks (what was broken, whether it was caught).

**PR description format** (one per batch), plus the compare link
`https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/compare/main...<branch>?expand=1`
(for a stacked branch, compare against its base branch):

- **Title**
- **What** (one short section per step)
- **Why** — cite real sections: Final Build Spec §2 (decisions), §3 (rules), §4 (flexibility), §5 workflows A–F; and Final Plan sections (e.g. §13 Safeguards)
- **Files**
- **Tests** — exact commands and results; say what was not run; number of new tests
- **Risk** (adjust to what is true)
- **Decisions to confirm**
- **Not included**
- End each PR description with the attribution line your Claude Code setup requires.

**Before any push** (only the branches Ishu names): `git remote -v`; `git fetch --all`; `git log --oneline <base>..<branch>`; `git diff --stat <base>...<branch>`; dry-run merge (`git merge-tree --write-tree origin/main <branch>`); secret scan of added lines (keys, tokens, connection strings, emails, phone numbers, PAN); confirm nothing from the scratchpad is included. If `origin/main` moved, merge it into the branch with a regular merge (no rebase, no force) and rerun the checks.

Ishu likes plain language and copy-paste-ready output.

---

## 10. First thing to do next session

1. `git fetch --all`; check what merged (`git log --merges origin/main`), whether #155 and its stack are merged, and whether Shaaz's Payments PR (`feat/payments-referral-gst`) and the daily job (`/internal/jobs/daily`) are on `main`.
2. Check the state of the branches in section 7 (local and remote) and continue from the last commit of any unfinished one.
3. Ask Ishu which step to start and wait.
