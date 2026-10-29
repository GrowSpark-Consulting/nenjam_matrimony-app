import {
  REFERRAL_EVENT_VERSION,
  refundTaxPaise,
  type PaymentRefunded,
  type PaymentSucceeded,
} from '@app/common';
import type { PaymentTransaction } from '../../../../../../libs/database/generated/client';
import type { IdentifierHashService } from '../../platform/identifier-hash.service';

/**
 * The keyed hash stored as `paymentSourceHash`: of the payer's UPI id, when
 * Razorpay reports one. Null without one, or while identifier hashing is not
 * configured — it feeds abuse checks and must never block a payment.
 */
export function paymentSourceHashOf(
  hasher: IdentifierHashService,
  vpa: string | null | undefined,
): string | null {
  if (!vpa || !hasher.available) return null;
  try {
    return hasher.hashIdentifier('UPI', vpa);
  } catch {
    return null;
  }
}

/**
 * PaymentSucceeded from the payment as stored. A row from before the pricing
 * columns charged the list price with no discount and no GST, so its amount
 * is all three.
 */
export function paymentSucceededEvent(
  payment: PaymentTransaction,
  context: {
    subscriptionId: string;
    planDurationId: string;
    isFirstPaidPlan: boolean;
    paymentSourceHash: string | null;
    paidAt: Date;
  },
): PaymentSucceeded {
  return {
    type: 'payment.succeeded',
    version: REFERRAL_EVENT_VERSION,
    paymentId: payment.id,
    livemode: payment.livemode === true,
    memberId: payment.userId,
    subscriptionId: context.subscriptionId,
    planDurationId: context.planDurationId,
    paidBy: payment.paidBy,
    isFirstPaidPlan: context.isFirstPaidPlan,
    listAmountPaise: payment.listAmountPaise ?? payment.amountInr,
    discountPaise: payment.discountPaise,
    discountSource: payment.discountSource,
    heldReferralCodeId: payment.heldReferralCodeId,
    taxableAmountPaise: payment.taxableAmountPaise ?? payment.amountInr,
    taxRateBps: payment.taxRateBps ?? 0,
    taxPaise: payment.taxPaise ?? 0,
    amountPaidPaise: payment.amountInr,
    currency: 'INR',
    paymentSourceHash: context.paymentSourceHash,
    paidAt: context.paidAt.toISOString(),
  };
}

/** PaymentRefunded for one refund of a captured payment. */
export function paymentRefundedEvent(
  payment: PaymentTransaction,
  refund: {
    refundId: string;
    refundedPaise: number;
    totalRefundedPaise: number;
    refundedAt: Date;
  },
): PaymentRefunded {
  return {
    type: 'payment.refunded',
    version: REFERRAL_EVENT_VERSION,
    refundId: refund.refundId,
    paymentId: payment.id,
    livemode: payment.livemode === true,
    memberId: payment.userId,
    refundedPaise: refund.refundedPaise,
    refundedTaxPaise: refundTaxPaise({
      amountPaidPaise: payment.amountInr,
      taxPaise: payment.taxPaise ?? 0,
      refundedBeforePaise: refund.totalRefundedPaise - refund.refundedPaise,
      refundedPaise: refund.refundedPaise,
    }),
    totalRefundedPaise: refund.totalRefundedPaise,
    fullyRefunded: refund.totalRefundedPaise >= payment.amountInr,
    refundedAt: refund.refundedAt.toISOString(),
  };
}
