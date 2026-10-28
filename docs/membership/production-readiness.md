# Membership — production readiness

What must happen, in order, to ship the membership foundation safely, and what
must be true before limits are ever enforced. Pair with [README.md](README.md)
(design/policies) and [api-contract.md](api-contract.md).

## 1. Decisions needed before anything can be sold

| # | Decision | Why it matters | Current state |
|---|---|---|---|
| P1 | **Prices** for Gold 3 / 6 months and Platinum 3 / 6 / 12 months (paise, incl. or excl. GST) | Nothing is purchasable without them | All durations unpriced + inactive |
| P2 | **Bonus days** on longer plans ("bonus weeks", PDF p.3) | Changes the term members get | 0 everywhere |
| P3 | **Gold contact pool**: PDF table says 60 per 3-month plan, PDF principles say "about 50" | Billing promise | 60 (table) |
| P4 | **Legacy subscribers**: how existing pre-catalogue SILVER/GOLD subscriptions (if any exist in production) should map | Previously purchased benefits | No limits while in force (`LEGACY`) — never reduced |
| P5 | **"Let free members contact you"**: a Platinum toggle the member controls, or always on? | Who can message whom | Always on for Platinum |
| P6 | **Payment records on account deletion**: deleted with the account today (pre-existing cascade). Tax/GST retention may require keeping them | Legal retention | Deleted with the account |
| P7 | **Web purchases**: support via Razorpay `checkout.js` or hide buying on web | Flutter scope | — |

Prices are set with `PlanCatalogAdminService.setDuration` by an admin whose role grants
`plan.publish` (audited). There is no HTTP surface for it yet; until the admin panel's
plan screens exist, use a reviewed one-off script run by an engineer.

## 2. Razorpay readiness

Verified in code and tests (unit + real Postgres):

- Amount computed server-side from the catalogue; integer paise; INR; the client never sends an amount.
- Order ↔ subscription: one PENDING subscription + one PENDING payment per order, created in one transaction after Razorpay returns the order (amount/currency of the returned order checked).
- Checkout signature (`order|payment`, HMAC-SHA256, constant-time compare).
- **Verify trusts only Razorpay's record**: fetches the payment; activates only if `captured`, for this order, at the checkout amount and currency. Authorized-only → no access; Razorpay unreachable → no access (webhook activates later).
- Webhook signature over the raw body; 401 on mismatch, 503 when unconfigured.
- Duplicate deliveries: deduplicated by event id **and** by signed-body hash (a replay with a forged event id is a duplicate) — same transaction as the state change.
- Out-of-order: a refund arriving before its capture closes the purchase; the late capture never activates it. Capture after a failure still activates. Duplicate captures/`order.paid` activate once (conditional state transitions).
- Amount/currency mismatch on capture → never activates, flagged, logged at error.
- Replayed verify calls → `ALREADY_APPLIED`.

**Not verified — nothing has run against Razorpay itself.** Sandbox checklist (test keys only, never production credentials):

1. Razorpay Dashboard → payment capture set to **automatic** (otherwise payments stay `authorized` and are auto-refunded; the app would correctly never activate them).
2. Configure webhook URL `https://<api>/payments/razorpay/webhook`, secret = `RAZORPAY_WEBHOOK_SECRET`, events `payment.captured`, `order.paid`, `payment.failed`, `refund.processed`.
3. Buy Gold with a test card → `/verify` → `outcome: ACTIVATED`; `/membership/me` shows Gold.
4. Webhook for the same payment arrives → one `payment_webhook_events` row; still one `ACTIVATED` event.
5. "Resend" the webhook from the dashboard → 200, `DUPLICATE`.
6. Declined test card → `PAYMENT_FAILED` event, still Free; retry on the same order succeeds.
7. Full refund from the dashboard → subscription `CANCELLED`, member back to Free; partial refund → still active.
8. Tamper a webhook body → 401. Unset the webhook secret → 503.
9. Confirm `refund.processed` payloads include the `payment` entity (the code also finds the payment by id without it).

Not built: recurring billing / real auto-renew (Razorpay Subscriptions), invoices / GST receipts, abandoned-checkout cleanup.

## 3. Deployment (shadow mode — no member is restricted)

Migrations are applied by hand with `prisma migrate deploy`; nothing runs them on build/start.

1. **Backup**: create a Neon branch (or confirm point-in-time restore) of the production database immediately before migrating. There is **no tested down-migration**; restore-from-backup is the only way to undo a migration.
2. **Read-only prechecks** on production (answer P4 with real data):
   ```sql
   SELECT version();                                   -- Postgres ≥ 13 (gen_random_uuid, enum ADD VALUE in a transaction)
   SELECT name, is_active, price_inr, duration_days FROM subscription_plans;
   SELECT p.name, s.status, count(*) FROM user_subscriptions s JOIN subscription_plans p ON p.id = s.plan_id GROUP BY 1, 2;
   SELECT status, count(*) FROM payment_transactions GROUP BY 1;
   ```
   Any ACTIVE rows → those members resolve to `LEGACY` (no limits) until P4 is decided.
3. **Migrate**: `pnpm prisma:migrate:deploy` with production `DATABASE_URL` (2 migrations; additive; the
   catalogue one is idempotent). Old code keeps working against the new schema, so
   migrate **before** deploying code. Verified on a copy shaped like production: legacy
   plan/subscription/payment rows are byte-identical before and after.
4. **Deploy the API** with env: `MEMBERSHIP_ENFORCEMENT_MODE=shadow` (or unset — same).
   Leave `RAZORPAY_*` unset until §2 passes (checkout/webhook then answer 503).
5. **Deploy the scheduler** service (the expiry cron runs hourly; access is date-based
   anyway, so this only keeps statuses tidy). Confirm the scheduler service actually exists
   on the current host — unverified since the move to Render.
6. **Verify**: `GET /health` 200; API logs have **no** `Plan catalogue not loaded at boot`
   and **no** `FREE plan or its current version is missing`; `GET /membership/me` with a
   member token → `source: "FREE"`, `limitsEnforced: false`, `effectiveCaps["profile.photos"]: 6`.
   Existing flows unchanged: send an interest, start a chat, upload a 6th photo (refused with
   the old message), shortlist.

### Environment variables

| Var | Service | Default | Notes |
|---|---|---|---|
| `MEMBERSHIP_ENFORCEMENT_MODE` | API | `shadow` | `off` \| `shadow` \| `enforce`; invalid values fall back to `shadow` |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | API | unset | Checkout + verify; unset → 503 |
| `RAZORPAY_WEBHOOK_SECRET` | API | unset | Webhook; unset → 503 |

## 4. Monitoring and alerting

There is no metrics stack (the `@app/logger` lib is a no-op); use the host's log search.
Alert on:

| Log text | Severity | Meaning |
|---|---|---|
| `FREE plan or its current version is missing` | Page | Catalogue broken — everyone fails open (unrestricted) |
| `Membership resolution failed` | Warn if sustained | DB errors; members fail open |
| `NOT activated` / `AMOUNT_MISMATCH` | Page | A payment's amount didn't match its order |
| `needs manual review` (`PAID_NOT_ACTIVATED`) | Page | Money taken, no plan — refund or grant manually |
| `Razorpay payment lookup failed` / `order creation failed` | Warn | Razorpay degraded; verify falls back to the webhook |
| `predates plan versions` | Info | A `LEGACY` member was resolved |
| `[membership:shadow] would deny` | Info | Volume per feature = impact estimate for enforcement |

Daily SQL checks: `PENDING` subscriptions older than a day with a `SUCCESS` payment
(should be none); `payment_webhook_events` rows per day; `subscription_events` by type.

## 5. Rollback

- **Behaviour**: set `MEMBERSHIP_ENFORCEMENT_MODE=off` and restart → every membership
  check is skipped (exact pre-membership behaviour, legacy 6-photo cap included). No code
  deploy needed. `shadow` → `off` changes nothing a member can see.
- **Payments**: unset `RAZORPAY_*` → checkout and webhook answer 503 (in-flight Razorpay
  payments will retry their webhooks for ~24h; re-enable within that window or reconcile).
- **Code**: redeploying the previous build is safe — it ignores the new tables/columns.
- **Schema**: no down-migration exists or has been tested. The migrations are additive, so
  leaving them in place is the rollback. Reverting schema = restoring the §3.1 backup
  (loses writes made since).

## 6. Before `MEMBERSHIP_ENFORCEMENT_MODE=enforce` (all required)

1. P1–P5 decided; prices set and durations activated.
2. §2 sandbox checklist passed with test keys; production keys + webhook configured.
3. The Flutter release implementing [flutter-integration-plan.md](flutter-integration-plan.md)
   steps 2–5 is the minimum supported app version (paywall, 403 handling, `effectiveCaps`
   photo limit, purchase + verify + refresh).
4. At least a week of shadow logs reviewed (how many members would hit each limit).
5. A member-facing announcement of the Free limits.
6. On switching: allowances start fresh (shadow usage is never charged). Watch the §4
   alerts and 403 volume for the first hours; `off`/`shadow` is the instant way back.
