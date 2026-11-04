# Membership plans — Free, Gold, Platinum

Source of requirements: `Nenjam_Membership_Plans.pdf` (3 pages), with one product
correction: **"Verified profiles only" browsing is available on every plan, Free
included** (the PDF marks it paid). Safety and privacy are never paywalled.

This is the backend foundation: plan catalogue, entitlement engine, usage metering,
subscription lifecycle and the Razorpay boundary. There is **no admin panel and no
admin HTTP API** yet. The services the admin panel will wrap exist, and their
future API is specified at the end of this document.

Companion documents:
- [api-contract.md](api-contract.md) — exact request/response/error contracts for the app.
- [flutter-integration-plan.md](flutter-integration-plan.md) — what the app needs, in order.
- [production-readiness.md](production-readiness.md) — pricing decisions, Razorpay sandbox
  checklist, deployment, monitoring, rollback, and the preconditions for `enforce`.
- [razorpay-test-mode.md](razorpay-test-mode.md) — step by step: test keys on Render,
  the dashboard settings, putting prices on sale, test purchases, and going live later.

---

## 1. Status at a glance

| Area | State |
|---|---|
| Plan catalogue (Free/Gold/Platinum, versioned entitlements, durations) | **Live** — created by migration `20261027120100_membership_catalog` |
| Prices | **Not set.** The PDF has none; every paid duration ships unpriced and inactive (not purchasable) |
| Entitlement engine + usage metering | **Live**, in `shadow` mode by default (records + logs, denies nothing) |
| Enforcement at existing features | Interests (monthly quota), photo uploads (cap), shortlist (cap), starting a chat |
| Member API | `GET /membership/plans`, `/me`, `/history`; `POST /membership/subscription/cancel` — see [api-contract.md](api-contract.md) |
| Checkout + Razorpay webhook | **Built, not live**: answers 503 until Razorpay keys are set; verify activates only payments Razorpay reports captured; never exercised against the real Razorpay API |
| Expiry sweep | Scheduler cron, hourly (bookkeeping only — access already ends at `endDate`) |
| Admin panel / admin API | **Not built** (by design). Internal services ready — see §10 |
| Flutter app | **Unchanged.** Still shows the static premium page; consumes none of this yet |

---

## 2. Architecture

```
apps/api/src/modules/
├── entitlements/                 READ + ENFORCE (imported by features)
│   ├── catalog/feature-catalog.ts   the feature registry: ids, kinds, periods, validation
│   ├── catalog/plan-catalog.service.ts  cached catalogue (stale-while-revalidate, warmed at boot)
│   ├── services/membership.service.ts   THE engine: resolve / requireFeature / consume / enforceCap
│   ├── repositories/usage.repository.ts atomic counters + per-item dedupe + cap locks
│   └── services/entitlement.service.ts  legacy "any paid plan?" probe (privacy settings) — unchanged
└── subscription/                 WRITE (nothing imports it back)
    ├── services/subscription-lifecycle.service.ts  state machine; the only writer of subscription status
    ├── services/plan-catalog-admin.service.ts       admin-ready catalogue changes (no HTTP surface)
    ├── services/checkout.service.ts, razorpay.service.ts, razorpay-webhook.service.ts
    └── controllers/  plans (member API), checkout, razorpay-webhook
libs/database/src/entitlements/
    ├── premium-entitlement.ts   shared "active paid subscription" filter (cards, privacy)
    └── subscription-expiry.ts   shared expiry sweep (API + scheduler)
apps/scheduler/src/cron/subscription-expiry.cron.ts
```

### Data model (all additive; migration `20261027120000_membership_foundation`)

| Table | Role |
|---|---|
| `subscription_plans` (existing, extended) | One row per plan. `tier` (0/1/2) ranks plans; `is_active` = on sale. Legacy `price_inr`/`duration_days`/`features`/`limits` kept, unused |
| `subscription_plan_durations` (new) | The **current** price list: months, days, bonus days, price (paise, nullable = unpriced), active |
| `subscription_plan_versions` (new) | **Immutable** entitlement snapshots (`entitlements` JSON keyed by feature id), `effective_from`, author, note |
| `user_subscriptions` (existing, extended) | Pins `plan_version_id`; snapshots `price_in_paise`/`currency`; `source` (PURCHASE/ADMIN_GRANT); `activated_at`, `cancelled_at`, `cancellation_reason` |
| `subscription_events` (new) | Append-only lifecycle history, with actor |
| `payment_transactions` (existing, extended) | `currency`, `refunded_amount`, `refunded_at` |
| `payment_webhook_events` (new) | Idempotency for provider webhooks; ids + payload **hash** only (no PII) |
| `membership_usage_counters` (new) | Usage per (user, feature, period) |
| `membership_usage_items` (new) | Items already charged in a period (per-item features) |
| `audit_logs` (existing) | Every catalogue change and admin lifecycle action |

DB-level guards (CHECK constraints): an active duration must be priced; prices > 0;
usage never negative; version > 0; entitlements is a JSON object.

---

## 3. The feature catalogue

Feature **definitions** (what an id means, how it is metered) live in code:
`feature-catalog.ts`. Plan **values** live in the database and change without a deploy.
Adding a feature = one registry entry + the code that enforces it; never a new column.

Value kinds: `boolean`; `level` (ordered enum); `cap` `{limit}` = most held at once;
`quota` `{limit}` per period (`DAY`/`MONTH` on the IST calendar, or `SUBSCRIPTION` =
the purchase's own pool). `limit: null` = unlimited; an unlimited quota may carry a
`fairUse` hard cap. `{limit: 60, perMonths: 3}` scales with plan length.

Version 1 (as shipped):

| Feature id | Free | Gold | Platinum | Enforced today? |
|---|---|---|---|---|
| `profile.photos` (cap) | 5 | 15 | 20 | **Yes** — photo upload |
| `interests.send` (month) | 5 | 100 | 300 | **Yes** — send interest |
| `shortlist.profiles` (cap) | 10 | ∞ | ∞ | **Yes** — shortlist add |
| `chat.initiate` | ✗ | ✓ | ✓ | **Yes** — first message in a conversation |
| `chat.reply` (required) | ✓ | ✓ | ✓ | always free |
| `chat.accept_from_free_members` | ✗ | ✗ | ✓ | **Yes** — lets free members write first |
| `search.verified_only` (required) | ✓ | ✓ | ✓ | never gated (filter is client-side) |
| `interests.respond`, `search.basic_filters` (required) | ✓ | ✓ | ✓ | never gated |
| `discovery.daily_recommendations` (day) | 5 | 20 | ∞ | entitlement only |
| `discovery.profile_views` (day, per profile) | 30 | ∞ | ∞ | entitlement only |
| `search.saved_searches` (cap) | 1 | 5 | ∞ | feature not built |
| `contacts.unlocks` (per plan, per profile) | 0 | 60 per 3 months | 200 | feature not built |
| `horoscope.full_jathagam` / `.detailed_report` | ✗ | ✓ | ✓ | feature not built |
| `horoscope.astrologer_minutes` (month) | 0 | 0 | 15 | feature not built |
| `visibility.boost_days` (month) | 0 | 7 | 15 | feature not built |
| `calls.voice` / `calls.video` | ✗/✗ | ✓/✗ | ✓/✓ | feature not built |
| `chat.read_receipts` | ✗ | ✓ | ✓ | not gated (receipts exist for all today) |
| `privacy.incognito`, `visibility.featured` | ✗ | ✗ | ✓ | feature not built |
| `search.power_filters`, `discovery.mutual_matches`, `interests.personal_note`, `profile.video_intro`, `profile.full_details`, `photos.private_access`, `contacts.whatsapp_share` | ✗ | ✓ | ✓ | not gated / not built |
| levels: `profile.badge`, `visibility.search_priority`, `insights.*`, `support.tier`, `verification.id_review` | lowest | mid | highest | entitlement only |

The full list (43 ids) and exact values are in the migration and are asserted line by
line against the PDF in `entitlements/tests/feature-catalog.spec.ts`.

**Never configurable** (absent from the registry, so no config can gate them): block,
report, hide profile, photo privacy, contact privacy, number masking, government-ID
verification. `ALLOW_FREE_PRIVACY_CONTROLS` stays `true` permanently. Features marked
*required* must be granted by every plan — the validator refuses any version that
turns one off.

"Separate products" (Nenjam Assist, Profile Highlighter, Contact Packs, standalone
Horoscope Report) are **not** modelled: no add-on architecture exists. Contact Packs
and Highlighter map naturally onto extra `contacts.unlocks` / `visibility.boost_days`
grants later.

---

## 4. Enforcement modes and rollout

`MEMBERSHIP_ENFORCEMENT_MODE` (API service env):

| Mode | Behaviour |
|---|---|
| `off` | No membership work at all. Exactly pre-membership behaviour (incl. the old 6-photo cap). |
| `shadow` (**default**) | Plans resolved and usage recorded **off the request path**, in separate `shadow:<feature>` counters that enforcement never reads; would-be denials logged as `[membership:shadow] would deny <feature> for user <id> on <PLAN> (...)`. Nothing is denied; the legacy 6-photo cap still applies. Switching to `enforce` therefore starts every member on a fresh allowance. |
| `enforce` | Plan limits and paid features enforced with structured 403s. |

Why `shadow` and not `enforce`: today every member is effectively Free and nothing can
be bought, so enforcing would remove chat initiation, unlimited interests and
shortlisting from every existing member overnight with no upgrade path.

**Do not switch to `enforce` until all of these hold:**
1. Prices set and durations activated (§10, `setDuration`).
2. Razorpay keys + webhook configured and the sandbox checklist (§6) passed.
3. The Flutter app ships the paywall: it reads `/membership/me` and `/membership/plans`,
   handles the 403 bodies below, shows Free limits, opens Razorpay Checkout and calls
   `/membership/checkout/verify`. Current app builds will show only the 403 `message`.
4. The Flutter photo picker no longer hard-caps at 6 (Gold 15 / Platinum 20).
5. Shadow logs reviewed for a week to size the impact on existing members.

### 403 contract (enforce mode)

```json
{
  "statusCode": 403, "error": "Forbidden",
  "code": "MEMBERSHIP_LIMIT_REACHED",       // | MEMBERSHIP_FEATURE_UNAVAILABLE | MEMBERSHIP_FAIR_USE_LIMIT
  "feature": "interests.send",
  "message": "You've used all 5 interests included in your Free plan this month. Upgrade to Gold to get more.",
  "plan": "FREE", "limit": 5, "used": 5,
  "resetsAt": "2026-10-31T18:30:00.000Z",    // quotas only
  "upgradeTo": "GOLD"                        // cheapest plan ON SALE that helps; null if none
}
```

### Fail-open

If the catalogue can't be read (Free plan missing, DB error), members are treated as
before membership existed — never locked out, and still held to the pre-membership caps
(6 photos). A paid subscription the resolver can't interpret also fails open rather than
falling to Free.

**Legacy subscriptions** (rows from before plan versions, e.g. an old SILVER/GOLD
purchase or a hand-made test row) resolve as `LEGACY`: no plan limits apply while they
are in force. What they were sold as isn't recorded (old GOLD advertised unlimited
interests and contacts), so they are never reinterpreted under today's terms. How to map
them is an open decision (production-readiness.md, P4).

---

## 5. Policies

- **No subscription row = Free.** Nobody is blocked for lacking a record.
- **Which plan applies:** the highest-tier subscription that is `ACTIVE` with
  `startDate <= now < endDate`. Access ends at `endDate` even if the status hasn't
  been flipped to `EXPIRED` yet.
- **Upgrade** (higher tier than anything held): starts immediately, overlapping the
  lower plan; the lower plan **resumes** if it outlives the upgrade. No proration;
  nothing already bought is shortened.
- **Renewal / downgrade:** queued to start when the member's last same-or-higher plan
  ends.
- **Cancellation** (`POST /membership/subscription/cancel`): stops renewal only;
  access continues to `endDate`. No refund. (Auto-renew itself isn't implemented —
  purchases are one-time orders — so `autoRenew` is always false today.)
- **Refund** (via Razorpay webhook): partial refunds accumulate with no access change;
  the refund completing the full amount marks the payment `REFUNDED` and the
  subscription `CANCELLED` (access ends). A refund that arrives before its capture
  webhook closes the purchase; the late capture never activates it.
- **Admin extension** pushes plans queued behind the extended one back by the same
  number of days, so an extension never overlaps (and uses up) a paid renewal.
- **Failed payment:** recorded; grants nothing; the subscription stays `PENDING` so a
  retry on the same order can still succeed. Abandoned `PENDING` rows are harmless
  (never grant access) and are not cleaned up yet.
- **Usage periods:** IST calendar day and month for everyone; per-plan pools
  (`contacts.unlocks`) belong to the purchase and reset with a new one. Monthly
  counters are shared across plan changes (upgrading mid-month keeps what was used).
- **Configuration changes** never edit a version: a change is a new version.
  - New purchases (and Free members) get the version in force at checkout time.
  - Existing subscribers keep the version they bought for the rest of their term.
  - `applyToExistingSubscribers: true` moves them forward **only where the new version
    reduces nothing relative to what each bought** (e.g. Gold interests 100 → 150 applies
    to everyone at once; 100 → 80 applies to new purchases only).
  - `effectiveFrom` can schedule a version; backdating is refused.
  - Free has no purchases, so a Free change applies to all Free members at
    `effectiveFrom` — required features can never be removed.
- **Prices:** the duration table is the current list; each subscription and payment
  snapshots what was charged, never rewritten.
- **Deactivating a plan** stops new sales only; existing subscriptions run to their end.
  Free can never be deactivated.

---

## 6. Payments (Razorpay)

Flow: `POST /membership/checkout {planCode, months}` → Razorpay order at the current
price + `PENDING` subscription (pinned version, price snapshot) + `PENDING` payment →
client opens Razorpay Checkout (`key` = `keyId`, `order_id` = `orderId`) →
`POST /membership/checkout/verify {orderId, paymentId, signature}`: signature checked,
then the payment is **fetched from Razorpay** and activates only if `captured`, for this
order, at the checkout amount/currency (authorized-only or Razorpay unreachable → nothing
granted; the webhook activates later). The webhook activates the same order
independently; whichever lands first wins, the other is a no-op.

Webhook: `POST /payments/razorpay/webhook` — no Firebase auth; authenticated by
`X-Razorpay-Signature` (HMAC of the raw body; `main.ts` keeps `rawBody`). Subscribe to
`payment.captured`, `order.paid`, `payment.failed`, `refund.processed`. Each delivery is
recorded — by `X-Razorpay-Event-Id` **and** by the hash of the signed body (the header
isn't signed, so a replay under a fresh id is still caught) — in the same transaction
that applies it: duplicates answer 200 and do nothing; failures answer 5xx and roll back
so Razorpay's retry works. Webhook activations check amount and currency; a mismatch
never activates.

Env (API service): `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`.
Without them checkout/webhook answer 503 and the app boots normally.

**Not verified:** nothing here has been run against the real Razorpay API. Signature
checks are unit-tested against independently computed HMACs; order creation against a
mocked HTTP layer; activation, idempotency, refunds and races against a real Postgres.

The sandbox checklist (test keys only) is in
[production-readiness.md §2](production-readiness.md#2-razorpay-readiness).

Remaining payment work: recurring billing (Razorpay Subscriptions) for real
auto-renew; invoices/GST receipts; abandoned-checkout cleanup.

---

## 7. Member API (all require a Firebase token)

| Route | Purpose |
|---|---|
| `GET /membership/plans` | Active plans, their current entitlements, durations on sale, feature metadata, `checkoutAvailable` |
| `GET /membership/me` | Current plan, subscription, queued plans, entitlements, usage vs every quota with `resetsAt`, `limitsEnforced` |
| `GET /membership/history` | Purchases/grants with payments (invoice data) |
| `POST /membership/subscription/cancel` | Stop renewal; access until end date |
| `POST /membership/checkout` | Start a purchase (503 until configured) |
| `POST /membership/checkout/verify` | Confirm a payment (idempotent) |

All additive; no existing route or response changed shape. Exact shapes, every error and
every `outcome`: [api-contract.md](api-contract.md).

---

## 8. Using the engine in a new feature

```ts
// boolean feature
const m = await this.membership.resolve(userId);
await this.membership.requireFeature(m, 'calls.video');

// metered — inside the action's own transaction, so a failed action costs nothing
await this.membership.consume('contacts.unlocks', { userId, tx, itemKey: profileId, membership: m });

// cap — locked + counted inside the transaction under enforce
await this.membership.enforceCap('search.saved_searches', {
  userId, tx, membership: m, count: (db) => db.savedSearch.count({ where: { userId } }),
});
```

Rules: resolve **before** opening a transaction when you can (or pass `tx` — never call
root-client queries from inside a transaction; that starves the pool, see
`plan-catalog.service.ts`). Never loop `resolve` over a list of other members. Never
gate block/report/privacy/verification.

---

## 9. Deployment

The full runbook (backup, read-only prechecks, migrate-before-deploy, env vars,
verification, monitoring, rollback) is
[production-readiness.md §3–§5](production-readiness.md#3-deployment-shadow-mode--no-member-is-restricted).
In short: back up → `prisma migrate deploy` (two additive migrations; legacy SILVER/GOLD
plan, subscription and payment rows are left byte-identical; SILVER is deactivated, not
deleted) → deploy the API in `shadow` → deploy the scheduler. `pnpm db:seed` no longer
writes plans; it only prints the catalogue.

Rollback: `MEMBERSHIP_ENFORCEMENT_MODE=off` (no deploy). There is **no down-migration**;
the migrations are additive and previous code ignores them, so leaving them in place is
the schema rollback — restoring the pre-migration backup is the only way to remove them.

---

## 10. Future admin panel

### Reusable services (exported by `SubscriptionModule` / `EntitlementsModule`)

| Service.method | Does | Audit action |
|---|---|---|
| `PlanCatalogAdminService.publishVersion` | New entitlement version (validated, optional schedule, optional apply-to-existing) | `membership.plan.version.publish` |
| `PlanCatalogAdminService.setDuration` | Create/edit a duration: price, days, bonus, active | `membership.plan.duration.set` (before/after) |
| `PlanCatalogAdminService.setPlanActive` | Start/stop selling a plan (Free refused) | `membership.plan.status.set` |
| `PlanCatalogAdminService.updatePlanDisplay` | Name, description, order | `membership.plan.display.set` |
| `SubscriptionLifecycleService.grant / extend / revoke` | Lifecycle exceptions (reason required) | `membership.subscription.grant/extend/revoke` |
| `SubscriptionLifecycleService.expireLapsed` | Manual expiry sweep | events only |
| `PlanCatalogService.refresh` / `MembershipService.summarize` | Read catalogue / a member's plan + usage | — |

### Authorization — enforced inside the services today

Every write method checks, **inside its own transaction**, that `actorId` is an ACTIVE,
undeleted staff user with an **active** `AdminAccount` whose **roles** grant the permission
(RBAC — see [docs/admin/README.md](../admin/README.md);
`admin/rbac/assert-admin-permission.ts`):

| Service method | Permission |
|---|---|
| `SubscriptionLifecycleService.grant` | `subscription.grant` |
| `SubscriptionLifecycleService.extend` | `subscription.extend` |
| `SubscriptionLifecycleService.revoke` | `subscription.cancel` |
| `PlanCatalogAdminService.publishVersion`, `.setDuration` (prices), `.setPlanActive` | `plan.publish` — members see the change |
| `PlanCatalogAdminService.updatePlanDisplay` | `plan.edit` |

All of them also require a reason (≥ 3 characters) and write an `AuditLog` row in the same
transaction (a failed audit write rolls the change back — integration-tested). The legacy
`AdminAccount.permissions` JSON is no longer read, so the old seeder's placeholder admin has
no access. A future controller can't skip these checks by forgetting a guard.

### Before any admin endpoint exists

`RolesGuard`, `AdminOnlyGuard`, `@Roles()` and `@Public()` are **empty stubs** (verified):
nothing reads their metadata. An admin controller must therefore:
1. Use `FirebaseAuthGuard` (real) **plus** a real admin guard — implement `AdminOnlyGuard`
   to load the caller's role/status/`AdminAccount` and check the route's permission.
2. Pass the authenticated caller's id as `actorId` (never from the request body).
3. Never accept raw catalogue JSON except through `publishVersion`'s validator.
4. Keep refunds in the Razorpay dashboard (the webhook applies them).
5. Consider a second admin's confirmation for price and entitlement changes (not built).

### Recommended endpoints

| Endpoint | Permission |
|---|---|
| `GET /admin/membership/plans` (incl. inactive, all versions) | `membership` → `read` |
| `POST /admin/membership/plans/:code/versions` | `membership` → `plans.write` |
| `PUT /admin/membership/plans/:code/durations/:months` | `membership` → `prices.write` |
| `PATCH /admin/membership/plans/:code` (active, display) | `membership` → `plans.write` |
| `GET /admin/membership/users/:id` (plan, usage, subscriptions, events, payments) | `subscriptions` → `read` |
| `POST /admin/membership/users/:id/grants` · `/subscriptions/:id/extend` | `subscriptions` → `write` |
| `POST /admin/membership/subscriptions/:id/revoke` | `subscriptions` → `cancel` |
| `GET /admin/payments?status=&from=&to=` · `GET /admin/payments/webhooks` | `payments` → `read` |
| `GET /admin/audit?entity=SubscriptionPlan…` | `audit` → `read` |

Read services for those endpoints (subscription/payment/audit listings with filters) are
not built yet; the tables and indexes they need exist.

---

## 11. Tests

- Unit (run in CI): `pnpm test`. Membership specs: `entitlements/tests/*`,
  `subscription/tests/*`, and `*.membership.spec.ts` beside interests, chat, shortlist,
  photos.
- Integration (real Postgres; skipped unless `INTEGRATION_DATABASE_URL` is set):
  `entitlements/tests/membership-usage.integration.spec.ts` (concurrency) and
  `subscription/tests/membership-lifecycle.integration.spec.ts`. Use a throwaway
  database/schema with every migration applied:
  ```bash
  DATABASE_URL="postgresql://…/scratch?schema=itest_membership" pnpm prisma migrate deploy
  INTEGRATION_DATABASE_URL="postgresql://…/scratch?schema=itest_membership" pnpm test -- integration.spec
  ```
  Never point either at the shared Neon database.
