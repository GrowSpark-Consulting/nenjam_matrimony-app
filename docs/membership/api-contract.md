# Membership API contract (for the Flutter app)

Verified against the code on branch `feat/membership-foundation`. Every route needs
`Authorization: Bearer <Firebase ID token>` and is scoped to the caller — no route
takes another member's id. Money is always **integer paise** (`₹4,999` = `499900`),
dates are ISO-8601 UTC strings. Feature ids are stable strings
(see `GET /membership/plans → features`).

The backend is the only authority: the app must never treat a client-side flag,
a Razorpay SDK callback, or a cached value as proof that a member has a plan.
After any purchase or plan change, re-read `GET /membership/me`.

---

## Errors (all routes)

Nest's default shape: `{ "statusCode": n, "message": string | string[], "error": string }`.

| Status | When | How to tell / handle |
|---|---|---|
| 400 | Body failed validation (`message` is a **string array**), or a business rule (`message` is a string, e.g. "Gold is not available for 3 months.") | Show `message` |
| 401 | Missing/expired token | Existing `AuthInterceptor` refresh-and-retry |
| 403 **account** | Suspended/banned/deleted account (auth guard) | **No `code`** — "This account is no longer active…" |
| 403 **membership** | Plan doesn't include it / allowance used up (only when `limitsEnforced` is true) | **`code` starts with `MEMBERSHIP_`** — see below |
| 404 | Not found / not yours (deliberately indistinguishable) | Show `message` |
| 429 | Rate limit (per IP) | Back off and retry later |
| 502 | Razorpay rejected or returned something unexpected | "Couldn't start the payment, try again" |
| 503 | Payments not configured (checkout/verify) | Hide/disable buying; `checkoutAvailable` says so up front |

### Membership 403 body

Returned by interest send, photo upload, shortlist add and chat message send — **only when
`MEMBERSHIP_ENFORCEMENT_MODE=enforce`**. Today (shadow) none of these are ever returned.

```json
{
  "statusCode": 403,
  "error": "Forbidden",
  "code": "MEMBERSHIP_LIMIT_REACHED",
  "feature": "interests.send",
  "message": "You've used all 5 interests included in your Free plan this month. Upgrade to Gold to get more.",
  "plan": "FREE",
  "limit": 5,
  "used": 5,
  "resetsAt": "2026-10-31T18:30:00.000Z",
  "upgradeTo": "GOLD"
}
```

| `code` | Meaning | Fields present |
|---|---|---|
| `MEMBERSHIP_FEATURE_UNAVAILABLE` | Not in the plan (e.g. `chat.initiate` for Free) | `feature`, `plan`, `upgradeTo` |
| `MEMBERSHIP_LIMIT_REACHED` | Quota used up (`resetsAt` set) or cap reached (no `resetsAt`) | + `limit`, `used`, `resetsAt?` |
| `MEMBERSHIP_FAIR_USE_LIMIT` | "Unlimited" plan hit its fair-use cap — **never show an upgrade prompt** | + `limit`, `used`, `resetsAt`; `upgradeTo` is null |

`message` is always a complete sentence (current app builds already surface it via
`unwrapOrThrow`). `upgradeTo` is the cheapest plan **on sale now** that would help, or
`null` — show an upgrade button only when it is non-null.

---

## `GET /membership/plans`

```json
{
  "checkoutAvailable": false,
  "plans": [
    {
      "code": "FREE", "name": "Free", "description": "Create a profile, …", "tier": 0,
      "isFree": true, "version": 1, "durations": [],
      "entitlements": { "interests.send": { "limit": 5 }, "chat.initiate": false, "search.verified_only": true, "support.tier": "STANDARD", "…": "…" }
    },
    {
      "code": "GOLD", "name": "Gold", "tier": 1, "isFree": false, "version": 1,
      "durations": [ { "months": 3, "durationDays": 90, "bonusDays": 0, "priceInPaise": 399900, "currency": "INR" } ],
      "entitlements": { "…": "…" }
    }
  ],
  "features": [
    { "key": "interests.send", "kind": "quota", "section": "INTERESTS", "label": "Sending interests", "period": "MONTH" },
    { "key": "support.tier", "kind": "level", "section": "SUPPORT", "label": "Customer support", "levels": ["STANDARD","PRIORITY","DEDICATED"] },
    { "key": "search.verified_only", "kind": "boolean", "section": "VERIFICATION", "label": "Browsing verified profiles only", "requiredOnEveryPlan": true }
  ]
}
```

- Only **active** plans; `durations` lists only lengths **priced and on sale** (empty today — no prices set).
- Entitlement value shapes: `boolean`; `level` (string from `levels`, low→high);
  cap/quota `{ "limit": n | null, "perMonths"?: n, "fairUse"?: n }` — `null` = unlimited.
- Render plan comparisons from `features` + `entitlements`; don't hardcode feature lists.

## `GET /membership/me`

```json
{
  "plan": { "code": "GOLD", "name": "Gold", "tier": 1 },
  "source": "SUBSCRIPTION",
  "planVersion": 1,
  "subscription": {
    "id": "…", "planCode": "GOLD", "status": "ACTIVE",
    "startDate": "2026-10-27T06:00:00.000Z", "endDate": "2027-01-25T06:00:00.000Z",
    "months": 3, "autoRenew": false, "cancelledAt": null, "source": "PURCHASE"
  },
  "scheduled": [ { "id": "…", "planCode": "GOLD", "planName": "Gold", "startDate": "…", "endDate": "…" } ],
  "entitlements": { "…": "…" },
  "usage": [
    { "feature": "interests.send", "period": "MONTH", "used": 3, "limit": 100, "remaining": 97, "fairUse": false, "resetsAt": "2026-10-31T18:30:00.000Z" }
  ],
  "purchaseOptions": [
    { "planCode": "PLATINUM", "planName": "Platinum", "months": 3, "priceInPaise": 799900, "currency": "INR", "kind": "UPGRADE", "startsAt": "…", "endsAt": "…" }
  ],
  "effectiveCaps": { "profile.photos": 6, "shortlist.profiles": null, "search.saved_searches": null, "insights.profile_viewers_visible": null },
  "checkoutAvailable": false,
  "limitsEnforced": false
}
```

| `source` | Meaning | App behaviour |
|---|---|---|
| `FREE` | No paid plan in force (`subscription: null`) | Free UI |
| `SUBSCRIPTION` | Paid/granted plan in force | Show plan + `endDate` |
| `LEGACY` | A pre-catalogue subscription is in force; `entitlements: null`, no limits apply | Show plan name + `endDate`; **no limits, no upgrade prompts** |
| `UNAVAILABLE` | Catalogue unreadable (server fails open); `entitlements: null` | Don't show limits or prompts |

- `usage` covers every metered feature, including ones not enforced yet. While
  `limitsEnforced` is `false`, show allowances as informational at most — nothing is
  being counted against the member. Usage shows the real allowance only (shadow-mode
  observation is never shown and never charged).
- Periods are IST calendar days/months; `resetsAt` is the exact reset instant.
- `purchaseOptions[].kind`: `NEW` and `UPGRADE` start now; `RENEWAL`/`DOWNGRADE` are
  **queued** to `startsAt`. Say so before payment ("Starts on 25 Jan").
- **Caps: use `effectiveCaps`, not `entitlements`.** `effectiveCaps` is what the server
  will actually hold the member to *right now*: the plan's limit under enforcement
  (photos 5/15/20, shortlist 10/∞/∞), otherwise the pre-membership cap (photos **6**,
  others `null` = no cap). `entitlements` shows the plan's own numbers (for marketing).
  Counting what the member holds is the app's own data.

## `GET /membership/history`

Newest first, at most 50. One item per purchase or admin grant:

```json
[{
  "id": "…", "plan": { "code": "GOLD", "name": "Gold" }, "months": 3,
  "status": "ACTIVE", "source": "PURCHASE",
  "startDate": "…", "endDate": "…", "priceInPaise": 399900, "currency": "INR",
  "activatedAt": "…", "cancelledAt": null, "cancellationReason": null, "createdAt": "…",
  "payments": [ { "id": "…", "orderId": "order_…", "paymentId": "pay_…", "amountInPaise": 399900,
                  "currency": "INR", "status": "SUCCESS", "paidAt": "…", "refundedAmount": 0, "refundedAt": null } ]
}]
```

`status` may be `PENDING` (checkout started, not paid — show "awaiting payment" or hide),
`ACTIVE`, `EXPIRED`, `CANCELLED` (`cancellationReason`: `REFUNDED` / `REVOKED`). Legacy
refunded payments may show `refundedAmount: 0` (the old schema didn't record amounts).

## `POST /membership/subscription/cancel`

No body. `200 { "cancelled": 1, "accessUntil": "…" }`; `404` if no paid plan is active.
Stops renewal only — **access continues to `accessUntil`; nothing is refunded**. Because
auto-renew is not implemented (purchases are one-time), this changes nothing a member can
see today: **don't expose it in the app until recurring billing exists.**

## `POST /membership/checkout`

Request: `{ "planCode": "GOLD" | "PLATINUM", "months": 3 }` (extra fields → 400).

Response `201`:

```json
{ "subscriptionId": "…", "orderId": "order_…", "amountInPaise": 399900, "currency": "INR",
  "keyId": "rzp_live_…", "plan": { "code": "GOLD", "name": "Gold" }, "months": 3 }
```

The price is computed on the server from the catalogue; the client never sends an amount.
Open Razorpay Checkout with `key: keyId`, `order_id: orderId`, `amount`, `currency`.
Nothing is granted yet (`PENDING`). Errors: 400 not on sale, 502 Razorpay, 503 not configured.

## `POST /membership/checkout/verify`

Request: exactly the Razorpay success-handler values:
`{ "orderId": "order_…", "paymentId": "pay_…", "signature": "<64 hex>" }`.

The server checks the signature, then **fetches the payment from Razorpay** and activates only
if Razorpay reports it `captured`, for this order, at the checkout amount and currency.

Response `200`: `{ "outcome": "...", "subscriptionId": "…", "status": "ACTIVE" | "PENDING" | …, "startDate": "…" | null, "endDate": "…" | null }`
(dates only once the plan is really active).

| `outcome` | Granted? | App should |
|---|---|---|
| `ACTIVATED`, `ALREADY_APPLIED` | Yes (now, or queued — compare `startDate`) | Success; refresh `/membership/me` |
| `AWAITING_CAPTURE`, `PENDING_CONFIRMATION` | Not yet | "Payment received, activating…"; poll `/membership/me` (the webhook activates it) |
| `NOT_PAID`, `REFUNDED` | No | Payment failed |
| `AMOUNT_MISMATCH`, `PAID_NOT_ACTIVATED`, `UNKNOWN_ORDER` | No | "Contact support" (operators are alerted via logs) |

Errors: 400 bad signature / payment belongs to another order, 404 not your order, 503.
Safe to retry; a retry after activation returns `ALREADY_APPLIED`.

If the member closes the Razorpay sheet or it reports failure, **do not** call verify; the
`PENDING` checkout simply never activates.
