# Frontend: live test procedure, release command and deep-link preparation

Written 2026-11-02 for the team (Dhatri's frontend work). Nothing here is
deployed or enabled. Items needing a person or a decision are marked
**BLOCKED** or **DECISION**. No tokens, OTPs, cookies or personal data belong
in this file or in any report built from it.

## 1. Referral release command (not run)

`REFERRAL_ENDPOINTS_LIVE` is a compile-time flag, default `false`
(`referral_providers.dart`, pinned by `referral_backend_mode_test.dart`).

| Build | Flag off (default) | Flag on |
|---|---|---|
| debug | mock repository (box shown) | live API |
| release / profile | **off**: no box, repository refuses, mock never used | live API |

When the team confirms the live referral test:

```
flutter build apk --release \
  --dart-define=API_BASE_URL=https://nenjam-matrimony.onrender.com \
  --dart-define=REFERRAL_ENDPOINTS_LIVE=true
```

(`appbundle` in place of `apk` for the Play Store.) Notes:

- Android release needs `android/key.properties`; without it the release task
  fails by design.
- Without `--dart-define=DUMMY_OTP=true` a release build uses real Firebase
  phone OTP, which needs SMS billing. **DECISION:** whether the next test
  build carries `DUMMY_OTP=true` (it also needs `DUMMY_OTP_ENABLED` and the
  phone allowlist on the backend). Never for a store build.
- The backend needs `AGENT_PROGRAM_ENABLED=true` or `/referrals/*` and
  `/registration/referral-code` do not exist.

## 2. Deep-link preparation (URL not decided: **DECISION** Raja)

Today nothing can receive a link: no Android intent filter beyond the
launcher, no iOS associated domains (`Info.plist` has only the Google
Sign-In scheme, no `.entitlements` file), no link package. On web, path URLs
are on (`usePathUrlStrategy`), so a URL reaches go_router.

**Needed once the domain and route are chosen**

1. **Where the code is captured.** Before splash redirects: read the code from
   the incoming `Uri` (web: initial URL; mobile: platform link callback or
   go_router's deep-link handling) and hand it to one function. The router
   starts at `/splash` and its redirect forgets the URI, so capturing later
   loses it.
2. **Validate, then store; never store unvalidated.** Run
   `normalizeReferralCode` (rejects anything not `NM` + 6 allowed chars,
   verified against link-shaped junk in `referral_persistence_test.dart`), then
   `ReferralRepository.validateCode` (no token needed), then
   `PendingReferralStore.write`. This is exactly what `ReferralCodeBox._apply`
   does today. `ReferralCodeBox` already shows a stored code on open, so the
   name step needs no change to display it.
3. **Existing behavior is kept.** Attach still happens through
   `ReferralAttachmentController` at its three points; sign-out still clears the
   code.
4. **Android App Links:** `https` intent filter with `android:autoVerify="true"`
   for the host and path, in the `MainActivity` of `com.growspark.nenjam`;
   `/.well-known/assetlinks.json` on the domain with that package name and the
   release signing certificate SHA-256 (and the Play app-signing one if used).
5. **iOS Universal Links:** Associated Domains capability
   (`applinks:<domain>`), a new `Runner.entitlements`, and
   `/.well-known/apple-app-site-association` for bundle `com.growspark.nenjam`
   (team ID needed).
6. **Website fallback:** the same URL must open something when the app is not
   installed: the Flutter web app (hosted from `Frontend/build/web`, rewrites
   in `web/vercel.json`) or a store-redirect page; and the code must survive
   the install (not solved by plain App/Universal Links; needs a decision such
   as asking the member to enter the code, or deferred deep links).
7. **A signed-in member opens another agent's link.** The attach call is made
   at the next cold start, and the first agent always stays:
   `409 ALREADY_ATTRIBUTED` (silent "already linked"), or `422 ALREADY_PAID`
   (now final, "can't be used with your account"; fixed in this change).
   **DECISION:** whether a signed-in member should be shown anything at all
   when they open a link; recommended: only validate-and-store for members
   who are not yet signed in, and ignore links otherwise.

## 3. Live verification procedure

Preconditions (each is **BLOCKED** until supplied):

| Needed | From |
|---|---|
| Dhatri's own approved number for the portal application | team |
| An approved agent account + its private referral code | Raja / admin |
| `AGENT_PROGRAM_ENABLED`, agent token key, `AGENT_PII_ENCRYPTION_KEY` set | backend |
| Membership prices entered and checkout enabled | Shaaz |

Evidence already collected 2026-11-02 (unauthenticated GETs only, no tokens):
`/health` 200; `/agent/config`, `/agent/me`, `/agent/balance`,
`/agent/commissions`, `/agent/payouts` each **401** with
`"A valid agent access token is required."` (the routes exist and the agent
program is on); `/membership/plans` and `/membership/me` **401** (need a member
Firebase token; nothing about prices could be checked).

**Agent Portal** (`https://agent.nenjammatrimony.com`, or a local run with
`VITE_API_BASE_URL=https://nenjam-matrimony.onrender.com`, mocks off):

| # | Step | Expected | Endpoint |
|---|---|---|---|
| 1 | Enter the approved number, request code | challenge shown | `POST /agent/auth/otp/request` |
| 2 | Enter the code received | applicant form (new) or status/home (existing) | `POST /agent/auth/otp/verify` |
| 3 | Network tab: applicant never calls config | no `/agent/config` before apply | none |
| 4 | Submit name, city, state | 201, Pending screen, no second OTP | `POST /agent/application` |
| 5 | Refresh the browser on `/status` | still signed in, same screen | `GET /agent/me` |
| 6 | After approval: Home | code card, balance 3 figures (paise ÷ 100) | `GET /agent/referral-links`, `GET /agent/balance` |
| 7 | Earnings | list, "Load more" while `nextCursor` set, labels from config | `GET /agent/commissions?cursor=` |
| 8 | Payouts | `CREATED` shown "Processing"; no create button | `GET /agent/payouts?cursor=` |

Mapping checks: money is integer paise; commission `rate.value` is basis
points (1000 = 10%); dates are `YYYY-MM-DD`; unknown status falls back to the
raw key; a 404 without a `code` shows "coming soon", any other failure shows
an error with "Try again".

**Flutter app** (build per section 1, member signed in with an approved
account):

| # | Step | Expected | Endpoint |
|---|---|---|---|
| 1 | Open Premium | plans/prices equal the backend values; unpriced lengths absent; buying disabled if `checkoutAvailable` is false | `GET /membership/plans` |
| 2 | Choose a plan, Continue (no code) | body `{planCode, months}` only; breakdown from `pricing`; Pay shows `amountInPaise` | `POST /membership/checkout` |
| 3 | Same with a private agent code | `promoCode` sent; `discountPaise` line and agent name; total changes | `POST /membership/checkout` |
| 4 | A wrong code | message, previous price kept, Pay off until Remove | 422 `PROMO_CODE_REJECTED` |
| 5 | Pay with Razorpay **test** keys only | verify body = SDK values; outcome closes sheet; plan shows on Premium | `POST /membership/checkout/verify`, `GET /membership/me` |
| 6 | Cancel the payment sheet | same order stays payable, nothing granted | none |
| 7 | Name step: enter the code, finish signup | code validated, stored, attached after verify-mobile | `POST /referrals/codes/validate`, `POST /registration/referral-code` |
| 8 | Kill the app between 7's name step and verify | code still applied on reopening | local |

Device-level payment (steps 5 and 6) can only be claimed once done on a real
Android/iOS device with a gateway session; unit tests use a fake gateway.

Record each row as PASSED only with the HTTP status actually received;
otherwise **BLOCKED**.
