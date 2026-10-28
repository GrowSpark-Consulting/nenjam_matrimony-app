import { AgentConfigError } from '../config/agent-config.service';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
} from '../settings/agent-program-settings';
import {
  ACCESS_TTL,
  AUTH_OPTIONS,
  makeAgentHarness,
  REFRESH_TTL,
} from '../testing/agent-test-harness';
import { assertAgentAuthOptions } from './agent-session-issuer';

describe('assertAgentAuthOptions', () => {
  it('accepts good options', () => {
    expect(() => assertAgentAuthOptions(AUTH_OPTIONS)).not.toThrow();
  });

  it.each([
    { issuer: '' },
    { audience: '' },
    { refreshTokenPepper: '' },
    { applicantPhoneTtlSeconds: 0 },
    { applicantPhoneTtlSeconds: -5 },
    { applicantPhoneTtlSeconds: 1.5 },
    { applicantPhoneTtlSeconds: NaN },
  ])('refuses %p, with no default filled in', (override) => {
    expect(() =>
      assertAgentAuthOptions({ ...AUTH_OPTIONS, ...override }),
    ).toThrow(RangeError);
  });
});

describe('AgentSessionIssuer.lifetimes', () => {
  it('reads both lifetimes from the settings', async () => {
    const h = makeAgentHarness();
    await expect(h.issuer.lifetimes()).resolves.toEqual({
      accessTtlSeconds: ACCESS_TTL,
      refreshTtlSeconds: REFRESH_TTL,
    });
  });

  it('reads them again on every call (no caching)', async () => {
    const h = makeAgentHarness();
    h.settings.set(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY, 60);
    h.settings.set(AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY, 120);
    await expect(h.issuer.lifetimes()).resolves.toEqual({
      accessTtlSeconds: 60,
      refreshTtlSeconds: 120,
    });
  });

  it('lists every missing lifetime, and invents none', async () => {
    const h = makeAgentHarness();
    h.settings.remove(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY);
    h.settings.remove(AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY);
    const error = await h.issuer.lifetimes().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AgentConfigError);
    expect((error as AgentConfigError).missing).toEqual([
      AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
      AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
    ]);
  });

  it.each([0, -1, 1.5, '900'])(
    'refuses an access lifetime of %p',
    async (v) => {
      const h = makeAgentHarness();
      h.settings.set(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY, v);
      await expect(h.issuer.lifetimes()).rejects.toThrow(RangeError);
    },
  );
});
