/**
 * `agent.clients_enabled`: the on/off switch for agent-added clients ("Way 2":
 * an agent adds a client, the client accepts with a one-time code). A Super
 * Admin changes it through the platform settings (no deploy).
 *
 * FAILS CLOSED, the opposite of `agent.quote_enabled`: only a stored `true`
 * turns the feature on. A missing key, `false`, or anything else that is
 * somehow stored means OFF. It is seeded `false`
 * (20261103090200_agent_client_settings_seed) so an admin can find it and
 * change it, and it stays off until someone deliberately turns it on. While
 * the one-time code is the test (dummy) code, turning it on still lets only
 * the approved test numbers through.
 *
 * Not one of the parsed agent-program keys (`RULES`): it is a switch, read on
 * its own, and a missing value must never make anything answer 503.
 */
export const AGENT_CLIENTS_ENABLED_KEY = 'agent.clients_enabled';

export function isAgentClientsEnabled(raw: Record<string, unknown>): boolean {
  if (!Object.prototype.hasOwnProperty.call(raw, AGENT_CLIENTS_ENABLED_KEY)) {
    return false;
  }
  return raw[AGENT_CLIENTS_ENABLED_KEY] === true;
}

/** The validator registered for the key (refused values answer 400 at admin entry). */
export function agentClientsEnabledProblem(value: unknown): string | null {
  return typeof value === 'boolean'
    ? null
    : `Setting ${AGENT_CLIENTS_ENABLED_KEY} must be true or false.`;
}
