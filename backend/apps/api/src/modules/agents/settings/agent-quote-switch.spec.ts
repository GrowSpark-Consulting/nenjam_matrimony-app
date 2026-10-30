import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AgentSettingValidators } from '../adapters/platform/agent-platform.adapters';
import type { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { AGENT_PROGRAM_SETTING_KEYS } from './agent-program-settings';
import {
  AGENT_QUOTE_ENABLED_KEY,
  agentQuoteEnabledProblem,
  isAgentQuoteEnabled,
} from './agent-quote-switch';

describe('agent.quote_enabled', () => {
  it('is named as agreed and is not one of the 18 seeded keys', () => {
    expect(AGENT_QUOTE_ENABLED_KEY).toBe('agent.quote_enabled');
    expect(AGENT_PROGRAM_SETTING_KEYS).not.toContain(AGENT_QUOTE_ENABLED_KEY);
    expect(AGENT_PROGRAM_SETTING_KEYS).toHaveLength(18);
  });

  it('no migration seeds it', () => {
    const dir = join(
      __dirname,
      '../../../../../../libs/database/prisma/migrations',
    );
    const seeding = readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .filter((d) =>
        readFileSync(join(dir, d.name, 'migration.sql'), 'utf8').includes(
          AGENT_QUOTE_ENABLED_KEY,
        ),
      )
      .map((d) => d.name);
    expect(seeding).toEqual([]);
  });

  it('missing means enabled; only true enables when it is set', () => {
    expect(isAgentQuoteEnabled({})).toBe(true);
    expect(isAgentQuoteEnabled({ [AGENT_QUOTE_ENABLED_KEY]: true })).toBe(true);
    for (const value of [false, null, 'true', 1, 0, undefined]) {
      expect([
        value,
        isAgentQuoteEnabled({ [AGENT_QUOTE_ENABLED_KEY]: value }),
      ]).toEqual([value, false]);
    }
  });

  it('the validator accepts only a boolean', () => {
    expect(agentQuoteEnabledProblem(true)).toBeNull();
    expect(agentQuoteEnabledProblem(false)).toBeNull();
    for (const value of [null, 'false', 0, 1, {}, []]) {
      expect(agentQuoteEnabledProblem(value)).toBe(
        'Setting agent.quote_enabled must be true or false.',
      );
    }
  });

  it('the validator is registered at startup, with the seeded keys', () => {
    const registered = new Map<string, (v: unknown) => string | null>();
    const settings = {
      registerValidator: (key: string, fn: (v: unknown) => string | null) =>
        registered.set(key, fn),
    } as unknown as PlatformSettingsService;
    new AgentSettingValidators(settings).onModuleInit();
    expect(registered.size).toBe(19);
    const fn = registered.get(AGENT_QUOTE_ENABLED_KEY);
    expect(fn?.(false)).toBeNull();
    expect(fn?.('no')).not.toBeNull();
  });
});
