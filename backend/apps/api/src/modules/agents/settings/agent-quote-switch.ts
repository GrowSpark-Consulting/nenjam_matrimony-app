/**
 * `agent.quote_enabled`: the runtime kill switch for the referral quote at
 * checkout. A Super Admin sets it to `false` through the platform settings
 * (no deploy) and every quote answers "no discount" straight away: a
 * purchase with no code pays the list price, and a typed code is refused by
 * the checkout (422 PROMO_CODE_REJECTED, reason QUOTE_DISABLED). Setting it
 * back to `true`, or deleting it, turns the quote on again.
 *
 * NOT one of the 18 seeded agent-program keys and never seeded: a missing
 * key means ENABLED. Only a boolean can be stored (the validator below);
 * anything else that is somehow stored counts as disabled (it fails closed:
 * no discount, nothing attached).
 */
export const AGENT_QUOTE_ENABLED_KEY = 'agent.quote_enabled';

export function isAgentQuoteEnabled(raw: Record<string, unknown>): boolean {
  if (!Object.prototype.hasOwnProperty.call(raw, AGENT_QUOTE_ENABLED_KEY)) {
    return true;
  }
  return raw[AGENT_QUOTE_ENABLED_KEY] === true;
}

/** The validator registered for the key (refused values answer 400 at admin entry). */
export function agentQuoteEnabledProblem(value: unknown): string | null {
  return typeof value === 'boolean'
    ? null
    : `Setting ${AGENT_QUOTE_ENABLED_KEY} must be true or false.`;
}
