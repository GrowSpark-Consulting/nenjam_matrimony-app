# SESSION_CONTEXT — read this first (for Claude Code)

Audience: the next Claude Code session working on the Nenjam Agent / Partner
Program backend for Ishu. Read this, then `CLAUDE.md`, then continue without
asking Ishu to repeat anything below. Written 28 Oct 2026 (end of day);
`origin/main` was `0137a3f`. Re-verify anything load-bearing against the code —
things move. Statements marked **To be confirmed** could not be checked from
git (GitHub, Render, Neon and what other people told Ishu are not visible
there); statements marked **(per Ishu)** or **(per Shaaz)** are what they said,
and are not proven by this repository.

---

## 1. The project in 10 lines

1. Nenjam Matrimony: Flutter app + NestJS pnpm monorepo (`backend/`), Prisma, shared Neon Postgres.
2. Deployed on **Render**: one Free web service on branch `main`, auto-deploys; no worker, scheduler or confirmed Redis (per Ishu; **To be confirmed** — not visible from git). `backend/railway.toml` still exists but is stale.
3. Ishu owns the **Agent / Partner Program backend**: agents, sign-in, applications, NM codes, attribution, commission, payouts.
4. Shaaz owns admin RBAC and audit, `PlatformSetting` + settings service, admin TOTP, the OTP service, `hashIdentifier`, subscriptions, payments, the admin dashboard. His work is **not on `main` yet** except membership (#123); see section 6.
5. Dhatri owns Flutter and the Agent Portal website. Never touch frontend code.
6. Agents are not members: own phone + OTP sign-in (purpose `AGENT_SIGN_IN`), own access token (HS256), rotating refresh token.
7. Raja's numbers: 10% commission, 14-day hold, 60-day credit window, Rs. 500 minimum payout, 5% first-plan discount, 10 client drafts, PAN before first payout — all settings or policy, never constants.
8. Everything agent-related on `main` is **services and pure functions against ports, with in-memory fakes and tests**, under `backend/apps/api/src/modules/agents/`, **not wired into any module** (checked: nothing outside that folder references it). Nothing is live.
9. Testing only until the Firebase paid plan: dummy OTP (`DUMMY_OTP_ENABLED=true` on Render, anyone can sign in as any number, accepted for testing) — **To be confirmed** on Render.
10. The contract is `docs/agent-program/agent-api.openapi.yaml`. The Phase 1 schema is PR #116 (a Draft, per Ishu), **not applied to any database**.

---

## 2. Standing rules

- **Backend only.** Never edit frontend (`Frontend/`) or Shaaz's files. If they need a change, write Ishu a message for that person.
- **Ishu decides when to push.** You may **commit yourself**, but **push only when Ishu names the branch**, and then only that branch. Never force-push, never push to `main`, never delete branches. Ishu gives permission per task; it does not carry over.
- **No reviewers on normal PRs.** Only a Draft PR (today: #116) gets a reviewer. **Ishu merges their own PRs** once CI passes. There is no `gh` CLI, so you give a compare link and a pasteable title and description; Ishu opens the PR.
- **Merging to `main` deploys to the live Render site.** After every merge, check that the deploy is **Live** (Render dashboard; not visible from git).
- `git fetch` first; branch from **`origin/main`** (not local `main`). Before merging or committing, run `git branch --show-current` (see trap 17).
- **Each batch of steps = ONE branch, one commit per step, ONE pull request**, unless Ishu says otherwise.
- Small, surgical diffs. Match existing style (see `CLAUDE.md`).
- **No new dependency** without asking Ishu. Node built-ins are fine.
- Business values (rates, windows, hold days, limits, flags, token lifetimes) are **parameters or settings, never constants**, and never defaulted in code.
- Pending business rules live in **one clearly marked place** (`PENDING DECISION (Raja)` comment).
- **Never run any Prisma command against a remote or shared database.** See traps 1 and 2. Use a throwaway local Postgres.
- **No migrations or schema edits without approval.** Applying a migration to the shared Neon database is a separate step Ishu must approve (nothing runs `prisma migrate deploy` on Render).
- Never print or store secrets, environment values, real phone numbers, emails, PAN or bank details. Use only the approved fake test values (trap 14).
- Verify claims against code on `origin/main`; write "To be confirmed" rather than guess. `CLAUDE.md`, `BRAIN.md` and `PROJECT_RULES.md` have known stale parts.

**Checks for every step** (from `backend/`), and say honestly what was not run:

```
npx tsc --noEmit
pnpm test
pnpm build:all
npx eslint apps/api/src/modules/agents   # or the folder changed
```

Also run the new spec alone (`npx jest <spec path>`) to count new tests, and
confirm the full-suite total rose by that count. For anything security-relevant
also run **mutation checks** (trap 15). Total on 28 Oct: **3315 passed**, 162
suites, 64 skipped, 11 todo.

---

## 3. Where everything is

| What | Where |
|---|---|
| Agent-program code | `backend/apps/api/src/modules/agents/{agent,application,auth,commission,config,content,crypto,errors,payout,ports,referral,settings,testing}/` |
| API contract | `docs/agent-program/agent-api.openapi.yaml` |
| Phase 1 schema draft | `docs/agent-program/agent-phase1-schema-draft.prisma` — **superseded** (header says so); kept as a record |
| Shared handoff | `docs/agent-program/HANDOFF_SHAAZ_AND_DHATRI.md` |
| Frontend handoff | `docs/agent-program/FRONTEND_HANDOFF_DHATRI.md` |
| Real schema | `backend/libs/database/prisma/schema.prisma` (agent models are **not** on `main`; they are on the #116 branch) |
| Phase 1 migration | PR #116, branch `feat/agent-phase1-migration`, folder `backend/libs/database/prisma/migrations/20261028095916_agent_program_phase1/` (see section 4) |
| Shaaz's admin work | PR #129 (draft), branch `feat/admin-rbac-foundation` (section 6) |
| Dummy OTP policy (members) | `backend/libs/common/src/auth/dev-auth.ts`, `POST /auth/dummy-otp/session` |
| Remote | `https://github.com/GrowSpark-Consulting/nenjam_matrimony-app.git` |

---

## 4. State on 28 Oct

### Merged PRs #122 to #133 (from `git log --merges origin/main`; titles are the PR commits' subjects, GitHub titles may differ)

| PR | Branch | What |
|---|---|---|
| #122 | `docs/agent-program-handoff` | shared handoff, frontend handoff, session context, decided settings |
| #123 | `feat/membership-foundation` | Shaaz: Free / Gold / Platinum membership foundation, plus its docs |
| #124 | `docs/agent-program-decisions-28oct` | Raja's 28 Oct decisions recorded; contract says share messages are backend-rendered |
| #125 | `feat/agent-ports-and-config` | ports and in-memory fakes; config service (`GET /agent/config`) |
| #126 | `chore/add-nestjs-jwt` | `@nestjs/jwt` dependency for agent access tokens |
| #127 | `docs/agent-contract-otp-challenge` | OTP request returns a `challengeId`; verify takes it |
| #128 | `feat/agent-ports-and-config` | ports aligned with what was agreed with Shaaz (purpose-bound OTP verify, `tx`, `AgentUnitOfWork`) |
| #130 | `feat/agent-signin-application-services` | sign-in, application and "me" services |
| #131 | `fix/cors-agent-portal-headers` | CORS: allow `Accept-Version`, expose `Retry-After` |
| #132 | `feat/agent-signer-links-validate` | HS256 signer, referral links and list, code validate and attach, hashed requester key |
| #133 | `docs/agent-contract-member-refusals` | member-endpoint refusals, `agentStatus` on application refusals, refresh note |

**#129 is not merged** (Shaaz's draft). **#116 is open**, Draft per Ishu (**To be confirmed** on GitHub).

### What is merged under `modules/agents/` (none of it wired)

- **Ports** (`ports/`): `AgentOtpPort`, `AgentSettingsPort`, `AgentIdentifierHasher`, `AgentPermissionPort`, `AgentAuditPort`, `AgentClock`, `AgentTokenSigner`, `AgentContentPort`, `AgentCommissionPolicyPort`, `AgentSecretSealer`, `AgentUnitOfWork` (+ opaque `AgentTx`), `AgentMemberReadPort`, and the repositories `AgentRepository`, `ReferralCodeRepository`, `AgentRefreshTokenRepository`, `ReferralAttributionRepository`, `AgentApplicantRepository`, `AgentPayoutDetailsRepository`, `ReferralCodeAttemptStore`. Their shapes are the ones agreed in principle with Shaaz; real adapters do not exist.
- **Fakes and tests** (`testing/`): in-memory fakes for every port, a unit of work that undoes writes made with its `tx`, a shared harness (`agent-test-harness.ts`), and the approved fake values.
- **Real code that is not a fake:** `AesGcmSecretSealer` (`crypto/`, AES-256-GCM via `node:crypto`, `v1:` prefix, key passed in, no key exists anywhere) and `AgentJwtTokenSigner` (`auth/`, HS256 only through `@nestjs/jwt`, secret/issuer/audience are constructor parameters, secret at least 32 characters, no secret exists anywhere).
- **Services:**
  - `AgentSignInService` (`auth/`): OTP start (same answer whether or not the phone is an agent), verify (returns an applicant session or an agent session), refresh (rotation; **strict reuse**: a revoked token presented again revokes every token of that agent and is audited), logout (revokes only the given token).
  - `AgentApplicationService` (`application/`): create or resubmit; a rejected agent who resubmits gets a new refresh-token family and the old tokens are revoked.
  - `AgentMeService` (`agent/`): profile, capabilities, `assertCan`, payout-details update (ACTIVE only, sealed, clears verification, sets `payout_details_set`).
  - `AgentConfigService` (`config/`): labels, share messages, four displayed settings.
  - `AgentReferralService` (`referral/`): links, referrals list (cursor, 1 to 50, default 20), one referral; every read scoped to the caller's own agent id.
  - `AgentReferralCodeService` (`referral/`): public code check and member attach; attempt-limited; the requester key must be an opaque hash, never a raw IP.
- **Pure rules** (all merged earlier): commission (`calculateCommission`, eligibility, transitions, refund effect, draft, ledger), referral (code generator, normaliser, attribution, view mapper, code-validation helpers, discount, share-message renderer), payout (eligibility, plan), agent status and application validators, auth helpers (claims, refresh token, submit rule), settings parser.

### Contract changes (all on `main`)

- Applicants (no agent record yet) get an **access token only** (`ApplicantSession`, no refresh token); `POST /agent/application` returns an **`AgentSession`**.
- `POST /agent/auth/otp/request` returns `{ challengeId, expiresInSeconds, resendAfterSeconds }`; `verify` takes `{ challengeId, code }` (the phone comes from the verified challenge).
- Refusals documented: application (401, 403, 409 with `agentStatus`), member attach (400, 404, 409, 422 `SELF_REFERRAL` / `ALREADY_PAID` / `PHONE_NOT_VERIFIED`, 429). `ALREADY_PAID` and `PHONE_NOT_VERIFIED` are new error codes.
- Refresh: a reused token revokes every refresh token of the agent; **clients must serialise refresh calls, including across tabs**. Logout revokes only the given token.
- Share messages are rendered by the backend (placeholders `{agent_name}`, `{code}`, `{discount_percent}`, `{link}`).

### The Phase 1 migration (#116)

- Branch `feat/agent-phase1-migration` (tip `2ed3922` when pushed on 28 Oct) replaces the never-merged `20261027141658_agent_phase1` with **`20261028095916_agent_program_phase1`**, which sorts after every migration on `main` (latest there: `20261027120100_membership_catalog`). It also carries the one added back-relation line on `User` (**Shaaz has approved it, per Ishu**).
- Checked on a throwaway local database: replay of all 34 migrations, CI's drift check ("No difference detected") and a control that fails, an object-by-object additivity comparison (nothing existing altered), 74 of 74 `psql` behaviour tests and a control that fails 12 without the hand-written constraints, 3315 tests, build.
- **It is NOT applied to any database.** Nothing runs `prisma migrate deploy` on Render. Shaaz ran a read-only check on the **production** Neon database on 28 Oct: no agent migration rows and no agent tables (**per Shaaz; To be confirmed**; other shared databases, if any, were not checked as far as is known).
- Shaaz's own migrations `20261028070845_admin_rbac_foundation` and `20261028075906_plan_drafts` are on his branch (verified in git), sort **before** ours, and are not applied anywhere. His next migrations (settings table, OTP challenges, payment fields) are to come **after** ours (per Shaaz).

### The 18 settings keys that must be seeded (no defaults in code)

`commission.auto_approve`, `commission.require_verified_profile`, `referral.credit_window_days`, `referral.member_discount_bps`, `referral.discount_stacks_with_coupons`, `referral.discount_only_in_credit_window`, `payout.minimum_amount_paise`, `agent.client_draft_limit`, `agent.payout_details_wait_hours`, `commission.base`, `commission.base_provisional`, `payout.tax_withholding`, `agent.access_token_ttl_seconds`, `agent.refresh_token_ttl_seconds`, `agent.otp_resend_after_seconds`, `referral.code_validation_ip_limit`, `referral.code_validation_code_limit`, `referral.code_validation_window_seconds`.

The three newest are positive integers, as are the three before them. `commission.base` and `payout.tax_withholding` may legitimately be `null` ("not decided"). **Decided values (Final Build Spec §4):** `commission.auto_approve` = `true`; `agent.payout_details_wait_hours` = `72`; `commission.require_verified_profile` = `false`; `referral.discount_only_in_credit_window` = `true` as the default, still pending Raja's confirmation. The rest need values from Ishu/Raja. Hold days come from the commission policy, **not** from these settings.

### Every table the ports imply

| Port | Table | In migration `20261028095916_agent_program_phase1`? |
|---|---|---|
| `AgentRepository` | `agents` (`phone`, `phone_hash`, `pan_last4`, `pan_encrypted` = the sealed PAN, `payout_details_set`, …) | yes |
| `ReferralCodeRepository` | `referral_codes` (+ code-format CHECK and one-primary-per-agent index, hand-written) | yes |
| `AgentRefreshTokenRepository` | `agent_refresh_tokens` (no `family_id`) | yes |
| `ReferralAttributionRepository` | `referral_attributions` (`phone_hash` nullable-unique, `needs_review`) | yes |
| `AgentApplicantRepository` | `agent_applicants` | yes |
| `AgentPayoutDetailsRepository` | `agent_payout_details` (+ `agent_payout_method` enum) | yes |
| `ReferralCodeAttemptStore` | `referral_code_attempts` | yes |
| (device push tokens, no port yet) | `agent_device_tokens` | yes |
| `AgentCommissionPolicyPort` | a commission policy version table (`hold_days`, …) | **no, deferred to the commission batch** |
| `AgentMemberReadPort` | none (reads existing member data) | n/a |

Expired `agent_applicants` and `referral_code_attempts` rows are purged **opportunistically inside the real adapters** (a small limited batch on write); no scheduler (noted in the ports' doc comments).

---

## 5. Decisions, and what is still open

### Decided on 28 Oct

- Raja approved the **Tamil share message** (wording in `FRONTEND_HANDOFF_DHATRI.md` section 6, in `content/agent-content.ts`); other Tamil labels are still `'<to be supplied>'`.
- The **Partner Program button is on the landing page only**, not in the app.
- **No agent KYC yet.** **Dummy OTP until the Firebase paid plan** is bought. **No coupons** in the agent program (`referral.discount_stacks_with_coupons` exists in the settings list but must not be used).
- Applicants get an **access token only**; applying returns an **agent session**; **strict refresh reuse** (a revoked token presented again revokes everything; accepted as strict by design).
- `family_id` is **dropped**; the **commission policy table is deferred**; **`payout_details_set` is a column** and the payout-details update must set it; **purge of expired rows happens inside the real adapters**.
- A self-referring agent **stays blocked** (an admin can correct it with a recorded reason, once the admin endpoint exists).
- Check-then-record counting and a non-constant-time code check are **accepted for now**; note both as limits for the real adapters.

### Marked pending-decision places in the code

| Decision | Place |
|---|---|
| Rejected agent may re-apply | `REJECTED_MAY_REAPPLY` in `agent/agent-status.ts` (currently `true`); consumed by `decideApplicationSubmit` and injectable into `AgentApplicationService` |
| Members with no verified phone | `decideMissingPhoneHash()` in `referral/decide-attribution.ts` (signup sources refused, payment source accepted and flagged `needs_review`) |
| Terminated agents' pending commission | `frozenForAgent()` in `commission/decide-commission-transition.ts` (currently frozen) |
| Partial refund before approval | `planRefundEffect()` in `commission/plan-refund-effect.ts` (cancels the whole commission) |
| Tax withholding (CA) | `planPayout()` in `payout/plan-payout.ts` refuses any set value with `TAX_RULE_UNSUPPORTED` — **must change when the CA answers** |
| Commission base (CA) | `commission.base` setting; `buildCommissionDraft()` returns `amountPaise: null` while it is `null` |
| Tamil labels | `AGENT_TAMIL_LABEL_PENDING` in `content/agent-content.ts` |

### Open decisions

Plan prices; GST and the commission base (CA); TDS (CA); may a rejected agent re-apply (Raja); how an agent pays for a client's plan; Tamil wording for the other labels; the referral link web address (`link` and `qrPayload` are `null` until decided); agent KYC later; members with no verified phone; terminated agents' pending commission; partial refund before approval; **who approves agents** (only `SUPER_ADMIN` is seeded on Shaaz's branch); where scheduled jobs run (no worker or scheduler on Render); **how migrations get applied on Render** (nothing does today); the Help screen support contact.

---

## 6. Shaaz's answers (28 Oct)

Verified in git on `origin/feat/admin-rbac-foundation` (PR #129, draft; two feature commits `9b4e996` and `a97133a`):

- Permission model: `Role` / `Permission` / `RolePermission` / `AdminUserRole` tables, plus `AdminGuard` and the `@RequirePermissions` decorator.
- The real function is `assertAdminPermission(db, actorId, permission)` (`admin/rbac/assert-admin-permission.ts`): it takes a transaction client or Prisma (`Pick<TransactionClient, 'user'>`), the **User id**, and a key of the form `module.action`; it throws Nest's `ForbiddenException`. Our `AgentPermissionPort` adapter must convert that to `AgentPermissionDeniedError`.
- `AdminAuditService.record(tx, entry)` with `actorType` one of `STAFF` / `MEMBER` / `AGENT` / `SYSTEM` (a CHECK on `audit_logs.actor_type`). His migration adds the `audit_logs` columns `actor_type`, `before`, `after`, `reason`, `request_id` and `user_agent`.
- **48 permission keys** are seeded, including `agent.pii.reveal`. **Step-up** (a fresh authenticator code) is required for `payout.execute`, `agent.pii.reveal`, `member.pii.reveal`, `refund.approve` and `rbac.manage`. **Only `SUPER_ADMIN`** is seeded as a role.
- Admin TOTP sign-in (`admin/auth/totp.ts`, secrets stored sealed) and provisioning only by an operator-run script, `pnpm admin:provision` (`backend/scripts/admin-provision.ts`: grant, revoke, reset-mfa, deactivate; there is no HTTP route for it). **Overlap to decide:** his `admin/auth/secret-box.ts` is also AES-256-GCM, with a different format (`v1.<iv>.<tag>.<ciphertext>`) and its own key `ADMIN_MFA_ENCRYPTION_KEY`; our `AesGcmSecretSealer` uses `v1:` + base64url and a key passed in. Whether to share one sealer is **To be confirmed** with Shaaz.

**Per Shaaz, not yet in git (To be confirmed when they land):**

- A `PlatformSettingsService` (key, JSON value, version). **Our settings seed must be a SEPARATE migration that sorts after his settings table.**
- Agent OTP dummy: off unless `AGENT_OTP_DUMMY_ENABLED=true`; the code comes from `AGENT_OTP_DUMMY_CODE` (no default, never logged); allow-listed numbers only in production.
- `hashIdentifier(kind, value)` with `IDENTIFIER_HASH_PEPPERS` = `v1:<secret>[,v0:<old>]` (newest first), an **`IP` kind**, and `hashIdentifierAll`.
- He wires `quoteReferral` into `checkout.service.ts` (`planPriceId` = the `SubscriptionPlanDuration` id, `listAmountPaise` = `duration.priceInPaise`) and adds the payment fields `paid_by`, `payment_source_hash`, `is_first_paid_plan`, `held_referral_code_id` (no foreign key), `discount_paise`, `discount_source`, plus `referral-events.ts`.
- The production Neon database had no agent migration rows and no agent tables on 28 Oct.

### Admin endpoints he wants

- `GET /admin/agents/summary`
- `GET /admin/agents` with filters
- `GET /admin/agents/:id`
- `POST` approve and reject `{ reason }`
- `POST` pause, resume, terminate `{ reason }`
- `POST` codes/replace `{ reason }`
- `POST` payout-details/verify
- `POST` reveal `{ reason }` (`agent.pii.reveal`, step-up, returned once, never cached)
- `GET /admin/agents/:id/referrals`
- `POST /admin/referrals/:id/correct { reason }`
- Commissions: list, approve, cancel `{ reason }`, override `{ amountPaise, reason }`
- Payouts: payable list, create (`Idempotency-Key`), mark-paid `{ reference, paidAt }`, cancel `{ reason }`

Conventions: `{ items, nextCursor }`, paise, ISO dates, every mutation takes `{ reason }` and audits in the same transaction.

---

## 7. Next steps, in order

1. A **docs-only admin contract file** for the endpoints above, for Shaaz to review.
2. The **real Prisma adapters** for the ports (repositories, unit of work, applicant and attempts stores), after #116 and Shaaz's pieces are merged. They must also: purge expired rows in small batches, make the attempt counter atomic, refuse a raw IP as requester key, and convert `ForbiddenException` to `AgentPermissionDeniedError`.
3. The **settings seed** as its own migration, after Shaaz's settings table.
4. **`quoteReferral`** (step I) — read-only, at checkout, against Shaaz's `checkout.service.ts`.
5. **Commission creation, refund handling, the daily approval job and payouts**, after his payment events exist and it is decided where scheduled jobs run.
6. The **sealed PAN reveal path** with a real key (nobody holds a sealing key or an agent JWT secret yet).
7. The end-of-project **`FRONTEND_HANDOFF` update**.

---

## 8. Known traps

1. **`backend/prisma.config.ts` loads `.env.local` with `override: true`.** A `DATABASE_URL` set in the shell is silently replaced. **Never run Prisma with the repo config.** Use a guarded wrapper (trap 2).
2. **Throwaway Postgres procedure.** PostgreSQL 17 is at `C:\Program Files\PostgreSQL\17\bin`; a Windows service already runs on port **5432** — do not touch it. In the scratchpad: `initdb -D <dir> -U postgres -A trust -E UTF8 --locale=C`; start with `pg_ctl ... -o "-p 55432 -c listen_addresses=127.0.0.1" -l <log> -w start` (run it in the background: from Git Bash it can hang the foreground); create empty databases with `createdb`. Write a **wrapper script** that builds `postgresql://postgres@127.0.0.1:55432/<db>`, **refuses any host except `localhost` / `127.0.0.1`**, prints the masked URL before every command, allows only `validate`, `format`, `generate`, `migrate deploy|dev|diff|status`, and passes a minimal environment; pair it with a **scratch config** (no `.env` loaded, throws on a non-local host) via `prisma --config`. Quote the PG path (it has a space). Stop the cluster and delete its data directory when done. CI uses `postgres:16`; the throwaway is 17 — keep SQL portable. CI's drift check passes only if the output contains **"No difference detected"**.
3. **Generated Prisma client is gitignored** (`backend/libs/database/generated/`). Regenerate locally after a schema change so `tsc` passes; don't commit it.
4. **`CLAUDE.md` says Railway**; deployment is Render.
5. **`git diff a..b` vs `a...b`**: when `origin/main` moves, a two-dot diff shows unrelated files. Use three-dot for "what this branch adds". `git diff --no-renames` shows a replaced file as delete + add.
6. **Prettier reformats files** after you write them; re-read before editing, and expect patterns written for unformatted code to stop matching.
7. **ESLint** (typed rules) flags `Object.prototype.hasOwnProperty.call` returns, unnecessary type assertions (`eslint --fix` removes them), trailing unused parameters and `expect.any(...)` assignments. New code must lint clean.
8. **Make your commit step stop on `tsc` failure too**, not just ESLint.
9. A bash heredoc containing some characters once broke the shell parse; prefer the Write tool for file contents.
10. **No `python`, no `gh` CLI.** Use node for scripts; give compare links. `git show origin/main:path` needs `MSYS_NO_PATHCONV=1` in Git Bash.
11. Shell is Windows (Git Bash and PowerShell). Paths: `/d/nenjam_matrimony-app` in bash.
12. The settings list includes `referral.discount_stacks_with_coupons`, but there is **no coupon feature**. Don't use it; don't remove it without asking.
13. `POST /agent/devices` only accepts `ANDROID`/`IOS` — the website portal has no push yet.
14. **Approved fake test values:** `+919876543210`, `+919000000001`, `+919000000002`, `+919999999999`, `ABCDE1234F`, `AAAAA1111A`, `HDFC0001234`, `ravi@okbank`, `NM7K2P9X`. Nothing else that looks real.
15. **Mutation checks must use a script that refuses a mutation whose pattern does not match** (prettier wraps lines, so a plain `sed` can silently do nothing and a "surviving" mutation proves nothing). Compare a surviving mutant with an equivalent one before adding a test.
16. **`prisma format` reformats Shaaz's models.** After running it, restore everything outside the agent section byte-for-byte from the merge result. Prisma 7 `migrate dev` no longer accepts `--skip-generate` / `--skip-seed` (it does not generate or seed on its own).
17. **Check `git branch --show-current` before a merge or commit.** `git checkout -b X` fails silently-ish if a local branch `X` already exists, and the next command then runs on the wrong branch (this happened once; it was undone before any push).
18. **Nothing runs `prisma migrate deploy` on Render.** A merged migration is not applied until someone runs it, and applying one to the shared Neon database is a separate step Ishu must approve.
19. Applicants have **no refresh token**. Contract limits and HTTP mappings for the refusals are in the service header comments (`agent-application.service.ts`, `agent-referral-code.service.ts`).
20. A **PR's GitHub title and Draft state are not in git**; take them from Ishu.

---

## 9. Report format Ishu expects

After each batch:

1. A table: branch, commit, new tests, results (tsc, pnpm test totals, build:all, ESLint).
2. Extra choices made that were not specified.
3. Decisions to confirm (who: Raja, Shaaz, CA, Dhatri).
4. Honest limits: what was not run or not verified, and any mutation checks (what was broken, whether it was caught).

Then **stop and wait**.

**PR description format** (one per batch), plus the compare link
`https://github.com/GrowSpark-Consulting/nenjam_matrimony-app/compare/main...<branch>?expand=1`:

- **Title**
- **What** (one short section per step)
- **Why** — cite real sections: Final Build Spec §2 (decisions), §3 (rules), §4 (flexibility), §5 workflows A–F; and Final Plan sections (e.g. §13 Safeguards)
- **Files**
- **Tests** — exact commands and results; say what was not run; number of new tests
- **Risk** — "Not wired into any module, no schema change, no migration, no new dependency, no behaviour change. Merging to main triggers a deploy to the live Render site, with no effect on users." (adjust when true)
- **Decisions to confirm**
- **Not included**
- End each PR description with the attribution line your Claude Code setup requires.

**Before any push** (only when Ishu names the branch): `git remote -v`; `git fetch`; `git log --oneline origin/main..<branch>`; `git diff --stat origin/main...<branch>`; dry-run merge (`git merge-tree --write-tree origin/main <branch>`); secret scan of added lines (keys, tokens, connection strings, emails, phone numbers, PAN); confirm nothing from the scratchpad is included. If `origin/main` moved, merge it into the branch with a regular merge (no rebase, no force) and rerun the checks.

Ishu likes plain language and copy-paste-ready output.

---

## 10. First thing to do next session

1. `git fetch`; check what merged (`git log --merges origin/main`), whether #116 and #129 are still open, and whether Shaaz's later migrations (settings table, OTP challenges, payment fields) are on `main`.
2. Check whether `PlatformSetting`, `OtpChallenge`, `hashIdentifier`, `quoteReferral` and the payment fields now exist (`git grep` on `origin/main` and on his branch); update section 6.
3. Ask Ishu which step from section 7 to start (most likely step 1, the admin contract file, which needs nothing from anyone else) and wait.
