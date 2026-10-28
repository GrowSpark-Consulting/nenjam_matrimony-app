# Flutter membership integration — plan (not yet implemented)

Scope and risks for connecting the app to the membership API
([api-contract.md](api-contract.md)). Nothing here is built yet. It follows the app's
real conventions (CLAUDE.md §3): hand-written Riverpod providers, hand-written
`fromJson`, repositories behind a `Provider`, `ApiClient` + `unwrapOrThrow`, go_router,
`AppL10n` strings in `en`/`ta`, and no codegen.

## What the app does today (verified)

| Area | State |
|---|---|
| Premium tab (`features/premium/.../premium_page.dart`, route `/premium`, a bottom-nav tab) | **Hardcoded fake plans**: "Gold Luxury ₹4,999 / 3 months", "Platinum VIP ₹9,999 / 6 months", with benefits the PDF doesn't offer ("Dedicated Relationship Manager", "Unlimited direct messages"). **Misleading to members today**, independent of this work |
| `/subscription` page | Honest "not available" screen; never grants anything |
| Payment SDK | None (`pubspec.yaml` has no Razorpay package) |
| Photo cap | Hardcoded `kMaxPhotos = 6` (`profile_photos/.../photo_manager_section.dart`) and `maxPhotos = 6` (`profile/.../photo_gallery_card.dart`) |
| Error bodies | `unwrapOrThrow` already keeps `message` and `code` → membership 403 sentences reach `ApiException.message`. `feature`/`limit`/`upgradeTo` are dropped. Screens that use `NetworkErrorMapper.statusMessage(403)` show only "You do not have permission for this action." |
| Web build | Shipped to Vercel; any payment SDK must work on web too, or purchase must be hidden there |

## Work, in order (each a separate PR off `main`)

1. **Stop the misleading premium page now (small, independent).** Replace the
   hardcoded cards with the existing honest "not available yet" state until
   step 4 ships. No backend dependency.
2. **Data layer** — `features/membership/{domain,data,presentation}`:
   - Models with hand-written `fromJson` for `/plans`, `/me`, `/history`,
     `/checkout`, `/checkout/verify` (exact shapes in api-contract.md). Unknown
     feature ids and `source` values must be tolerated, not thrown on.
   - `ApiMembershipRepository` + `MockMembershipRepository` behind one `Provider`
     (the app's existing mock→real pattern).
   - `membershipPlansProvider` (`FutureProvider.autoDispose`) and
     `myMembershipProvider`. Reset `myMembershipProvider` in the central
     sign-in/sign-out `ref.listen` in `main.dart` (where per-user state is
     already torn down), and on app resume.
   - Extend `ApiException` additively with the parsed body (`details`) so
     `feature`, `limit`, `resetsAt`, `upgradeTo` survive.
3. **Plans + status UI** — premium page renders `/plans` (plans, `features`
   labels, `entitlements`, on-sale `durations` with ₹ from paise); a membership
   card (plan, `endDate`, queued plans from `scheduled`); history page from
   `/history`. Reuse `NmSubscriptionCard`, `premium_badge.dart`, and the existing
   gradient and spacing tokens.
4. **Purchase.** Gate on `checkoutAvailable` and non-empty `purchaseOptions`.
   - Show each option's `kind` and `startsAt`, so a renewal or downgrade states
     when it begins.
   - Flow: `POST /checkout` → Razorpay Checkout (`keyId`, `orderId`) → on success
     `POST /checkout/verify` → handle every `outcome` (table in the contract).
   - On `AWAITING_CAPTURE` or `PENDING_CONFIRMATION`, poll `/me` with backoff for
     about 60 seconds.
   - On SDK failure or cancel: no verify call; show a friendly message.
   - Never set any local "premium" flag; always re-read `/me`.
   - Platform: `razorpay_flutter` covers Android/iOS only. Web needs Razorpay
     `checkout.js` through JS interop, or purchases hidden on web
     (**decision needed**).
5. **Limits UX** (needed only before `enforce`):
   - A single `MembershipDenial` mapper: a 403 with a `MEMBERSHIP_` code shows a
     sheet with `message` and an upgrade button **only when `upgradeTo` is set
     and `checkoutAvailable` is true**.
   - Never offer an upgrade for `MEMBERSHIP_FAIR_USE_LIMIT`, `LEGACY` or
     `UNAVAILABLE`. A 403 without a `code` is the account-blocked case, so keep
     the current behaviour for it.
   - Wire the sheet into: interest send, photo upload, shortlist add, and chat
     send. The chat send is the case where a Free member is starting a
     conversation; replies always work.
   - Photo cap: replace both hardcoded 6s with `effectiveCaps['profile.photos']`
     (6 today; 5/15/20 under enforce).
   - Remaining interests: from `usage`, shown only when `limitsEnforced` is true.
   - Pre-checks such as "Free can't start a chat" are hints only; the 403 is the
     authority. Verified-only browsing stays available to everyone (it's a
     client-side filter, and the backend requires it on every plan).
6. **Cancel / auto-renew** — not shown. Purchases are one-time; the cancel
   endpoint changes nothing visible until recurring billing exists.

## Tests (match CI: `flutter analyze --no-fatal-infos`, `flutter test`)

- `fromJson` for every response, including `LEGACY`/`UNAVAILABLE`, empty
  `durations`, and `null` limits.
- 403 mapping: membership vs account-blocked, upgrade button shown or hidden.
- Verify-outcome handling, including polling until `/me` changes.
- Premium page states: loading, no plans on sale, purchasable, current plan,
  queued plan. Run through the existing responsive matrix (320–480dp, en/ta,
  keyboard).
- Photo manager driven by `effectiveCaps` (6, then 15 or 20).

## Risks

| Risk | Mitigation |
|---|---|
| Enforcement turned on before the app ships step 5 | Enforcement stays `shadow` until the app version with step 5 is the minimum supported (see production-readiness.md) |
| Older app versions after enforcement | They already show the 403 `message` sentence via `unwrapOrThrow`; screens on the generic mapper don't — audit those before enforcing |
| Web payments | Decide: interop vs hide purchase on web |
| Scope | Steps 2–5 are a multi-PR feature (≈ new feature module, 4 screens touched, SDK integration); step 1 is hours |
