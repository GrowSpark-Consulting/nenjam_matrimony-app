import {
  addExclusiveTax,
  type PaymentDiscountSource,
  type ReferralQuoteResult,
} from '@app/common';

/** Razorpay's smallest charge. */
export const MIN_CHARGE_PAISE = 100;

const DISCOUNT_SOURCES: readonly PaymentDiscountSource[] = [
  'NONE',
  'REFERRAL_FIRST_PLAN',
];

/** What a purchase costs, fixed at checkout and stored on the payment. */
export interface CheckoutPricing {
  /** The plan price, excluding GST. */
  listAmountPaise: number;
  discountPaise: number;
  discountSource: PaymentDiscountSource;
  heldReferralCodeId: string | null;
  /** listAmountPaise − discountPaise. */
  taxableAmountPaise: number;
  taxRateBps: number;
  /** GST added on top of the taxable amount. */
  taxPaise: number;
  /** What the member pays: taxableAmountPaise + taxPaise. */
  totalPaise: number;
}

/** The quote and the price disagree, or the result can't be charged. */
export class PricingError extends Error {
  constructor(
    public readonly code: 'INCONSISTENT_QUOTE' | 'BELOW_MINIMUM_CHARGE',
    message: string,
  ) {
    super(message);
    this.name = 'PricingError';
  }
}

/**
 * The price of a purchase: the list price, less the referral discount the
 * agent program quoted (none without a quote), plus GST on top. Every amount
 * in the quote is re-derived here and checked, so a wrong quote can never
 * change what is charged without being noticed — it is refused instead.
 */
export function priceCheckout(
  listAmountPaise: number,
  quote: ReferralQuoteResult | null,
  taxRateBps: number,
): CheckoutPricing {
  if (!Number.isSafeInteger(listAmountPaise) || listAmountPaise < 0) {
    throw new RangeError('listAmountPaise must be a non-negative integer.');
  }
  const discountPaise = quote?.discountPaise ?? 0;
  const discountSource = quote?.discountSource ?? 'NONE';
  if (
    !Number.isSafeInteger(discountPaise) ||
    discountPaise < 0 ||
    discountPaise > listAmountPaise ||
    !DISCOUNT_SOURCES.includes(discountSource) ||
    (discountSource === 'NONE') !== (discountPaise === 0)
  ) {
    throw new PricingError(
      'INCONSISTENT_QUOTE',
      `Unusable referral quote: discount ${String(discountPaise)} (${String(discountSource)}) on ${listAmountPaise}.`,
    );
  }
  const taxableAmountPaise = listAmountPaise - discountPaise;
  if (
    quote !== null &&
    quote.taxableAfterDiscountPaise !== undefined &&
    quote.taxableAfterDiscountPaise !== taxableAmountPaise
  ) {
    throw new PricingError(
      'INCONSISTENT_QUOTE',
      `Referral quote says ${quote.taxableAfterDiscountPaise} after discount; list − discount is ${taxableAmountPaise}.`,
    );
  }
  const { taxPaise, totalPaise } = addExclusiveTax(
    taxableAmountPaise,
    taxRateBps,
  );
  if (totalPaise < MIN_CHARGE_PAISE) {
    throw new PricingError(
      'BELOW_MINIMUM_CHARGE',
      `A charge must be at least ${MIN_CHARGE_PAISE} paise; this one is ${totalPaise}.`,
    );
  }
  return {
    listAmountPaise,
    discountPaise,
    discountSource,
    heldReferralCodeId:
      discountSource === 'NONE' ? null : (quote?.heldReferralCodeId ?? null),
    taxableAmountPaise,
    taxRateBps,
    taxPaise,
    totalPaise,
  };
}

/** The `payment.gst_rate_bps` setting, or null when missing or unusable. */
export function parseGstRateBps(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= 10_000
    ? value
    : null;
}

export const GST_RATE_SETTING = 'payment.gst_rate_bps';
