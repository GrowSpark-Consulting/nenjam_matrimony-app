# Agent / Partner Program — shared handoff

For: Shaaz (backend: permissions, settings, OTP, payments, admin dashboard) and
Dhatri (Flutter app and Agent Portal website).
From: Ishu (agent-program backend).
State as of: 27 Oct 2026, `origin/main` at `5a8a561`.

Status words used below: **Done (merged)**, **In review**, **Waiting on Shaaz**,
**Not started**, **Pending decision**. Anything we could not check in the code
is marked **To be confirmed**.

---

## 1. What we are building, and why

Nenjam is adding a **Partner Program**: people ("agents") sign up, get an
**NM referral code** (for example `NM7K2P9X`), and share it. When someone they
referred buys their **first paid plan**, the agent earns a **commission**
(10%). The referred member gets **5% off** that first plan. After a
**hold period** (14 days) the commission can be approved, and an admin pays
agents out **manually** once their balance reaches the **minimum** (Rs. 500).

Why it is built the way it is:

- **Business numbers change**, so every number is a **setting** (or a
  versioned commission policy), never written into code.
- **Agents are not members.** An agent has their own phone sign-in and their
  own token, separate from the member's Firebase login.
- **Agents see very little about the people they referred**: first name and
  last initial, age, city, dates, stage, plan, commission status and a
  masked phone (`+91 98***210`). Nothing else.

---

## 2. The parts and how they connect

| Part | What it is | Owner | Where |
|---|---|---|---|
| Backend API | NestJS app in this repo (`backend/apps/api`). Agent endpoints will live under `/agent/...`, member referral endpoints under `/referrals/...` and `/registration/...` | Ishu (agent program), Shaaz (permissions, settings, OTP, payments) | Deployed on **Render**, one Free web service, branch `main`, auto-deploys on merge. No worker, no scheduler, no confirmed Redis on Render. (The repo still contains `backend/railway.toml` from an earlier setup — To be confirmed whether to remove it.) |
| Database | PostgreSQL via Prisma, **shared Neon** database | Each of us owns our own models and migrations in the shared `schema.prisma` | Neon |
| Admin dashboard | Separate app, its own repo and link. Admin signup is invite-only. | Shaaz | Its own repo |
| Agent Portal | Website for agents, phone-first | Dhatri | Its own web address (**not decided yet**). That address must be added to `CORS_ORIGINS` on Render. |
| Landing page | Will carry a "Partner Program" button/link that opens the Agent Portal. Possibly another repo, planned later. | To be confirmed | — |
| Flutter app | Member app. Gets a "Have a referral code?" box on the name and age page (and a promo code box at payment later). | Dhatri | `Frontend/` in this repo |

**Entry point (decided by Raja, 28 Oct):** "Partner Program" is a button/link
on the **landing page only**, not in the app. It opens the Agent Portal at its
own address.

How a referral flows end to end:

```
Agent Portal ──(agent token)──> /agent/* endpoints ──> agent tables
                                                         │
Member app "Have a referral code?" ──> /referrals/codes/validate (no token)
                                   ──> /registration/referral-code (member token)
                                                         │
Shaaz's checkout ──> quoteReferral() (Ishu, read-only) ──> 5% discount on first plan
Shaaz's payments ──> PaymentSucceeded / PaymentRefunded events
                 ──> onPaymentSucceeded / onPaymentRefunded (Ishu) ──> commission + ledger
Admin dashboard (Shaaz) ──> admin endpoints behind Shaaz's permission guard ──> approve, pay out
```

---

## 3. Who owns what

| Area | Owner |
|---|---|
| Agent tables, agent sign-in, applications, NM codes, attribution, referral validate/attach, commission, payouts, and the backend behind the agent, commission and payout screens | **Ishu** |
| Permission guard and `@Audited`, AuditLog columns, `PlatformSetting` and the settings service, admin MFA (TOTP), the shared `OtpService` (agent sign-in calls it with purpose `AGENT_SIGN_IN`), `hashIdentifier(kind, value)` in `libs/common`, subscriptions, payments (including offline payments), the admin dashboard | **Shaaz** |
| Flutter changes and the Agent Portal website | **Dhatri** |

Shaaz's schedule: **Day 1 migration Wed 28 Oct** (permission tables, settings,
AuditLog columns, `OtpChallenge`), **Day 2 Thu 29 Oct** (guard, `OtpService`,
TOTP, `@Audited`, the `referral-events.ts` contract).

Rule we keep: if one of us needs a change in the other's files, we **send a
message** rather than edit them.

---

## 4. Raja's decisions, and where each one lives

All values are settings or a versioned commission policy. None are constants
in code. The setting keys below are the ones defined in
`backend/apps/api/src/modules/agents/settings/agent-program-settings.ts`
(merged). The table that stores settings (`PlatformSetting`) is Shaaz's and
**does not exist yet**, so no values are stored anywhere yet.

| Decision | Value | Where it lives | Status |
|---|---|---|---|
| Commission rate | 10% (percentage only for now) | Commission policy: `calcType: 'PERCENTAGE'`, `value: 1000` (basis points). Checked by `validateCommissionPolicyVersion()`. Snapshotted on every commission. Policy table: Not started. | Decided |
| Hold period | 14 days | Commission policy `holdDays: 14` | Decided |
| Commission never above what was paid | — | `calculateCommission(rule, basePaise, amountPaidPaise)` caps at `amountPaidPaise` | Done (merged) |
| Credit window | 60 days | `referral.credit_window_days` = `60` | Decided |
| Minimum payout | Rs. 500 | `payout.minimum_amount_paise` = `50000` | Decided |
| Referred member discount | 5%, first paid plan only | `referral.member_discount_bps` = `500` | Decided |
| Open client drafts | 10 | `agent.client_draft_limit` = `10` | Decided (agent-added clients come later) |
| PAN before the first payout | required | A rule in `decidePayoutEligibility()` (`PAN_NOT_VERIFIED`), not a setting | Done (merged) |
| Verified profile needed for commission | OFF (no KYC yet) | `commission.require_verified_profile` = `false` | Decided by the team |
| Auto-approve commissions after the hold | On (an admin can switch to manual later, without a deploy) | `commission.auto_approve` = `true` | Decided |
| Wait after payout details change | 72 hours | `agent.payout_details_wait_hours` = `72` | Decided |
| Discount only inside the credit window | Yes (default) | `referral.discount_only_in_credit_window` = `true` | Default set; **Pending decision** (Raja to confirm) |
| Commission base (with or without GST) | 10% of the amount **without GST**. Plan prices are **exclusive** of GST (Raja, 29 Oct): GST is added on top, so the member pays taxable + GST. `quoteReferral` returns `taxableAfterDiscountPaise` (before GST), never what the member pays | `commission.base` = `AMOUNT_PAID_EXCLUDING_GST` and `commission.base_provisional` = `false`. The commission handler computes `base = amountPaid` (after the referral discount) minus the GST part (`taxPaise` from the `PaymentSucceeded` event) | Decided (Raja, 28 Oct) |
| Tax withholding (TDS) | — | `payout.tax_withholding` (shape unknown, passed through as-is) | **Pending decision** (CA) |

Note: the settings list also contains `referral.discount_stacks_with_coupons`.
There is **no coupon feature in the agent program** (coupons are Shaaz's
separate marketing feature), so nothing in agent-program code uses that key.
The referral discount is the only discount we handle.

---

## 5. Pending decisions

| Question | Who decides | Where it shows in code (one marked place) |
|---|---|---|
| Plan prices | Raja | — |
| TDS | CA | `planPayout()` refuses any set tax value with `TAX_RULE_UNSUPPORTED` |
| Partial refund before approval | Raja | `planRefundEffect()` in `commission/plan-refund-effect.ts` (currently cancels the whole commission) |
| How an agent can pay for a client's plan | Raja | Not started |
| Tamil wording for the other labels (statuses, stages) | Raja | Comes from `GET /agent/config` (not built yet). The share messages are approved and final (28 Oct); see `FRONTEND_HANDOFF_DHATRI.md` section 6 |
| Referral link web address | Raja | `link` and `qrPayload` are `null` until decided |
| Will agents need KYC later? | Raja | — |

**Decided by Raja (28 Oct, evening), no longer pending:**
- **Commission base:** 10% of the amount without GST (see the settings table above).
- **A rejected agent may re-apply**; the resubmission goes back to `PENDING_APPROVAL` for admin review (`REJECTED_MAY_REAPPLY` stays `true`).
- **A terminated agent's waiting commission stays FROZEN** until Raja decides otherwise; commission already approved is still paid.
- **Roles (Shaaz):** Raja plus one more as Super Admin; a **Partner Manager** role for approving and rejecting agents; payouts only for Raja and the person who pays. Pause, terminate and PAN/phone reveal are not specified yet: Super Admin only for now.
- **The four agent terms** on the Help screen are approved (a lawyer checks them before launch).
- **Still open:** the support contact for the Help screen, agent KYC, plan prices, TDS (the CA), the web address.

**Decided (no longer pending): members with no verified phone.** A member with no verified phone can never be credited to an agent (`referral_attributions.phone_hash` is NOT NULL), from any source. `quoteReferral` returns no discount with `PHONE_NOT_VERIFIED` and payment goes on; a code entered at payment follows the same rule.

---

## 6. What is merged and what is next

Everything merged so far is **pure functions with tests**. None of it is wired
into a NestJS module yet (checked: `app.module.ts` does not reference it and
nothing outside `modules/agents/` imports it), so **none of it is live**.

All files are under `backend/apps/api/src/modules/agents/`. PR numbers and
branch names were checked against `git log --merges origin/main`.

| Item | File | PR | Status |
|---|---|---|---|
| Dummy OTP docs corrected (comments and `.env.example` only) | `libs/common/src/auth/dev-auth.ts`, `.env.example` | #100 | Done (merged) |
| `calculateCommission` | `commission/calculate-commission.ts` | #101 | Done (merged) |
| NM code generator | `referral/referral-code.ts` | #102 | Done (merged) |
| Agent referral view (allow-list, masked phone, IST dates) | `referral/agent-referral-view.ts` | #103 | Done (merged) |
| `isProfileEligibleForCommission` | `commission/profile-eligibility.ts` | #104 | Done (merged) |
| API contract and schema draft | `docs/agent-program/` | #105, #120 | Done (merged) |
| `normalizeReferralCode` | `referral/normalize-referral-code.ts` | #106 | Done (merged) |
| `decideAttribution` | `referral/decide-attribution.ts` | #107 | Done (merged) |
| `decideCommissionTransition` | `commission/decide-commission-transition.ts` | #108 | Done (merged) |
| `planRefundEffect` | `commission/plan-refund-effect.ts` | #109 | Done (merged) |
| Settings validation | `settings/agent-program-settings.ts` | #110 | Done (merged) |
| `buildCommissionDraft` | `commission/build-commission-draft.ts` | #111 | Done (merged) |
| `decidePayoutEligibility` | `payout/decide-payout-eligibility.ts` | #112 | Done (merged) |
| Agent status rules and capabilities | `agent/agent-status.ts` | #113 | Done (merged) |
| PAN / UPI / IFSC / bank validators and maskers | `agent/application-validators.ts` | #114 | Done (merged) |
| `renderShareMessage` | `referral/render-share-message.ts` | #115 | Done (merged) |
| Refresh token helpers | `auth/refresh-token.ts` | #117 | Done (merged) |
| Access token claims | `auth/agent-access-claims.ts` | #118 | Done (merged) |
| `decideApplicationSubmit` | `auth/decide-application-submit.ts` | #119 | Done (merged) |
| Code validation helpers, `computeReferralDiscount`, ledger entry builders, `planPayout` | `referral/code-validation.ts`, `referral/compute-referral-discount.ts`, `commission/ledger-entries.ts`, `payout/plan-payout.ts` | #121 | Done (merged) |
| Phase 1 database migration (agents, referral codes, attribution, tokens) | branch `feat/agent-phase1-migration` | #116 (confirmed: GitHub's `refs/pull/116/head` is this branch) | **In review** (Draft per Ishu; Draft status To be confirmed on GitHub). **Waiting on Shaaz**'s Day 1 migration. |

Next, in order:

1. After Shaaz's Day 1 merges: regenerate the Phase 1 migration so it sorts
   after his, re-append the two hand-written constraints, rerun the replay and
   drift check, and add the agent-program settings seed. — **Waiting on Shaaz**
2. Services and endpoints: sign-in, application, `me`, `config`, referral
   links and list, code validate and attach. — **Not started**
3. Admin endpoints, behind Shaaz's permission guard. — **Waiting on Shaaz**
4. Commission creation, refund handling and the daily approval job, once
   payments exist and we decide where the daily job runs (there is no worker
   or scheduler on Render). — **Not started**
5. End-of-project handoff update. — **Not started**

---

## 7. The interface between Ishu's code and Shaaz's

| Piece | Owner | What it does | Status |
|---|---|---|---|
| `quoteReferral()` | Ishu | Read-only. Shaaz's checkout calls it to get the referral discount for a first plan. The merged math is `computeReferralDiscount()`. | Not started (math merged) |
| `PaymentSucceeded`, `PaymentRefunded` events | Shaaz | Emitted **after the payment commits**, through a swappable transport (no worker exists yet). Contract file `referral-events.ts` due Day 2. | Waiting on Shaaz |
| `onPaymentSucceeded`, `onPaymentRefunded` | Ishu | Handlers keyed on `paymentId` and `refundId`, so a repeated event never counts twice. Use `buildCommissionDraft()`, `planRefundEffect()` and the ledger builders. | Not started |
| Payment fields | Shaaz | `paid_by`, `payment_source_hash`, `is_first_paid_plan`, `held_referral_code_id` (no foreign key) and the discount fields | Waiting on Shaaz |
| Permission keys and the settings table | Shaaz | Admin endpoints use his guard; agent settings are stored in his `PlatformSetting` | Waiting on Shaaz |
| `OtpService` with purpose `AGENT_SIGN_IN` | Shaaz | Agent sign-in sends and checks OTPs through it | Waiting on Shaaz |
| `hashIdentifier(kind, value)` | Shaaz | Phone hashing in `libs/common`. Ishu does not write a second helper. | Waiting on Shaaz |

Direction rule: **agent tables may point at Shaaz's tables (for example
`users`); his tables never point at ours.** In the Phase 1 migration the only
change to an existing model is one Prisma back-relation line on `User`
(`referralAttribution ReferralAttribution?`), which adds no column.

---

## 8. Deployment and testing notes

- **Everything is for testing** until we buy the Firebase paid plan. Until
  then the **dummy OTP** is on (`DUMMY_OTP_ENABLED=true` on Render): anyone can
  sign in as any number. The team accepted this for testing. The app does not
  go live to customers before real OTP is on. Real agents, real payments and
  payouts wait for that.
- **Render**: one Free web service on `main`. Merging to `main` deploys to the
  live site. There is no worker, scheduler or confirmed Redis, so anything
  "daily" needs a decision on where it runs.
- **Migrations are additive only** (no `DROP`, no change to existing columns).
  Nothing runs `prisma migrate deploy` automatically on Render today, so a
  merged migration is not applied until someone runs it.
- **Branches and PRs**: branch from `origin/main`, name `type/short-description`
  (`feat/...`, `docs/...`, `chore/...`), Conventional Commit messages. Each
  batch of work is one branch with one commit per step and one PR.
- **Prisma warning**: `backend/prisma.config.ts` loads `.env.local` with
  `override: true`. A `DATABASE_URL` set in your shell is silently replaced by
  whatever `.env.local` points to, so any Prisma command can hit that
  database. Check `.env.local` before running Prisma locally.

---

## 9. Risks, and things we agreed not to do

- No coupon handling in the agent program.
- No KYC or face verification for agents; profiles show without verification;
  the verified-profile commission check stays OFF.
- No discovery filter changes for the agent program.
- No changes to OTP behaviour, and no DLT/SMS work.
- Account deletion (keeping payments and a phone hash after deletion) is
  parked.
- Agents cannot create payouts; payouts are manual, by an admin.
- No frontend commission or eligibility logic: the backend decides, the
  frontend shows.
- Risk: the dummy OTP lets anyone sign in as any number. Never point it at a
  database with real users.
- Risk: the Phase 1 migration must sort after Shaaz's Day 1 migration;
  merging it early would break the order.
- Risk: the daily approval job has nowhere to run on Render yet.

---

## 10. Glossary

| Term | Meaning |
|---|---|
| Agent | A partner who refers members. Not a member; has their own sign-in. |
| Applicant | A phone with no agent record yet. Gets an access token only. |
| NM code | Referral code: `NM` + 6 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0, O, 1, I, L). |
| Attribution | The link between a member and the agent who referred them. One per person, keyed on a phone hash. |
| Credit window | Days after attribution during which a first paid plan earns commission (60). |
| Hold | Days a commission waits before it can be approved (14). |
| Paise | All money is in paise: Rs. 500 = `50000`. |
| Basis points (bps) | 1/100 of a percent: 10% = `1000`, 5% = `500`. |
| Ledger | Signed entries (credit, reversal, payout debit, payout release, adjustment) whose sum is the agent's balance. |
| Public commission status | What an agent sees: `ON_HOLD`, `APPROVED`, `PAID`, `CANCELLED`. Internal review states show as `ON_HOLD`. |
| Stage | Where a referred person is: `REGISTERED`, `PROFILE_COMPLETE`, `PURCHASED`. |
| Paused | How the `SUSPENDED` agent status is shown to agents. |
