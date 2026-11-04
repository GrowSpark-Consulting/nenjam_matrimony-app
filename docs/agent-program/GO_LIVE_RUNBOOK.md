# Agent program — go-live runbook

For Ishu and Shaaz. The exact ORDER to switch the agent program on in
production, the check after every step, and how to undo each one. Written 29
Oct 2026 (evening) against `origin/main` `ba28426` and the pushed, unmerged
branches named below. **No secret value appears here, and none may be added:**
secrets live in Ishu's password manager and are typed into Render only.
**To be confirmed** marks what git cannot show (Render, Neon, GitHub Actions).

Rules for every step:

- One step at a time. Do the check. Only then the next step.
- Merging to `main` deploys to Render. After each merge, wait until the deploy
  is **Live**, then check `GET /health` answers 200.
- Read the Render log lines named in the checks; never paste a log that
  contains a connection string or token anywhere.
- Migrations are applied only in Shaaz's production window (`prisma migrate
  deploy`), never from a laptop, never by `db push`. An applied migration
  never changes.

---

## 0. Where we start (29 Oct evening)

- Production: **40 migrations**, no drift (per Shaaz). Policy v1 (1000 bps,
  14-day hold) present.
- `main` has: PR A (5 admin routes), #155 (commission tables), #159
  (Payments: checkout injects `AGENT_REFERRAL_QUOTE` optionally; payment
  outbox and `ReferralEventBus`).
- Not on `main` yet: everything below.
- Render: `CORS_ORIGINS` already lists the Agent Portal origin (per Ishu;
  **To be confirmed**). `IDENTIFIER_HASH_PEPPERS`, `AGENT_PII_ENCRYPTION_KEY`,
  `AGENT_JWT_SECRET`, the dummy-OTP variables and `AGENT_PROGRAM_ENABLED` are
  **not set** (per Ishu).

---

## 1. Merge order (approved 29 Oct)

| # | Branch | What changes in production when it merges |
|---|---|---|
| 1 | `feat/agent-quote-provider` | The quote module exists but provides **nothing** until step 3 (peppers) and step 2 (settings) are both in place: checkout keeps charging the list price; typed codes get 422 `PROMO_CODES_UNAVAILABLE`. Log: `Referral quote NOT provided (...)`. |
| 2 | `feat/agent-settings-seed` | Two data-only migrations, applied in the window (step 2 below). |
| 3 | `feat/agent-commission-services` | Commission handlers subscribe to payment events **only** when peppers are set and a policy is in effect. Until then: `Commission handlers NOT subscribed (...)`; events wait in the outbox. |
| 4 | `feat/agent-admin-services`, then `fix/agent-gst-exclusive`, then `fix/agent-partial-refund-proportional` | Service changes only (the stacked commission branches). |
| 5 | `feat/agent-admin-routes-rest` | The remaining admin routes (pause, resume, terminate, codes, verify, reveal, referrals, commissions, payouts). |
| 6 | `feat/agent-platform-adapters` | Settings validators registered (bad admin values refused at entry). |
| 7 | the sealer switch (Shaaz's `SecretSealer`), from `main` after step 6 | Not written yet; must merge BEFORE any agent PII is stored (before step 10). |
| 8 | `feat/agent-routes-flagged` | Agent and member referral routes, **off** until `AGENT_PROGRAM_ENABLED=true`. |
| 9 | `docs/agent-contract-conformance` | Test and docs only. |

Before each merge: merge `origin/main` into the branch, resolve conflicts by
keeping both sides (expected in `agents.module.ts` imports and the PR-A
controller spec stand-ins), and rerun the checks.

---

## 2. Migrations: the settings seed (Shaaz's window)

**When:** after `feat/agent-settings-seed` is merged.

1. Shaaz applies the two pending migrations, which sort after every earlier one:
   `20261029130100_agent_program_settings_seed` and
   `20261029130200_agent_program_settings_approved`.
2. **Check:** `_prisma_migrations` has **42** rows, the two newest being those
   two; `prisma migrate diff` shows no drift; `platform_settings` holds the
   **18** agent keys with no SQL NULL (`payout.tax_withholding` is JSON
   `null`, on purpose).
3. **Undo:** none needed (data only, `ON CONFLICT DO NOTHING`). To change a
   value, a Super Admin uses the admin settings API. Never delete the rows and
   never edit the migration files.

---

## 3. `IDENTIFIER_HASH_PEPPERS` (Render)

**Before** anything that hashes a phone or IP runs for real. Format
`v1:<at least 32 characters>` (see `backend/.env.example`). Generated and
kept by Ishu.

1. Set it on Render; the service restarts.
2. **Check:** no `IDENTIFIER_HASH_PEPPERS is not set` warning; with step 2
   done: `Referral quote provided to the checkout.` and
   `Commission handlers subscribed to payment events.`
3. Test checkout (a test member, a fake code): with no code the price is
   the list price; with an approved fake code that does not exist the answer
   is 422 (unknown code), not 503.
4. **Undo:** removing it switches the quote and the subscription off at the
   next restart (events wait). **Never change or drop a pepper once hashes
   are stored** — rotation follows the pepper-rotation runbook in
   `SESSION_CONTEXT.md` (section 8b on the commission stack).

> ⚠️ Checkout fails **every** purchase on any quote error. The quote is
> provided only when peppers AND the six quote settings are present, which
> protects against both being missing; do not work around that guard.

---

## 4. `AGENT_PII_ENCRYPTION_KEY` (Render)

32 random bytes, base64 (44 characters). Generated and kept by Ishu.

1. Set it on Render **after** the sealer switch (step 7 of the merge order) is
   live, so the first value ever sealed is in the final format.
2. **Check:** no `AGENT_PII_ENCRYPTION_KEY is not set` warnings at start-up.
   A malformed value stops the API at start-up: if the deploy fails, fix the
   value (Render keeps the previous deploy running).
3. **Undo:** remove it → PII routes answer 503. **Never change it once
   anything is sealed with it** (sealed PAN / payout details / applicant
   phones would no longer open).

---

## 5. `AGENT_JWT_SECRET` (Render)

At least 32 random characters, different from `JWT_SECRET`. Generated and
kept by Ishu.

1. Set it on Render.
2. **Check:** no `AGENT_JWT_SECRET is not set` warning.
3. **Undo:** removing it → agent routes answer 503. Changing it signs every
   agent out (access tokens and refresh tokens stop working).

---

## 6. Dummy OTP for testing (Render) — in THIS order

Shaaz's Joi schema stops the **whole API** if `AGENT_OTP_DUMMY_ENABLED=true`
is set without a code, or in production without an allow-list. So:

1. `AGENT_OTP_DUMMY_PHONES` = the comma-separated E.164 test phones (chosen by
   Ishu; never real customers).
2. `AGENT_OTP_DUMMY_CODE` = exactly 6 digits (chosen by Ishu, never logged).
3. `AGENT_OTP_DUMMY_ENABLED=true` **last**.
4. **Check:** start-up log `Dummy sign-in codes are ON for N allow-listed
   phone(s)`; a phone outside the list gets 503 `OTP_DELIVERY_UNAVAILABLE`.
5. **Undo:** set `AGENT_OTP_DUMMY_ENABLED=false` first, then clear the others.

`agent.otp_resend_after_seconds` is seeded **30** (the OTP service's own
floor); the settings validator refuses anything lower.

---

## 7. `AGENT_PROGRAM_ENABLED=true` (Render) — LAST

Only after steps 2–6 and merge step 8.

1. Set it; the service restarts.
2. **Check (smoke tests, with an allow-listed test phone):**
   - `POST /agent/auth/otp/request` → 200 with `challengeId`.
   - `POST /agent/auth/otp/verify` with the dummy code → 200, `scope: APPLICANT`.
   - `POST /agent/application` with the applicant token → 201, `scope: AGENT`,
     status `PENDING_APPROVAL`.
   - Admin web: the agent appears; approve it (Partner Manager) → `ACTIVE`,
     a primary code issued.
   - `GET /agent/referral-links` → the code; `POST /referrals/codes/validate`
     with it → `valid: true`.
   - `GET /agent/config` → 200 (503 `AGENT_PROGRAM_UNAVAILABLE` means a
     setting or the commission policy is missing — see the log).
   - Every response carries `Content-Version: 1`; `Accept-Version: 2` → 406.
3. **Undo:** `AGENT_PROGRAM_ENABLED=false` → every agent and member referral
   route answers 404 at once. The quote and the commission handlers are NOT
   affected by the flag (by design): checkout discounts and commissions on
   existing attributions continue.

---

## 8. `CORS_ORIGINS` (Render)

Must list the Agent Portal origin (https://agent-nenjam-matrimony-app.vercel.app;
later `agent.nenjammatrimony.com`). **Check:** the portal's browser calls
succeed (no CORS error); `Retry-After` is readable on 429.

---

## 9. The daily job and `JOBS_SECRET` (Shaaz) — **To be confirmed**

Per Shaaz: a daily GitHub Actions job calls `POST /internal/jobs/daily` with
the `JOBS_SECRET` header; it runs the payment-outbox sweep and then our
`runDailyApproval()` (catching up everything past `hold_until`). **Not in git
yet.** When it lands: set `JOBS_SECRET` (Render and GitHub secrets, same
value), run the job once manually, **check** the outbox has no undelivered
events older than a day and approved commissions appear after their hold.

---

## 10. Business data (admin web, no deploy)

- **Plan prices** through admin plan drafts (Shaaz's flow). Prices exclude GST.
- **`payment.gst_rate_bps` stays 0** until the company is registered for GST;
  then a Super Admin sets it (commonly 1800). The commission is 10% of the
  taxable amount, so it does not change with the rate.

---

## 11. Real OTP before real commission

Dummy OTP lets anyone who knows an allow-listed number sign in as it. **Do
not let real agents earn real commission on dummy OTP.** Before inviting real
agents: real OTP (Firebase pay-as-you-go; not bought yet — the delivery
design is still open with Shaaz), then remove the dummy variables (step 6
undo).

---

## 12. Rollback, quick reference

| Problem | First action | Effect |
|---|---|---|
| Agent routes misbehave | `AGENT_PROGRAM_ENABLED=false` | Routes 404; quote and commissions continue |
| Checkout errors | Render: roll back to the previous deploy | Quote provider gone; list price |
| Commission handler errors | Render rollback (events stay in the outbox and are delivered again later; handlers are idempotent) | No commission changes |
| A bad setting value | Admin settings API (validators refuse invalid values) | Next request uses the new value |
| Wrong migration | **Stop. Never edit an applied migration.** Write a new one with Shaaz | — |

Known risk for Shaaz: the outbox retries the **oldest 50** undelivered events
each run with no backoff or attempt limit, so more than 50 permanently
failing events would block newer ones. Watch `payment_event_outbox` rows
with `delivered_at IS NULL` and a growing `attempts`.
