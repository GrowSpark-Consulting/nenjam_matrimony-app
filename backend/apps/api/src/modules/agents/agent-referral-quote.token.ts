/**
 * The injection token under which the agents module exports
 * `AgentReferralQuoteService` to the checkout (Shaaz's Payments PR).
 *
 * The checkout injects it OPTIONALLY (`@Optional() @Inject(AGENT_REFERRAL_QUOTE)`):
 * when nothing is provided it charges the list price with no discount.
 *
 * Provided by AgentReferralQuoteModule (quote/), only when identifier hashing
 * and the quote's settings are configured; otherwise its value is null.
 */
import type { AgentReferralQuoteService } from './referral/agent-referral-quote.service';

export const AGENT_REFERRAL_QUOTE = Symbol('AGENT_REFERRAL_QUOTE');

export type AgentReferralQuote = Pick<AgentReferralQuoteService, 'quote'>;
