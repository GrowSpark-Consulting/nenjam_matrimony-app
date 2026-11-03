/**
 * The first check of every Way 2 route: `agent.clients_enabled` must be
 * stored as exactly `true`. Missing, false or anything else is OFF and the
 * route answers 403 CLIENT_INVITES_DISABLED (fails closed). Read on every
 * call, so switching it needs no deploy. The daily expiry does NOT check it:
 * drafts still expire, and their PII is still deleted, while it is off.
 */
import { AgentServiceError } from '../errors/agent-service-error';
import type { AgentSettingsPort } from '../ports/agent-platform-ports';
import {
  AGENT_CLIENTS_ENABLED_KEY,
  isAgentClientsEnabled,
} from '../settings/agent-clients-switch';

export async function assertAgentClientsEnabled(
  settings: AgentSettingsPort,
): Promise<void> {
  const raw = await settings.getMany([AGENT_CLIENTS_ENABLED_KEY]);
  if (!isAgentClientsEnabled(raw)) {
    throw new AgentServiceError('CLIENT_INVITES_DISABLED');
  }
}
