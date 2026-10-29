/**
 * The payment events the agent program consumes: a commission on a member's
 * first paid plan, and its reversal when that payment is refunded. Emitted by
 * the payments code (checkout, webhook, offline payments); consumed by the
 * agent-program handlers. This file is the contract between the two.
 *
 * Rules
 *  - Emitted only AFTER the payment's transaction has committed, never inside
 *    it, so a handler never sees a payment that was rolled back.
 *  - At-least-once: the same event may arrive again. Handlers are idempotent,
 *    keyed on `paymentId` (PaymentSucceeded) and `refundId` (PaymentRefunded).
 *  - Amounts are integer paise, the values STORED on the payment when it was
 *    made. Consumers use them as they are and never recompute them — tax
 *    especially, since the rate can change later.
 *  - Times are ISO-8601 UTC strings, so an event survives a JSON transport.
 *  - Within a `version` changes are additive only; anything else is a new
 *    version.
 *
 * Every payment emits PaymentSucceeded, paid in the app or recorded by an
 * admin (cash, UPI) — `paidBy` says which. Only a first paid plan
 * (`isFirstPaidPlan`) can earn a commission; the rest are for completeness.
 *
 * GST is ADDED to the price (prices exclude GST; Raja, 29 Oct):
 *
 *   taxableAmountPaise = listAmountPaise − discountPaise
 *   taxPaise           = round(taxableAmountPaise × taxRateBps / 10000)
 *   amountPaidPaise    = taxableAmountPaise + taxPaise   (what the member pays)
 *
 * e.g. ₹1,000 with 5% off at 18%: taxable 95000, GST 17100, paid 112100.
 * The rate is a platform setting with no default in code; it is 0 until the
 * business is GST-registered, so today taxPaise = 0 and the member pays the
 * taxable amount.
 */

export const REFERRAL_EVENT_VERSION = 1;

export type PaymentPaidBy = 'MEMBER' | 'AGENT' | 'ADMIN_RECORDED';
export type PaymentDiscountSource = 'NONE' | 'REFERRAL_FIRST_PLAN';

export interface PaymentSucceeded {
  type: 'payment.succeeded';
  version: typeof REFERRAL_EVENT_VERSION;
  /** `payment_transactions.id`. The idempotency key. */
  paymentId: string;
  /** `users.id` of the member the plan is for (who paid is `paidBy`). */
  memberId: string;
  subscriptionId: string;
  /** `SubscriptionPlanDuration.id` — the `planPriceId` given to quoteReferral. */
  planDurationId: string;
  paidBy: PaymentPaidBy;
  /** The member's first paid plan: the only payment that earns a commission. */
  isFirstPaidPlan: boolean;
  /** The plan's price before any discount, excluding GST. */
  listAmountPaise: number;
  discountPaise: number;
  discountSource: PaymentDiscountSource;
  /** The referral code quoted at checkout (a plain id, no foreign key), or
   *  null when none was. */
  heldReferralCodeId: string | null;
  /** listAmountPaise − discountPaise, excluding GST: the commission base. */
  taxableAmountPaise: number;
  /** The GST rate when the payment was made, in basis points (1800 = 18%);
   *  0 while the business is not GST-registered. */
  taxRateBps: number;
  /** The GST added on top of taxableAmountPaise (see `addExclusiveTax`). */
  taxPaise: number;
  /** What the member actually paid: taxableAmountPaise + taxPaise. */
  amountPaidPaise: number;
  currency: 'INR';
  /** Keyed hash of the payment source (card, UPI id) when the provider
   *  reports one; for abuse checks only. Null otherwise. */
  paymentSourceHash: string | null;
  paidAt: string;
}

export interface PaymentRefunded {
  type: 'payment.refunded';
  version: typeof REFERRAL_EVENT_VERSION;
  /** The provider's refund id (Razorpay `rfnd_…`), or ours for a refund an
   *  admin records. The idempotency key. */
  refundId: string;
  paymentId: string;
  memberId: string;
  /** This refund alone, not the running total; part of amountPaidPaise. */
  refundedPaise: number;
  /** The GST part of this refund (see `refundTaxPaise`). */
  refundedTaxPaise: number;
  /** Everything refunded on the payment so far, this refund included. */
  totalRefundedPaise: number;
  /** True once totalRefundedPaise reaches the amount paid. */
  fullyRefunded: boolean;
  refundedAt: string;
}

export type ReferralEvent = PaymentSucceeded | PaymentRefunded;

/**
 * How the payments code hands events over. In-process for now (Render runs
 * no worker); a queue can replace it later without changing the shapes.
 * Resolves once every handler has accepted the event.
 */
export interface ReferralEventPublisher {
  publish(event: ReferralEvent): Promise<void>;
}

/** Nest injection token for the ReferralEventPublisher. */
export const REFERRAL_EVENT_PUBLISHER = Symbol('REFERRAL_EVENT_PUBLISHER');

/**
 * Adds GST to a taxable amount: taxPaise = round(taxable × rate / 10000),
 * totalPaise = taxable + taxPaise (what the member pays). At rate 0 the
 * total is the taxable amount.
 *
 * Rounding to the nearest paisa (half up) is provisional until the CA
 * confirms it; whatever is stored on the payment is what counts.
 */
export function addExclusiveTax(
  taxableAmountPaise: number,
  taxRateBps: number,
): { taxPaise: number; totalPaise: number } {
  assertPaise('taxableAmountPaise', taxableAmountPaise);
  if (!Number.isSafeInteger(taxRateBps) || taxRateBps < 0) {
    throw new RangeError('taxRateBps must be a non-negative integer.');
  }
  const taxPaise = Math.round((taxableAmountPaise * taxRateBps) / 10_000);
  return { taxPaise, totalPaise: taxableAmountPaise + taxPaise };
}

/**
 * The GST part of one refund, in proportion to the payment's GST within what
 * was paid. Computed on the running total, so however a payment is refunded
 * in pieces the parts add up to exactly `taxPaise` once it is fully refunded.
 */
export function refundTaxPaise(input: {
  amountPaidPaise: number;
  taxPaise: number;
  refundedBeforePaise: number;
  refundedPaise: number;
}): number {
  const { amountPaidPaise, taxPaise, refundedBeforePaise, refundedPaise } =
    input;
  assertPaise('amountPaidPaise', amountPaidPaise);
  assertPaise('taxPaise', taxPaise);
  assertPaise('refundedBeforePaise', refundedBeforePaise);
  assertPaise('refundedPaise', refundedPaise);
  if (taxPaise > amountPaidPaise) {
    throw new RangeError('taxPaise cannot exceed amountPaidPaise.');
  }
  if (refundedBeforePaise + refundedPaise > amountPaidPaise) {
    throw new RangeError('Refunds cannot exceed the amount paid.');
  }
  if (amountPaidPaise === 0) return 0;
  const taxUpTo = (refunded: number) =>
    Math.round((refunded * taxPaise) / amountPaidPaise);
  return (
    taxUpTo(refundedBeforePaise + refundedPaise) - taxUpTo(refundedBeforePaise)
  );
}

function assertPaise(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer (paise).`);
  }
}
