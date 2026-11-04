import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AgentSettingValidators } from '../adapters/platform/agent-platform.adapters';
import type { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { AGENT_PROGRAM_SETTING_KEYS } from './agent-program-settings';
import {
  AGENT_CLIENTS_ENABLED_KEY,
  agentClientsEnabledProblem,
  isAgentClientsEnabled,
} from './agent-clients-switch';

describe('agent.clients_enabled', () => {
  it('is named as agreed and is not one of the parsed keys', () => {
    expect(AGENT_CLIENTS_ENABLED_KEY).toBe('agent.clients_enabled');
    expect(AGENT_PROGRAM_SETTING_KEYS).not.toContain(AGENT_CLIENTS_ENABLED_KEY);
  });

  it('missing means OFF; only a stored true turns it on', () => {
    expect(isAgentClientsEnabled({})).toBe(false);
    expect(isAgentClientsEnabled({ [AGENT_CLIENTS_ENABLED_KEY]: true })).toBe(
      true,
    );
    for (const value of [false, null, 'true', 1, 0, undefined, {}]) {
      expect([
        value,
        isAgentClientsEnabled({ [AGENT_CLIENTS_ENABLED_KEY]: value }),
      ]).toEqual([value, false]);
    }
  });

  it('an inherited value does not count as set', () => {
    const raw = Object.create({ [AGENT_CLIENTS_ENABLED_KEY]: true }) as Record<
      string,
      unknown
    >;
    expect(isAgentClientsEnabled(raw)).toBe(false);
  });

  it('the validator accepts only a boolean', () => {
    expect(agentClientsEnabledProblem(true)).toBeNull();
    expect(agentClientsEnabledProblem(false)).toBeNull();
    for (const value of [null, 'false', 0, 1, {}, []]) {
      expect(agentClientsEnabledProblem(value)).toBe(
        'Setting agent.clients_enabled must be true or false.',
      );
    }
  });

  it('the validator is registered at startup', () => {
    const registered = new Map<string, (v: unknown) => string | null>();
    const settings = {
      registerValidator: (key: string, fn: (v: unknown) => string | null) =>
        registered.set(key, fn),
    } as unknown as PlatformSettingsService;
    new AgentSettingValidators(settings).onModuleInit();
    const fn = registered.get(AGENT_CLIENTS_ENABLED_KEY);
    expect(fn?.(true)).toBeNull();
    expect(fn?.('yes')).not.toBeNull();
  });

  it('exactly one migration seeds it, and seeds it false', () => {
    const dir = join(
      __dirname,
      '../../../../../../libs/database/prisma/migrations',
    );
    const seeding = readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .filter((d) =>
        readFileSync(join(dir, d.name, 'migration.sql'), 'utf8').includes(
          `'${AGENT_CLIENTS_ENABLED_KEY}'`,
        ),
      )
      .map((d) => d.name);
    expect(seeding).toEqual(['20261103090200_agent_client_settings_seed']);
    const sql = readFileSync(join(dir, seeding[0], 'migration.sql'), 'utf8');
    expect(sql).toContain(`('${AGENT_CLIENTS_ENABLED_KEY}', 'false'::jsonb,`);
  });
});
