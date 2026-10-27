# SESSION_CONTEXT — read this first (for Claude Code)

Audience: the next Claude Code session working on the Nenjam Agent / Partner
Program backend for Ishu. Read this, then `CLAUDE.md`, then continue without
asking Ishu to repeat anything below. Written 27 Oct 2026; `origin/main` was
`5a8a561`. Re-verify anything load-bearing against the code — things move.

---

## 1. The project in 10 lines

1. Nenjam Matrimony: Flutter app + NestJS pnpm monorepo (`backend/`), Prisma, shared Neon Postgres.
2. Deployed on **Render**: one Free web service, branch `main`, auto-deploys. No worker, scheduler or confirmed Redis.
3. Ishu owns the **Agent / Partner Program backend**: agents, sign-in, applications, NM codes, attribution, commission, payouts.
4. Shaaz owns permissions/`@Audited`, AuditLog columns, `PlatformSetting` + settings service, admin MFA, `OtpService`, `hashIdentifier`, subscriptions, payments, admin dashboard.
5. Dhatri owns Flutter and the Agent Portal website. Never touch frontend code.
6. Agents are not members: own phone + OTP sign-in (purpose `AGENT_SIGN_IN`), own access token, rotating refresh token.
7. Raja's numbers: 10% commission, 14-day hold, 60-day credit window, Rs. 500 minimum payout, 5% first-plan discount, 10 client drafts, PAN before first payout — all settings or policy, never constants.
8. Everything so far is **pure functions with tests** under `backend/apps/api/src/modules/agents/`, **not wired into any module**.
9. Testing only until the Firebase paid plan: `DUMMY_OTP_ENABLED=true` on Render (anyone can sign in as any number; accepted for testing).
10. The contract is `docs/agent-program/agent-api.openapi.yaml`; the Phase 1 migration is PR #116, waiting on Shaaz's Day 1 migration.

---

## 2. Standing rules

- **Backend only.** Never edit frontend (`Frontend/`) or Shaaz's files. If they need a change, write Ishu a message for that person.
- **Ishu decides when to push.** Never push, merge, push to `main` or force-push unless Ishu gives explicit permission **for that task**, and then only the branches named. Never delete branches.
- `git fetch` first; branch from **`origin/main`** (not local `main`).
- **Each batch of steps = ONE branch, one commit per step, ONE pull request**, unless Ishu says otherwise.
- Small, surgical diffs. Match existing style (see `CLAUDE.md`).
- **No new dependency** without asking Ishu. Node built-ins are fine.
- Business values (rates, windows, hold days, limits, flags, token lifetimes) are **parameters or settings, never constants**, and never defaulted in code.
- Pending business rules live in **one clearly marked place** (`PENDING DECISION (Raja)` comment).
- **Never run any Prisma command against a remote or shared database.** See trap 1. Use a throwaway local Postgres.
- **No migrations or schema edits without approval.**
- Never print or store secrets, environment values, real phone numbers, emails, PAN or bank details. Use only the fake examples already in the repo (`+919876543210`, `ABCDE1234F`, `HDFC0001234`, `ravi@okbank`, `NM7K2P9X`).
- **Merging to `main` deploys to the live Render site.**
- Verify claims against code on `origin/main`; write "To be confirmed" rather than guess. `CLAUDE.md`, `BRAIN.md` and `PROJECT_RULES.md` have known stale parts.

**Checks for every step** (from `backend/`), and say honestly what was not run:

```
npx tsc --noEmit
pnpm test
pnpm build:all
npx eslint apps/api/src/modules/agents   # or the folder changed
```

Also run the new spec alone (`npx jest <spec path>`) to count new tests, and
confirm the full-suite total rose by that count.

---

## 3. Where everything is

| What | Where |
|---|---|
| Agent-program code | `backend/apps/api/src/modules/agents/{agent,auth,commission,payout,referral,settings}/` |
| API contract | `docs/agent-program/agent-api.openapi.yaml` |
| Phase 1 schema draft | `docs/agent-program/agent-phase1-schema-draft.prisma` |
| Shared handoff | `docs/agent-program/HANDOFF_SHAAZ_AND_DHATRI.md` |
| Frontend handoff | `docs/agent-program/FRONTEND_HANDOFF_DHATRI.md` |
| Real schema | `backend/libs/database/prisma/schema.prisma` (agent models **not** on `main` yet) |
| Phase 1 migration | PR #116, branch `feat/agent-phase1-migration`, folder `backend/libs/database/prisma/migrations/20261027141658_agent_phase1/` (must be regenerated before merge) |
| Dummy OTP policy | `backend/libs/common/src/auth/dev-auth.ts`, `POST /auth/dummy-otp/session` |
| Remote | `https://github.com/GrowSpark-Consulting/nenjam_matrimony-app.git` |

Merged PRs: #100 (OTP docs) … #115, #117–#121. #116 is open (Draft per Ishu).

---

## 4. Merged, and next

Merged (all pure, none wired):

| Area | Exports (file) |
|---|---|
| Commission | `calculateCommission` (`commission/calculate-commission.ts`), `isProfileEligibleForCommission` + `COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY` (`commission/profile-eligibility.ts`), `decideCommissionTransition` (`commission/decide-commission-transition.ts`), `planRefundEffect` (`commission/plan-refund-effect.ts`), `buildCommissionDraft` (`commission/build-commission-draft.ts`), ledger builders + `sumLedgerBalance` (`commission/ledger-entries.ts`) |
| Referral | `generateReferralCode`, `generateUniqueReferralCode` (`referral/referral-code.ts`), `normalizeReferralCode`, `decideAttribution`, `toAgentReferralView`, `maskPhone`, `toDisplayName`, `toPublicCommissionStatus` (`referral/agent-referral-view.ts`), `renderShareMessage`, `decideCodeValidationAttempt`, `toValidateResponse` (`referral/code-validation.ts`), `computeReferralDiscount` |
| Payout | `decidePayoutEligibility`, `planPayout` |
| Agent | `canTransitionAgentStatus`, `agentCapabilitiesFor`, `REJECTED_MAY_REAPPLY` (`agent/agent-status.ts`), PAN/UPI/IFSC/bank normalisers and maskers (`agent/application-validators.ts`) |
| Auth | `generateRefreshToken`, `hashRefreshToken`, `decideRefreshToken`, `buildAgentAccessClaims`, `validateAgentAccessClaims`, `decideApplicationSubmit` |
| Settings | `parseAgentProgramSettings`, `validateCommissionPolicyVersion`, 12 key constants (`settings/agent-program-settings.ts`) |
| Docs | API contract (applicant/agent sessions, application returns `AgentSession`), schema draft |

Next, in order:

1. After Shaaz's Day 1 (due Wed 28 Oct) merges: regenerate the Phase 1 migration so it sorts after his, re-append the two hand-written constraints (code-format CHECK, one-primary-code partial unique index), rerun replay + drift check on a throwaway DB, add the agent-program settings seed.
2. Services and endpoints: sign-in, application, `me`, `config`, referral links and list, code validate and attach.
3. Admin endpoints behind Shaaz's permission guard (Day 2, Thu 29 Oct).
4. Commission creation, refund handling, daily approval job — once payments exist and it's decided where the daily job runs.
5. End-of-project `FRONTEND_HANDOFF` update.

Interface with Shaaz: `quoteReferral()` (Ishu, read-only, at checkout); his `PaymentSucceeded` / `PaymentRefunded` events after commit via a swappable transport; Ishu's `onPaymentSucceeded` / `onPaymentRefunded` keyed on `paymentId` / `refundId`; his payment fields `paid_by`, `payment_source_hash`, `is_first_paid_plan`, `held_referral_code_id` (no FK) and discount fields; his permission keys and settings table. Our tables point at his, never the reverse.

---

## 5. Marked pending-decision places in the code

| Decision | Place |
|---|---|
| Rejected agent may re-apply | `REJECTED_MAY_REAPPLY` in `agent/agent-status.ts` (currently `true`); consumed as `rejectedMayReapply` by `decideApplicationSubmit` |
| Members with no verified phone | `decideMissingPhoneHash()` in `referral/decide-attribution.ts` |
| Terminated agents' pending commission | `frozenForAgent()` in `commission/decide-commission-transition.ts` (currently frozen) |
| Partial refund before approval | `planRefundEffect()` in `commission/plan-refund-effect.ts` (cancels the whole commission) |
| Tax withholding (CA) | `planPayout()` in `payout/plan-payout.ts` refuses any set value with `TAX_RULE_UNSUPPORTED` — **must change when the CA answers** |
| Commission base (CA) | `commission.base` setting; `buildCommissionDraft()` returns `amountPaise: null` while it is `null` |

Other decisions still open: plan prices, how an agent pays for a client's plan, Tamil share text, referral link web address, agent KYC, whether the app shows a Partner Program button. Values not yet decided for keys: `commission.auto_approve`, `agent.payout_details_wait_hours`, `referral.discount_only_in_credit_window`.

---

## 6. Known traps

1. **`backend/prisma.config.ts` loads `.env.local` with `override: true`.** A `DATABASE_URL` set in the shell is silently replaced. Never run Prisma with the repo config. Use a scratch config that loads no `.env` and refuses any host other than `localhost`/`127.0.0.1`, and print the masked URL first.
2. **Throwaway Postgres**: PostgreSQL 17 is installed at `C:\Program Files\PostgreSQL\17\bin`. A Windows service already runs on port **5432** — do not touch it. Create a separate cluster with `initdb` in the scratchpad (`-U postgres -A trust`), start with `pg_ctl ... -o "-p 55432 -c listen_addresses=127.0.0.1"`, stop it when done. Docker is not running. CI uses `postgres:16`.
3. **Generated Prisma client is gitignored** (`backend/libs/database/generated/`), not committed as `CLAUDE.md` claims. Regenerate locally after a schema change so `tsc` passes; don't commit it.
4. **`CLAUDE.md` says Railway**; deployment is Render (`backend/railway.toml` still exists; the Flutter default API host is Render).
5. **`git diff a..b` vs `a...b`**: when `origin/main` moves, a two-dot diff shows unrelated files. Use three-dot for "what this branch adds".
6. **Prettier reformats files** after you write them; re-read before editing.
7. **ESLint** (typed rules) flags `Object.prototype.hasOwnProperty.call` returns (`no-unsafe-return`) and unnecessary type assertions. ESLint is non-blocking in CI but new code must lint clean.
8. **Make your commit step stop on `tsc` failure too**, not just ESLint — a spec-only type error once slipped into a local commit.
9. A bash heredoc containing some characters once broke the shell parse; prefer the Write tool for file contents.
10. **No `python`, no `gh` CLI** on this machine. Use node for scripts; give compare links instead of creating PRs.
11. Shell is Windows (Git Bash and PowerShell). Paths: `/d/nenjam_matrimony-app` in bash.
12. The settings list includes `referral.discount_stacks_with_coupons`, but there is **no coupon feature** in the agent program. Don't use it; don't remove it without asking.
13. `POST /agent/devices` only accepts `ANDROID`/`IOS` — the website portal has no push yet.
14. Contract lists `409 APPLICATION_EXISTS` for `POST /agent/application`, while `decideApplicationSubmit` has finer reasons (`ALREADY_PENDING`, `ALREADY_AN_AGENT`, `REAPPLY_NOT_ALLOWED`, `PHONE_ALREADY_REGISTERED`, `UNKNOWN_STATUS`, `BAD_SCOPE`, `SCOPE_MISMATCH`). The HTTP mapping is to be confirmed when building the endpoint.
15. The contract's code-validation limits ("10/min/IP, 5 failed/min/IP, 20/hour/code") are suggestions; no setting keys exist for them yet.
16. Applicants have **no refresh token** (`agent_refresh_tokens.agent_id` is required in the Phase 1 schema).

---

## 7. Report format Ishu expects

After each batch:

1. A table: branch, commit, new tests, results (tsc, pnpm test totals, build:all, ESLint).
2. Extra choices made that were not specified.
3. Decisions to confirm (who: Raja, Shaaz, CA, Dhatri).
4. Honest limits: what was not run or not verified.

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
- End with the attribution line from the system reminder.

**Before any push** (only when permitted): `git remote -v`; `git log --oneline origin/main..<branch>`; `git diff --stat origin/main...<branch>`; dry-run merge (`git merge-tree --write-tree origin/main <branch>`); secret scan of added lines (keys, tokens, connection strings, emails, phone numbers, PAN); confirm nothing from the scratchpad is included.

Ishu likes plain language and copy-paste-ready output.

---

## 8. First thing to do tomorrow

1. `git fetch` and check whether Shaaz's Day 1 migration has merged (`git log origin/main -- backend/libs/database/prisma/migrations`).
2. Check PR #116's state; if Shaaz's Day 1 is in, regenerate the Phase 1 migration on a throwaway local DB (trap 1 and 2), re-append the hand-written block, rerun replay + drift check, and report — don't push without permission.
3. Check whether `hashIdentifier`, `OtpService`, the permission guard or `PlatformSetting` exist yet (`git grep` on `origin/main`); note what is still missing for the endpoint batch.
4. Ask Ishu which batch to start (likely sign-in + application endpoints) and wait.
