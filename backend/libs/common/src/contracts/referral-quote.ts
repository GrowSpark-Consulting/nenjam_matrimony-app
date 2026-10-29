import type { PaymentDiscountSource } from './referral-events';

/**
 * The referral discount checkout asks the agent program for, before it
 * creates the payment order. The contract between checkout (Shaaz) and the
 * agent program's quote service (Nithisha).
 *
 * The agent program provides it under its token AGENT_REFERRAL_QUOTE
 * (modules/agents/agent-referral-quote.token.ts) from a GLOBAL module;
 * checkout injects it optionally. Without it — agent program not wired —
 * checkout charges the list price and refuses a typed promo code.
 *
 * Read-only: quoting never attaches a code or counts as a use. Checkout
 * re-derives every amount from the quote and refuses to charge when they
 * disagree (taxable = list − discount, discount 0 exactly when the source is
 * NONE).
 */
export interface ReferralQuoteRequest {
  /** `users.id` of the member about to pay. */
  memberId: string;
  /** What the member typed at checkout; absent or blank means none. */
  promoCode?: string | null;
  /** `SubscriptionPlanDuration.id` being bought. */
  planPriceId: string;
  /** The plan price before any discount, excluding GST. */
  listAmountPaise: number;
}

export interface ReferralQuoteResult {
  discountPaise: number;
  discountSource: PaymentDiscountSource;
  /** listAmountPaise − discountPaise, excluding GST. */
  taxableAfterDiscountPaise: number;
  /** The code to hold on the payment (a plain id), when one applies. */
  heldReferralCodeId?: string;
  /** "Ravi K." — the agent the discount comes from. */
  agentDisplayName?: string;
  /** Why a typed code gave no discount (INVALID, NOT_FIRST_PLAN, …). */
  rejectedReason?: string;
}

export interface ReferralQuoteProvider {
  quote(request: ReferralQuoteRequest): Promise<ReferralQuoteResult>;
}
