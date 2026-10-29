/**
 * The injection token under which the agents module exports
 * `AgentReferralQuoteService` to the checkout (Shaaz's Payments PR).
 *
 * The checkout injects it OPTIONALLY (`@Optional() @Inject(AGENT_REFERRAL_QUOTE)`):
 * when nothing is provided it charges the list price with no discount.
 *
 * NOT PROVIDED YET: the quote needs the member read adapter (the member's
 * verified phone hash and whether they have paid), which waits for the
 * Payments PR's payment fields. Until then the token exists so his code can
 * import it, and the module provides nothing under it.
 */
import type { AgentReferralQuoteService } from './referral/agent-referral-quote.service';

export const AGENT_REFERRAL_QUOTE = Symbol('AGENT_REFERRAL_QUOTE');

export type AgentReferralQuote = Pick<AgentReferralQuoteService, 'quote'>;
