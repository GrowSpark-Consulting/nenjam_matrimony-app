# Agent / Partner Program — frontend handoff

For: Dhatri (Agent Portal website and Flutter app).
From: Ishu (agent-program backend).
State as of: 27 Oct 2026.

The full API contract is `docs/agent-program/agent-api.openapi.yaml`. This
page is the friendly version of it. If this page and the contract ever
disagree, **the contract wins** — and please tell Ishu.

> **Important:** the backend endpoints below are **designed but not built
> yet**. The contract is agreed; the services are next on Ishu's list. Build
> against the contract with mock data first. See section 8.

---

## 1. What you build, and what you don't

**You build**

- **The Agent Portal website**, phone-first. Agents sign in with their phone
  number and an OTP, apply, and then see their code, the people who joined,
  their earnings, balance and payouts.
- **Flutter changes**: a "Have a referral code?" box on the name and date of
  birth page (`Frontend/lib/features/registration/presentation/pages/onboarding_name_page.dart`,
  "Step 2"), and later a promo code box at payment.

**You do NOT build**

- Any commission, discount or eligibility maths. The backend decides
  everything; the frontend only shows what it gets.
- Admin screens (approving agents, payouts). Those are in Shaaz's admin
  dashboard.
- Agent-added clients ("Way 2"). That comes later.
- A "Partner Program" button on the app's first screen. The entry point is a
  link on the landing page that opens the portal. Whether the app also gets a
  button is **To be confirmed with Raja**.

---

## 2. How to call the API

| Topic | What to do |
|---|---|
| Base URL | `<BACKEND_URL>` (the Render service URL — ask Ishu). Local: `http://127.0.0.1:3000`. Never hard-code it. |
| Agent auth | `Authorization: Bearer <accessToken>` from the agent sign-in. This is **our own token, not Firebase**. |
| Member auth (Flutter only) | The existing Firebase ID token, as the app already sends. |
| Version | Send `Accept-Version: 1` on every request. Missing means `1`; an unsupported value gives `406 UNSUPPORTED_VERSION`. |
| Money | Always **paise** (integer). Show `amountPaise / 100` as rupees, e.g. `50000` → "₹500.00". |
| Dates | Calendar dates are `YYYY-MM-DD` in **Indian time**; timestamps are ISO-8601 UTC. |
| Lists | Cursor pagination: `?cursor=<opaque>&limit=<1-50, default 20>` → `{ items, nextCursor }`. `nextCursor` is `null` on the last page. Pass the cursor back unchanged. |
| CORS | The portal's web address must be added to `CORS_ORIGINS` on Render. Tell Ishu the address once it is decided. |

### Two kinds of session

| | ApplicantSession | AgentSession |
|---|---|---|
| Who gets it | A phone with **no agent record yet** | A phone that **has an agent record** (any status) |
| `scope` | `APPLICANT` | `AGENT` |
| Fields | `accessToken`, `expiresInSeconds`, `scope` | `accessToken`, `refreshToken`, `expiresInSeconds`, `scope`, `agent` (profile) |
| Refresh | **No refresh token.** If it expires before they apply, send them back to OTP. | Rotating refresh token. |
| Allowed | `POST /agent/application`, `GET /agent/me` (gives 404) | Depends on status (section 4) |

`POST /agent/application` returns an **AgentSession**, so after applying you
store the new tokens and carry on — **no second OTP**.

### Refreshing (agent sessions only)

- When a call returns `401` with `code: TOKEN_EXPIRED`, call
  `POST /agent/auth/refresh` with `{ "refreshToken": "..." }` **once**, store
  the new pair (the old refresh token stops working), and retry.
- `REFRESH_TOKEN_INVALID`, `REFRESH_TOKEN_EXPIRED` or `REFRESH_TOKEN_REUSED`:
  clear the tokens and go to sign-in. `REUSED` means the token was used twice;
  the backend has revoked the whole session.
- Never refresh twice in parallel: queue requests while one refresh runs.
- Token lifetimes are settings; always use `expiresInSeconds` from the
  response, never a fixed number.

### Errors

The app's existing error shape, plus one field:

```json
{ "statusCode": 403, "message": "…", "error": "Forbidden", "code": "AGENT_NOT_ACTIVE" }
```

Branch on `code`, never on `message` (`message` may be a list for validation
errors). Codes in the contract: `VALIDATION_FAILED`, `UNAUTHORIZED`,
`TOKEN_EXPIRED`, `UNSUPPORTED_VERSION`, `RATE_LIMITED`, `OTP_INVALID`,
`OTP_EXPIRED`, `REFRESH_TOKEN_INVALID`, `REFRESH_TOKEN_EXPIRED`,
`REFRESH_TOKEN_REUSED`, `AGENT_NOT_ACTIVE`, `AGENT_NOT_FOUND`,
`APPLICATION_EXISTS`, `REFERRAL_NOT_FOUND`, `CODE_NOT_FOUND`,
`ALREADY_ATTRIBUTED`, `SELF_REFERRAL`.

- `403 AGENT_NOT_ACTIVE` includes `agentStatus`: reload `GET /agent/me` and
  show the matching status screen.
- `429 RATE_LIMITED` comes with a `Retry-After` header (seconds).

---

## 3. Sign-in flow (dummy OTP for now)

1. Phone screen → `POST /agent/auth/otp/request` with `{ "phone": "+919876543210" }`
   (E.164, `+91` and 10 digits). Response: `{ expiresInSeconds, resendAfterSeconds }`.
   It answers the same whether or not the phone is an agent.
2. OTP screen → `POST /agent/auth/otp/verify` with `{ "phone", "code" }`
   (`code` is 4–8 digits). Response is an `ApplicantSession` or an
   `AgentSession`; **branch on `scope`**.
   - `APPLICANT` → application form.
   - `AGENT` → read `agent.status` and go to the matching screen.
3. Errors: `401 OTP_INVALID` / `OTP_EXPIRED` → let them retry or resend after
   `resendAfterSeconds`.

**Dummy OTP:** until the Firebase paid plan is bought, OTP is a dummy for
testing (anyone can sign in as any number). Agent sign-in uses Shaaz's
`OtpService`; which code the dummy mode accepts for agents is
**To be confirmed with Shaaz**. Do not build anything that depends on the
dummy behaviour.

---

## 4. Screen by screen (Agent Portal)

What each status may do (from the contract):

| Status | Shown as | Can call |
|---|---|---|
| (applicant) | — | `POST /agent/application`, `GET /agent/me` (404) |
| `PENDING_APPROVAL` | label from config | `GET /agent/me`, `GET /agent/config`, refresh, logout |
| `REJECTED` | label from config, with `rejectionReason` | same as pending, plus re-apply (`POST /agent/application`) — re-apply is a **Pending decision** |
| `ACTIVE` | label from config | everything |
| `SUSPENDED` | **"Paused"** | all reads; links come back `shareable: false`; cannot edit payout details |
| `TERMINATED` | label from config | read-only: `GET /agent/me`, `GET /agent/config`, `GET /agent/commissions`, `GET /agent/balance`, `GET /agent/payouts`, refresh, logout. Approved balance is still paid. |

### 4.1 Sign in
See section 3.

### 4.2 Application form → `POST /agent/application`

| Field | Required | Rule (contract) | Tip |
|---|---|---|---|
| `name` | yes | 2–100 characters | |
| `city` | yes | 1–80 characters | |
| `state` | yes | 1–80 characters | |
| `pan` | no | `^[A-Z]{5}[0-9]{4}[A-Z]$`, e.g. `ABCDE1234F` | Trim and upper-case before sending. |

- The phone is **never** sent in the body; it is the verified sign-in phone.
- Show this note: **PAN is optional now, but PAN and verified payout details
  are required before the first payout.**
- Success `201` → an `AgentSession`. Store `accessToken` and `refreshToken`,
  then show the Pending screen using `agent`.
- `409` means an application already exists. The exact refusal codes for
  "already pending", "already an agent" and "re-apply not allowed" are
  **To be confirmed** (the contract currently lists `APPLICATION_EXISTS`).

### 4.3 Status screens → `GET /agent/me` (+ `GET /agent/config` for labels)

Shows `name`, `phoneMasked` (e.g. `+91 98***210`), `city`, `state`, `status`
with `statusLabel` (`{ en, ta }`), `approvedAt`, `panLast4`,
`payoutDetailsSet`, `primaryCode`.

- **Pending**: "We're reviewing your application." No code yet
  (`primaryCode` is `null`).
- **Approved (`ACTIVE`)**: go to Home.
- **Rejected**: show `rejectionReason`, and a "Apply again" button only if
  re-apply is allowed (Pending decision).
- **Paused (`SUSPENDED`)**: everything readable, sharing disabled, payout
  details read-only.
- **Terminated**: read-only earnings, balance and payouts; no code or sharing.

### 4.4 Home: code and share → `GET /agent/referral-links`, `GET /agent/balance`

Each item: `codeId`, `code`, `isPrimary`, `link`, `qrPayload`,
`shareMessages` (`[{ id, text: { en, ta } }]`), `shareable`.

- Show the **code** with a "Copy code" button — always.
- `link` and `qrPayload` are **`null`** until the web address is decided:
  hide the link and the QR code when they are `null`.
- Disable sharing when `shareable` is `false` (Paused).
- Show a balance summary from `GET /agent/balance`.

### 4.5 People who joined → `GET /agent/referrals`, `GET /agent/referrals/{id}`

Query: `cursor`, `limit`, optional `stage` (`REGISTERED`, `PROFILE_COMPLETE`,
`PURCHASED`). Each item has **exactly** these fields:

`id` (the attribution id, not a user id), `displayName` (e.g. `Priya S.`),
`age`, `city`, `signedUpAt` (IST date), `stage`, `profileCompletenessPct`
(0–100), `planName`, `purchasedAt` (IST date or `null`), `commissionStatus`
(`ON_HOLD`, `APPROVED`, `PAID`, `CANCELLED` or `null`), `maskedPhone`
(e.g. `+91 98***210`).

There is nothing else to show; please don't ask for more fields — it is a
privacy rule.

### 4.6 Earnings and balance → `GET /agent/commissions`, `GET /agent/balance`

Commissions (query `cursor`, `limit`, optional `status`): `id`, `referralId`,
`referralDisplayName`, `planName`, `basePaise`, `amountPaise`,
`rate` (`{ calcType: 'PERCENTAGE', value }` where `value` is basis points,
1000 = 10%), `status`, `earnedOn`, `holdEndsOn`, `approvedOn`, `paidOn`.

Balance: `onHoldPaise`, `availablePaise`, `paidPaise`, `minPayoutPaise`,
`canRequestPayout`. `canRequestPayout` is information only: **agents cannot
create payouts**; an admin pays out manually.

### 4.7 Payouts → `GET /agent/payouts`

Query `cursor`, `limit`. Each item: `id`, `amountPaise`, `status`
(`CREATED` shown as **"Processing"**, `PAID`, `CANCELLED`), `reference`,
`createdOn`, `paidOn`, `commissionCount`. Read-only.

### 4.8 Payout details → `PATCH /agent/me/payout-details` (ACTIVE only)

Send **exactly one** of:

- `{ "upi": { "vpa": "ravi@okbank" } }` — trim and lower-case. The backend
  validator accepts `^[a-z0-9._-]{2,256}@[a-z][a-z0-9]{1,63}$`.
- `{ "bank": { "accountHolderName", "accountNumber", "ifsc" } }`
  - `accountNumber`: digits only, 9–18. **Strip spaces and hyphens before
    sending** — the backend rejects them.
  - `ifsc`: `^[A-Z]{4}0[A-Z0-9]{6}$`, e.g. `HDFC0001234`; trim and upper-case.

Response is masked only: `{ method: 'UPI' | 'BANK', display }`, e.g.
`HDFC ****6789`. The full number or UPI id is never sent back.

### 4.9 Help
No help endpoint exists in the contract. Static content for now —
**To be confirmed** what it says.

### 4.10 Sign out → `POST /agent/auth/logout`
Body `{ "refreshToken" }` (agent sessions). An applicant has nothing to revoke;
just discard the token.

### 4.11 Push notifications
`POST /agent/devices` takes `{ fcmToken, platform }` with `platform` = `ANDROID`
or `IOS` only — it is for a future phone app, **not for the website**.

---

## 5. Flutter changes

### "Have a referral code?" box (name and date of birth page)

1. Let the member type a code. Before sending: **trim, remove spaces and
   hyphens**. Case does not matter (the server upper-cases).
2. `POST /referrals/codes/validate` with `{ "code" }` — **no token needed**.
   Response is only `{ valid, agentDisplayName }`:
   - `valid: true` → show "Referred by Ravi K."
   - `valid: false` → one generic message ("This code isn't valid"). The
     backend never says why, on purpose.
   - `429` → "Too many tries, please wait" (attempts are limited per IP and
     per code).
3. `POST /registration/referral-code` with `{ "code" }` and the member's
   **Firebase token**, once the member is signed in. Success:
   `{ attached: true, agentDisplayName, windowEndsAt }`. Errors:
   `404 CODE_NOT_FOUND`, `409 ALREADY_ATTRIBUTED` (the first agent always
   stays), `422 SELF_REFERRAL`, `429`.

Whether the member is already signed in on that page (so you can attach
straight away) is **To be confirmed** against the registration flow.

### Promo code box at payment
Later, with Shaaz's checkout. **To be confirmed.**

---

## 6. WhatsApp share button

No WhatsApp API is needed.

- **Portal**: the button opens `https://wa.me/?text=<encodeURIComponent(message)>`.
- **Flutter** (if agent sharing is ever added to the app): use the phone's
  share sheet. The app has no share package in `pubspec.yaml` today, so that
  would be a new dependency — check with the team first.
- The message text comes ready-made in `shareMessages` on each referral link
  (with the code already filled in). While there is no web address, the link
  line is left out automatically.
- The Tamil text is pending Raja's review (`'<to be supplied>'` until then).

---

## 7. Labels, statuses and stages — all from `GET /agent/config`

Never hard-code labels. `GET /agent/config` returns (each label as
`{ en, ta }`):

| Field | Keys |
|---|---|
| `statusLabels` | `PENDING_APPROVAL`, `ACTIVE`, `REJECTED`, `SUSPENDED` ("Paused"), `TERMINATED` |
| `stageLabels` | `REGISTERED`, `PROFILE_COMPLETE`, `PURCHASED` |
| `commissionStatusLabels` | `ON_HOLD`, `APPROVED`, `PAID`, `CANCELLED` |
| `payoutStatusLabels` | `CREATED` ("Processing"), `PAID`, `CANCELLED` |
| `shareMessages` | templates `[{ id, text: { en, ta } }]` |
| `settings` | `holdDays`, `creditWindowDays`, `minPayoutPaise`, `referredMemberDiscountPercent` |

Agents only ever see the four public commission statuses; internal review
states arrive as `ON_HOLD`.

---

## 8. Mocked or not ready yet

| Thing | State |
|---|---|
| All agent endpoints | Contract agreed, **not built yet**. Use mock data shaped like the contract examples. |
| Referral `link` and `qrPayload` | `null` until the web address is decided |
| Tamil labels and share text | `'<to be supplied>'` until Raja reviews |
| Payments, commissions, payouts | Waiting on Shaaz's payments work; lists will be empty |
| Real OTP | Dummy OTP until the Firebase paid plan |
| Agent-added clients | Later |
| Portal web address | Not decided (needed for `CORS_ORIGINS`) |

---

## 9. Open decisions that may change your screens

- Can a rejected agent re-apply? (Rejected screen's "Apply again" button.)
- Is the Partner Program button also in the app?
- The referral link web address (shows the link and QR).
- Tamil share-message wording.
- How an agent can pay for a client's plan (a future screen).
- Whether agents will need KYC later (a future screen).
- Plan prices (shown in commission and discount amounts).

---

## 10. How to test against the dev backend

- Point the portal at `<BACKEND_URL>` (ask Ishu) and send `Accept-Version: 1`.
- The dummy OTP is on, so any number works — use fake numbers only, never a
  real person's.
- Until the agent endpoints are deployed, the calls will 404: use mocks
  matching the contract. The contract file has examples for the sign-in and
  application responses.
- Your local portal address must be in `CORS_ORIGINS` for browser calls to
  work; ask Ishu to add it on the dev backend.
- The Flutter app's default API address (`AppConstants.apiBaseUrl` in
  `Frontend/lib/core/constants/app_constants.dart`) is the Render service.
  Override it with `--dart-define=API_BASE_URL=...` (see the repo's
  `CLAUDE.md` §9; that file still says Railway, but the default is now Render).

---

## 11. Checklist

Portal
- [ ] Phone + OTP screens, branching on `scope`
- [ ] Token storage, single-flight refresh, sign-out
- [ ] `Accept-Version: 1` on every call
- [ ] Error handling by `code`, including `AGENT_NOT_ACTIVE` and `429`
- [ ] Application form with the field rules and the PAN note
- [ ] Status screens: Pending, Rejected (with reason), Paused, Terminated
- [ ] Home: code, copy button, hide link/QR when `null`, share disabled when not `shareable`
- [ ] WhatsApp button via `wa.me`
- [ ] People who joined, with stage filter and pagination
- [ ] Earnings, balance, payouts (with "Processing" for `CREATED`)
- [ ] Payout details: UPI or bank, strip spaces/hyphens, masked result
- [ ] All labels from `GET /agent/config`, English and Tamil
- [ ] Money shown from paise; dates shown as IST dates

Flutter
- [ ] "Have a referral code?" box on the name and date of birth page
- [ ] Validate call (no token) with one generic invalid message
- [ ] Attach call (Firebase token) with its error cases
- [ ] Promo code box at payment (later)
