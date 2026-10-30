# Razorpay test mode — setup runbook

How to switch membership payments on with **Razorpay test keys**: no real money moves,
the code path is exactly the one live payments will use, and switching to live later is
only a key swap plus a short cleanup.

Live keys need the company registered and Razorpay's activation (KYC) done. **Until then,
only `rzp_test_` keys go on Render.**

---

## 0. Before you start: what test mode on production means

The app and admin panel talk to the **production** API, so test keys there mean:

- **Anyone with the app can "buy" Gold or Platinum with a test card.** No money moves.
- **This is harmless while `MEMBERSHIP_ENFORCEMENT_MODE=shadow`.** In shadow mode no
  member is limited, so a test purchase unlocks nothing extra. Keep it on `shadow`.
- **Every payment made before the live switch is a test payment.** Production has none
  today. They are closed when going live (§6).
- **Buying is in the Android/iOS app only**; the web shows plans and "buy in the app".

## 1. Razorpay dashboard (Test Mode toggle ON, top of the dashboard)

1. **API keys:** Account & Settings → API Keys → **Generate Test Key**.
   - Copy the **Key Id** (`rzp_test_…`) and the **Key Secret**. The secret is shown
     once; keep it in your password manager.
2. **Payment capture:** Account & Settings → Payment Capture → **Automatic**, capture
   immediately.
   - Without this, payments stay *authorized*. The app never activates an
     authorized-only payment, and Razorpay auto-refunds it later.
3. **Webhook:** Account & Settings → Webhooks → **Add New Webhook**.
   - **URL:** `https://nenjam-matrimony.onrender.com/payments/razorpay/webhook`
   - **Secret:** a new random value, for example the output of
     `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`.
     This same value goes on Render as `RAZORPAY_WEBHOOK_SECRET`. It is **not** the
     Key Secret.
   - **Events:** `payment.captured`, `order.paid`, `payment.failed`, `refund.processed`
   - Save, and make sure the webhook is **Active**.

## 2. Render (Nenjam API → Environment)

| Variable | Value |
|---|---|
| `RAZORPAY_KEY_ID` | the `rzp_test_…` Key Id |
| `RAZORPAY_KEY_SECRET` | the test Key Secret |
| `RAZORPAY_WEBHOOK_SECRET` | the webhook secret from §1.3 |
| `MEMBERSHIP_ENFORCEMENT_MODE` | leave as `shadow` (or unset; the default is `shadow`) |

**Save, rebuild and deploy.** "Save only" does not restart the API, and the new values
are read at startup.

**Check (from any terminal):**

```bash
# Before the keys: 503. After: 401, because the request is unsigned.
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  https://nenjam-matrimony.onrender.com/payments/razorpay/webhook
```

## 3. Put prices on sale (admin panel)

Production has **no prices yet**: every paid length is unpriced and off sale, so checkout
answers *"not available"*. Prices are plan data, never code, so they can change any time
without a deploy:

1. https://admin.nenjammatrimony.com → **Plans** → Gold → **start a draft**.
2. Enter each length's **price in rupees**, **excluding GST**, and tick **On sale**.
3. **Submit for approval**.
4. A **second** admin opens the draft and **publishes** it. The person who submits can
   never publish their own draft, so provision Raja (or another admin) first.
5. Repeat for Platinum.

Use the intended prices if they are decided. Otherwise any price of at least ₹1 works
for testing, and you change it later with another draft.

GST is added on top of these prices by the platform setting `payment.gst_rate_bps`. The
setting arrives with the Payments PR and is **0 until the business is GST-registered**,
so members pay exactly the plan price.

## 4. Test purchases (Android app)

> **Blocked until the app has Razorpay.** As of 29 Oct the Flutter app ships no payment
> SDK: `UnsupportedPaymentGateway` hides every Buy button. A `RazorpayPaymentGateway` (the
> `razorpay_flutter` package) must open Razorpay with the checkout response's
> `key: keyId`, `order_id: orderId`, `amount: amountInPaise`, `currency`. Until then the
> server side is ready but nothing can start a purchase.

Razorpay's test credentials (the dashboard's *Test Card Details* page has the current
list):

| Method | Use | Result |
|---|---|---|
| Card | `4111 1111 1111 1111`, any future expiry, any CVV, any name | success (enter any OTP/password on the test bank page) |
| UPI | `success@razorpay` | success |
| UPI | `failure@razorpay` | failure |

Then work through the sandbox checklist in
[production-readiness.md §2](production-readiness.md). In short:

1. **Buy:** buy Gold → the app's verify step returns `ACTIVATED`, and
   `/membership/me` shows Gold. The admin panel → **Subscriptions** lists it.
2. **Webhook:** the webhook for the same payment adds one `payment_webhook_events` row
   and still only one activation. **Resend** it from the dashboard → `DUPLICATE`.
3. **Declined payment:** a declined card or `failure@razorpay` → payment failed, the
   member stays Free; a retry on the same order succeeds.
4. **Refunds:** from the dashboard (Transactions → Payments → Refund):
   - a **full** refund ends the plan (Cancelled);
   - a **partial** refund keeps it.

**If something looks wrong:**

| What you see | Cause |
|---|---|
| Checkout answers **503** | Keys not set, or Render not redeployed after saving |
| **400** "not available" | No published price for that length (§3) |
| Verify stays **`AWAITING_CAPTURE`** | Automatic capture is off (§1.2) |
| Webhook deliveries fail with **401** | The webhook secret on Render differs from the dashboard's |
| The first webhook times out | Render was asleep. Razorpay retries, and the app's verify step activates the plan anyway |

## 5. What is stored

Each purchase records a PENDING subscription and payment at checkout, and activates only
when **Razorpay itself** reports the payment *captured*, for that order and at that
amount. The amount comes from Razorpay's own record, never from the app. Card numbers and
UPI ids are never stored.

## 6. Going live later (company registered + Razorpay activated)

1. **Close the test purchases.** Every payment and subscription created before the switch
   is a test one. List them in the admin panel (Subscriptions), then revoke each still
   active with the reason *"Razorpay test-mode purchase"*. Back up the database first,
   as for any production change.
2. **Live keys:** in the dashboard with Test Mode **OFF**, generate the **live** keys
   (`rzp_live_…`) and add a **separate live webhook** (same URL and events, new secret).
   Set automatic capture in live mode too.
3. **Render:** replace `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and
   `RAZORPAY_WEBHOOK_SECRET` with the live values, then save, rebuild and deploy.
4. **GST:** once registered, a Super Admin sets `payment.gst_rate_bps`, for example
   `1800` for 18%, through the admin settings (`PUT /admin/settings/payment.gst_rate_bps`,
   with a fresh authenticator code). It applies to new payments only.
5. **One small real purchase,** refunded from the dashboard, before announcing.

Switching `MEMBERSHIP_ENFORCEMENT_MODE` to `enforce` is a separate decision with its own
preconditions (production-readiness.md).
