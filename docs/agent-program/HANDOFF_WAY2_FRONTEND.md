# Agent-added clients ("Way 2"): frontend handoff

For the frontend developer building the **Agent Portal** (React) and the
**member app** (Flutter). Everything here is on the backend branch
`feat/agent-clients-routes` and is described formally in
`docs/agent-program/agent-api.openapi.yaml` (tags **Clients** and **Client
invites**). If this file and the contract ever disagree, the contract wins;
please tell the backend owner.

---

## 1. The flow in plain words

An agent meets someone who wants to join Nenjam. Instead of sharing a
referral code, the agent fills in the person's phone number and the six
fields of step 1 of registration (name, gender, date of birth, marital
status, who the profile is for). That is a **draft**. The agent can still
change it or throw it away.

When the agent is happy, they **submit** it. From that moment the draft is
locked: the agent can no longer change anything. The person (we call her
the **client**) now has an **invitation** waiting.

The client opens the member app, taps "Added by an agent? Confirm here",
types her phone number, receives a one-time code, and types it. She sees
who invited her and the details the agent entered. She either:

- **Accepts**: her member account is created right then, with step 1 of
  her registration already filled in from what the agent typed. She is
  signed in and continues the registration wizard from step 2 like any
  other member. The agent gets credit for her exactly as if she had used
  the agent's referral code (same discount on her first plan, same
  commission rules).
- **Rejects**: nothing is created. That agent can never add her number
  again.

If she does nothing, the invitation **expires** after a number of days (a
setting, 14 today). A phone that already has a member account can never be
added.

### Worked example

1. Ravi Kumar (an ACTIVE agent) adds Priya Sundaram, `+91 98xxxxxxx`. The
   portal shows a new row "Priya S. · +91 98***210 · Draft".
2. Ravi corrects her last name, then taps **Submit**. The row becomes
   "Waiting for client", with "open until 11 Nov 2026".
3. Priya opens the member app, taps "Added by an agent?", enters her number,
   then the code. She sees one card: "Ravi K. added you", her details, "5%
   off your first plan", "Answer by 11 Nov 2026".
4. Priya taps **Accept**. The app receives a Firebase custom token, signs
   her in with it, loads her registration draft and opens step 2.
5. Ravi's portal row now reads "Accepted · 28 Oct 2026". It links to her
   entry in **My referrals** (the `referralId`).

---

## 2. Things every request needs

- Base URL: the same API as the rest of the agent portal / member app.
- Send `Accept-Version: 1` on every request (missing is treated as 1).
- Bodies are JSON. Unknown fields are refused (`400 VALIDATION_FAILED`).
- **Errors** always look like this. Branch on `code`, never on `message`:

  ```json
  { "statusCode": 409, "error": "Conflict", "code": "CLIENT_DRAFT_EXISTS",
    "message": "You have already added this client." }
  ```

  For `VALIDATION_FAILED`, `message` is a list naming the bad fields, for
  example `["details.dob is not valid"]`. It never contains what was typed.
- **Dates** you show (`expiresOn`, `submittedOn`, `acceptedOn`,
  `windowEndsAt`) are Indian calendar dates `YYYY-MM-DD`. Show them as they
  are; do not convert time zones. `createdAt` is an ISO timestamp (UTC).
- Every Way 2 route may also answer:

  | HTTP | `code` | What the UI should say / do |
  |---|---|---|
  | 403 | `CLIENT_INVITES_DISABLED` | The feature is switched off on the server. Hide the feature (see section 4); if a screen is already open: "This isn't available right now." |
  | 503 | `AGENT_PROGRAM_UNAVAILABLE` | "Not available right now. Please try again later." |
  | 409 | `CONCURRENT_CHANGE` | Something changed at the same moment: retry once, then reload. |
  | 429 | `RATE_LIMITED` | "Too many attempts. Try again in N seconds." N is the `Retry-After` header (seconds). |

---

## 3. Statuses and labels

A draft is in exactly one of these. The **labels** come from
`GET /agent/config` → `clientStatusLabels` (English and Tamil). Always use
those; do not hard-code the words. Tamil is still `<to be supplied>` today.

| `status` | English label today | Meaning | Agent can |
|---|---|---|---|
| `DRAFT` | Draft | Not sent yet | edit, discard, submit |
| `WAITING_FOR_CLIENT` | Waiting for client | Submitted, locked | only look |
| `ACCEPTED` | Accepted | She joined; she is the agent's referral | open the referral |
| `REJECTED` | Declined | She said no; this agent can never add her number again | only look |
| `EXPIRED` | Expired | Ran out of time, or closed (for example she joined another way) | only look; may add her again |

`editable` in the response is `true` only for `DRAFT`. `details` is `null`
once the draft is closed (accepted, declined or expired): the agent's copy
of her details is deleted then. A draft whose time has run out is shown as
`EXPIRED` immediately, even before the nightly job runs.

---

## 4. How `/agent/config` drives the feature (Agent Portal)

`GET /agent/config` (agent token) now also returns:

```json
{
  "clientStatusLabels": {
    "DRAFT": { "en": "Draft", "ta": "<to be supplied>" },
    "WAITING_FOR_CLIENT": { "en": "Waiting for client", "ta": "<to be supplied>" },
    "ACCEPTED": { "en": "Accepted", "ta": "<to be supplied>" },
    "REJECTED": { "en": "Declined", "ta": "<to be supplied>" },
    "EXPIRED": { "en": "Expired", "ta": "<to be supplied>" }
  },
  "clients": { "enabled": true, "draftLimit": 10, "expiryDays": 14 }
}
```

(alongside everything it returned before).

- **`clients.enabled` is `false` → hide everything about clients**: the
  menu entry, the "Add a client" button, the list. Today it is `false` in
  every environment until the business switches it on.
- Treat a missing `clients` object (an older server) as `enabled: false`.
- `draftLimit` is the most open clients (`DRAFT` plus `WAITING_FOR_CLIENT`)
  at once: show "7 of 10" by counting those in the list. `expiryDays` is
  for help text ("Your client has 14 days to answer"). Either may be
  `null`; then `enabled` is `false` too.
- This call never fails because of the client feature.

**Which agents see it:** an `ACTIVE` agent can do everything. A
`SUSPENDED` ("Paused") agent can see the list and the details but every
change answers `403 AGENT_NOT_ACTIVE` (`agentStatus: "SUSPENDED"`): show
the list read-only with the usual paused banner. `PENDING_APPROVAL`,
`REJECTED` and `TERMINATED` agents get `403 AGENT_NOT_ACTIVE` on every
client route: hide the feature for them (their status is in `GET /agent/me`).

---

## 5. Agent Portal routes (React)

All with the agent access token: `Authorization: Bearer <agent access token>`.
On `401 TOKEN_EXPIRED`, refresh once and retry, as everywhere else.

### `POST /agent/clients`: add a client (creates a DRAFT)

Request:

```json
{
  "phone": "+919876543210",
  "details": {
    "firstName": "Priya",
    "lastName": "Sundaram",
    "gender": "FEMALE",
    "dob": "1998-04-12",
    "maritalStatus": "NEVER_MARRIED",
    "profileCreatedFor": "Daughter"
  }
}
```

Field rules (check them in the form too; the server checks them again):

- `phone`: E.164, for example `+919876543210`.
- `firstName`, `lastName`: 1 to 50 characters after trimming.
- `gender`: `MALE` or `FEMALE`.
- `dob`: `YYYY-MM-DD`, a real date, at least 21 years ago.
- `maritalStatus`: `NEVER_MARRIED`, `DIVORCED`, `WIDOWED` or `AWAITING_DIVORCE`.
- `profileCreatedFor`: `Myself`, `Son`, `Daughter`, `Brother`, `Sister`,
  `Friend` or `Relative`. These are the member app's values.

Response `201`:

```json
{
  "id": "5b0f6a52-4f0e-4c6e-9d6b-2f1a3c7e8d90",
  "status": "DRAFT",
  "statusLabel": { "en": "Draft", "ta": "<to be supplied>" },
  "displayName": "Priya S.",
  "phoneMasked": "+91 98***210",
  "details": { "firstName": "Priya", "lastName": "Sundaram", "gender": "FEMALE",
               "dob": "1998-04-12", "maritalStatus": "NEVER_MARRIED",
               "profileCreatedFor": "Daughter" },
  "editable": true,
  "createdAt": "2026-10-28T10:00:00.000Z",
  "submittedOn": null,
  "expiresOn": "2026-11-11",
  "acceptedOn": null,
  "referralId": null
}
```

Errors:

| HTTP | `code` | What the UI should say |
|---|---|---|
| 400 | `VALIDATION_FAILED` | Highlight the named fields. |
| 403 | `AGENT_NOT_ACTIVE` | "Your account is paused; you can't add clients right now." |
| 409 | `CLIENT_DRAFT_EXISTS` | "You have already added this number." Offer to open the list. |
| 422 | `CLIENT_DRAFT_LIMIT_REACHED` | "You can have at most {draftLimit} open clients. Submit, discard or wait for one to close." |
| 422 | `CLIENT_PHONE_UNAVAILABLE` | "This number can't be added." Give no reason: the server deliberately doesn't say why. |
| 503 | `OTP_DELIVERY_UNAVAILABLE` | "Only test numbers can be added for now." (No SMS yet, see section 9.) |

### `GET /agent/clients?status=&cursor=&limit=`: the list, newest first

- `status`: optional, one of the five statuses.
- `limit`: 1 to 50 (default 20).
- `cursor`: the previous page's `nextCursor`.

Response `200`:

```json
{ "items": [ { "...": "ClientDraft as above" } ], "nextCursor": "eyJ0Ijoi..." }
```

`nextCursor` is `null` on the last page. Errors: `400` (bad query), `403`.

### `GET /agent/clients/{id}`: one draft

Response `200`: a `ClientDraft`. Errors: `404 CLIENT_DRAFT_NOT_FOUND`
("This client no longer exists." Another agent's draft also looks like
this), `403`.

### `PATCH /agent/clients/{id}`: edit a DRAFT

Request `{ "details": { ...all six fields... } }`. This replaces all six
fields. The phone cannot be changed: to change it, discard the draft and
add the client again.

Response `200`: the updated `ClientDraft`.

Errors:

- `400 VALIDATION_FAILED`.
- `404 CLIENT_DRAFT_NOT_FOUND`.
- `409 CLIENT_DRAFT_LOCKED`: "This client was already submitted (or has
  closed) and can't be changed." Reload the draft.
- `403`.

### `DELETE /agent/clients/{id}`: discard a DRAFT

Response `204`, no body. Errors: `404`, `409 CLIENT_DRAFT_LOCKED` (only a
DRAFT can be discarded; a submitted invitation cannot be withdrawn), `403`.

### `POST /agent/clients/{id}/submit`: send it to the client

No body. Response `200`: the `ClientDraft`, now `WAITING_FOR_CLIENT`, with
`submittedOn` set and a new `expiresOn` (counted from now). Ask "Once
submitted you can't change it. Submit?" before calling.

Errors:

- `404`.
- `409 CLIENT_DRAFT_LOCKED`.
- `422 CLIENT_PHONE_UNAVAILABLE`: the number joined in the meantime. Say
  "This number can no longer be added." The draft stays a DRAFT; offer to
  discard it.
- `503 OTP_DELIVERY_UNAVAILABLE`.
- `403`.

The server also sends the client a one-time code at submit (with the test
code nothing is really sent). The client can always ask for a fresh code in
the app, so do not promise "she got an SMS".

---

## 6. Member app routes (Flutter)

The client is **not** a member yet and has **no Firebase session** while she
looks at invitations. She uses a separate, short-lived **client token**.

### The exact sign-in sequence

1. **Phone screen.** `POST /client-invites/otp/request` with
   `{ "phone": "+919876543210" }` → `200`
   `{ "expiresInSeconds": 300, "resendAfterSeconds": 30 }`. The answer is
   the same whether or not anyone invited this number.
2. **Code screen.** `POST /client-invites/otp/verify` with
   `{ "phone": "+919876543210", "code": "123456" }` → `200`
   `{ "accessToken": "eyJ...", "expiresInSeconds": 900, "scope": "CLIENT" }`.
   Enable "Resend" after `resendAfterSeconds` (call step 1 again; the
   newest code is the one that counts).
3. **Invitations.** `GET /client-invites` with
   `Authorization: Bearer <client token>` → `200`:

   ```json
   { "items": [ {
       "id": "5b0f6a52-4f0e-4c6e-9d6b-2f1a3c7e8d90",
       "agentDisplayName": "Ravi K.",
       "details": { "firstName": "Priya", "lastName": "Sundaram", "gender": "FEMALE",
                    "dob": "1998-04-12", "maritalStatus": "NEVER_MARRIED",
                    "profileCreatedFor": "Daughter" },
       "expiresOn": "2026-11-11",
       "referredMemberDiscountPercent": 5
   } ] }
   ```

   An empty `items` means nobody has invited this number (or the
   invitations ran out). Show "There's no invitation for this number." and
   offer the normal sign-up. Usually there is one; there can be more (two
   agents added her). Show each as a card.
4. **Accept.** `POST /client-invites/{id}/accept` (client token, no body) →
   `200`:

   ```json
   { "firebaseCustomToken": "eyJ...", "agentDisplayName": "Ravi K.",
     "windowEndsAt": "2026-12-27" }
   ```

5. **Sign in.** `FirebaseAuth.instance.signInWithCustomToken(firebaseCustomToken)`.
   From here on she is an ordinary member, and every request uses her
   Firebase ID token exactly like any other member. Forget the client token.
6. **Resume registration.** `GET /profiles/draft` (member token). It returns
   her draft with `data.basicDetails` filled in from the agent's details,
   `completedSteps: [1]` and `currentStep: 1`: exactly what the app would
   have after she saved step 1 herself. Open the wizard where the app
   normally goes after step 1 is saved (step 2).

**Reject** instead: ask first ("Decline {agentDisplayName}'s invitation?
They won't be able to add your number again."), then
`POST /client-invites/{id}/reject` → `204`. Rejecting twice also answers
`204`. Remove the card. No account is created, so she stays signed out.

### What to verify about resuming a draft for an already-signed-in account

The usual member path collects step 1 while signed out and signs in at the
end. Here she arrives **already signed in with step 1 already saved**.
Please check, and tell the backend owner about anything that doesn't hold:

- Nothing in the app overwrites `basicDetails` with an empty or locally
  cached step 1 (an older half-filled local draft on the same phone, for
  example). The server's draft is the truth.
- The app goes straight into the wizard. It does not show the
  registration landing page, the language picker or the signed-out step 1
  again.
- She can still open step 1 and correct what the agent typed. Saving it
  uses the normal `PATCH /profiles/draft/basic-details`.
- Her account email is a placeholder (`<uid>@firebase.invalid`), as for
  every phone-only signup today. If the wizard asks for an email later,
  that is the normal path.
- On app restart before she finishes, the normal "resume my draft"
  behaviour applies (she is a signed-in member with a draft).
- The referral is already attached. Do not ask her for a referral code;
  `POST /registration/referral-code` would answer `409 ALREADY_ATTRIBUTED`.

### Errors on the client routes

| Route | HTTP | `code` | What the UI should say / do |
|---|---|---|---|
| request | 400 | `VALIDATION_FAILED` | "Enter a valid mobile number." |
| request | 503 | `OTP_DELIVERY_UNAVAILABLE` | "We can't send a code to this number yet." (Only test numbers today.) |
| request | 429 | `RATE_LIMITED` | "Too many codes requested. Try again in N seconds" (`Retry-After`). |
| verify | 400 | `VALIDATION_FAILED` | "Enter the code we sent." |
| verify | 401 | `OTP_INVALID` | "That code isn't right." (Also a used code, or no code requested.) |
| verify | 401 | `OTP_EXPIRED` | "That code has expired. Request a new one." |
| verify | 429 | `RATE_LIMITED` | Too many wrong codes: "Request a new code." |
| list / accept / reject | 401 | `UNAUTHORIZED` / `TOKEN_EXPIRED` | The client token is missing or expired (it lives 15 minutes): go back to the phone screen and verify again. |
| accept / reject | 404 | `INVITE_NOT_FOUND` | "This invitation isn't available." Reload the list. |
| accept / reject | 409 | `INVITE_UNAVAILABLE` | "This invitation has expired or was closed." Reload the list. (Also: the agent is paused right now.) |
| accept | 409 | `ALREADY_MEMBER` | "This number already has a Nenjam account. Please sign in." Go to the normal sign-in. |
| any | 403 | `CLIENT_INVITES_DISABLED` | Hide the "Added by an agent?" entry; on an open screen: "This isn't available right now." |

**Accept is safe to retry.** If the network drops after she taps Accept,
just call accept again with the same client token. If it had already gone
through, the server answers `200` again with a fresh custom token and
creates nothing new.

### The client token lives in memory only

Never write it to disk (no SharedPreferences, no secure storage, no local
DB) and never log it. Keep it in the screen's / provider's state; when the
app is closed or she goes back past the phone screen, it is gone, and she
verifies again. It is useless anywhere else: every agent and member route
refuses it.

---

## 7. Where to put the entry point (member app)

"Added by an agent? Confirm here" belongs where a new person starts:
beside the normal sign-up / sign-in choice. The exact place is a product
decision for the frontend owner. Hide it when any client route answers
`403 CLIENT_INVITES_DISABLED`. There is no config call for members, so
the first `otp/request` tells you.

---

## 8. How to test

- Ask the backend owner **privately** for an approved test number and the
  test code. Do not put them in code, tests, screenshots, tickets or chat
  channels. Only approved test numbers can be added or receive a code (any
  other number answers `503 OTP_DELIVERY_UNAVAILABLE`), in every
  environment, until real SMS exists.
- The feature switch (`agent.clients_enabled`) is off by default: ask the
  backend owner to switch it on in the environment you test against, and
  to set it back afterwards.
- Accepting creates a real member account for the test number. To run the
  flow again you need a fresh test number, or the backend owner has to
  remove that account.
- The agent side needs an ACTIVE test agent (the usual agent sign-in).

---

## 9. What changes when real SMS arrives

Today the code is the dummy (test) code checked by our own server. When SMS
is switched on, the plan is Firebase phone sign-in in the app. Build the
code screen so either works:

- Keep "send a code" and "check the code" as separate steps behind one
  interface ("I need proof of this phone" → "here is the proof"). Today
  the proof is `{ phone, code }` sent to `POST /client-invites/otp/verify`.
- Later: the app runs Firebase `verifyPhoneNumber` / `signInWithCredential`,
  then sends `{ "firebaseIdToken": "..." }` to the same
  `POST /client-invites/otp/verify` (planned; **not built**) and gets the
  same client token back. `otp/request` will not be used then.
- With real SMS she may already have a Firebase session before she
  accepts, so `firebaseCustomToken` in the accept answer may become
  `null`. When it is `null`, do not call `signInWithCustomToken`; keep the
  current session and go straight to `GET /profiles/draft`.
- The invitation, accept and reject screens do not change.

---

## 10. What is NOT built

- **Real SMS** for clients (only approved test numbers, with the test code).
- **Verifying by Firebase ID token** at `otp/verify` (section 9).
- **Photo verification** of the client.
- **Report-a-partner**: a client cannot report an agent from these screens.
- **Admin screens** for client drafts (nothing in the admin panel yet).
- **A cap on refused numbers per agent per day** (`agent.client_phone_refusals_per_day`):
  not built, waiting for a decision.
- No notice (SMS, push, email) tells the client that she was added; the agent
  tells her.
- The agent cannot withdraw a submitted invitation, and cannot change the
  phone of a draft (discard and add again).

---

## 11. Checklist of screens and states

**Agent Portal**

- [ ] Hide the whole feature when `clients.enabled` is false, `clients` is missing, or the agent is not ACTIVE/SUSPENDED.
- [ ] Clients list: tabs or a filter for the five statuses (labels from `clientStatusLabels`), name, masked phone, "open until {expiresOn}", "N of {draftLimit}" open, paging with `nextCursor`, empty state.
- [ ] Add client form: phone plus the six fields, client-side checks, every error in section 5.
- [ ] Draft detail (DRAFT): edit, discard (confirm), submit (confirm, "can't change after").
- [ ] Waiting detail: read-only, "waiting until {expiresOn}".
- [ ] Accepted detail: accepted date, link to the referral (`referralId`).
- [ ] Declined / Expired detail: read-only, no details shown (they are deleted).
- [ ] Paused agent: list read-only, every change disabled, paused banner.
- [ ] `503 OTP_DELIVERY_UNAVAILABLE`: "Only test numbers for now."

**Member app**

- [ ] "Added by an agent? Confirm here" entry (hidden on `403 CLIENT_INVITES_DISABLED`).
- [ ] Phone screen: E.164 input, send code, every error in section 6.
- [ ] Code screen: code input, resend after `resendAfterSeconds`, wrong / expired / too many.
- [ ] Invitations: loading, empty ("no invitation for this number"), one or more cards (agent name, details, discount, answer-by date).
- [ ] Accept: confirm, call, `signInWithCustomToken`, `GET /profiles/draft`, continue at step 2; retry-safe on network loss.
- [ ] Reject: confirm dialog, `204`, card removed, stays signed out.
- [ ] `ALREADY_MEMBER`: send her to normal sign-in.
- [ ] Client token expired: back to the phone screen.
- [ ] Client token in memory only, never stored or logged.
- [ ] Resume checks from section 6 done on a real device.
