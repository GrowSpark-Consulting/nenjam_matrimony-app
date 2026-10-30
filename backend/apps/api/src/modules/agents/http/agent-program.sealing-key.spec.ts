import type { PrismaClient } from '@app/database';
import { ServiceUnavailableException } from '@nestjs/common';
import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import {
  agentPiiSealerFor,
  buildAgentProgram,
  type AgentProgramDeps,
} from './agent-program';

// Test-only value, not a secret: 32 bytes of 0x07, base64.
const GOOD_KEY = Buffer.alloc(32, 7).toString('base64');

function deps(
  env: Record<string, string | undefined>,
  warn: jest.Mock<void, [string]>,
): AgentProgramDeps {
  return {
    prisma: {} as PrismaClient,
    platformSettings: {} as AgentProgramDeps['platformSettings'],
    otp: {} as AgentProgramDeps['otp'],
    hashing: {} as AgentProgramDeps['hashing'],
    adminAudit: {} as AgentProgramDeps['adminAudit'],
    env,
    logger: { warn },
  };
}

describe('AGENT_PII_ENCRYPTION_KEY at startup', () => {
  it('a missing key logs a warning and the program still builds', () => {
    const warn = jest.fn<void, [string]>();
    expect(() => buildAgentProgram(deps({}, warn))).not.toThrow();
    expect(
      warn.mock.calls.some((c) =>
        String(c[0]).startsWith('AGENT_PII_ENCRYPTION_KEY is not set'),
      ),
    ).toBe(true);
  });

  it('a blank key counts as missing', () => {
    const warn = jest.fn<void, [string]>();
    buildAgentProgram(deps({ AGENT_PII_ENCRYPTION_KEY: '   ' }, warn));
    expect(
      warn.mock.calls.some((c) => String(c[0]).includes('AGENT_PII_ENC')),
    ).toBe(true);
  });

  it('a valid key builds with no warning about it', () => {
    const warn = jest.fn<void, [string]>();
    buildAgentProgram(deps({ AGENT_PII_ENCRYPTION_KEY: GOOD_KEY }, warn));
    expect(
      warn.mock.calls.some((c) => String(c[0]).includes('AGENT_PII_ENC')),
    ).toBe(false);
  });

  it('a malformed key stops startup and the error does not show the value', () => {
    const bad = Buffer.alloc(16, 5).toString('base64');
    let message = '';
    try {
      buildAgentProgram(
        deps({ AGENT_PII_ENCRYPTION_KEY: bad }, jest.fn<void, [string]>()),
      );
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toContain('AGENT_PII_ENCRYPTION_KEY must be 32 random');
    expect(message).not.toContain(bad);
  });

  it('piiSealing follows the key', () => {
    expect(
      buildAgentProgram(deps({}, jest.fn<void, [string]>())).piiSealing,
    ).toBe(false);
    expect(
      buildAgentProgram(
        deps({ AGENT_PII_ENCRYPTION_KEY: GOOD_KEY }, jest.fn<void, [string]>()),
      ).piiSealing,
    ).toBe(true);
  });

  it('with no key the sealer refuses every seal and open with 503, never a stand-in key', () => {
    const sealer = agentPiiSealerFor(null);
    for (const purpose of Object.values(AGENT_SEAL_PURPOSES)) {
      for (const act of [
        () => sealer.seal(purpose, 'ABCDE1234F'),
        () => sealer.open(purpose, 'v1:AAAA'),
      ]) {
        let caught: unknown;
        try {
          act();
        } catch (e) {
          caught = e;
        }
        expect(caught).toBeInstanceOf(ServiceUnavailableException);
        expect(
          (caught as ServiceUnavailableException).getResponse(),
        ).toMatchObject({
          code: 'AGENT_PROGRAM_UNAVAILABLE',
        });
      }
    }
  });

  it('with a key the sealer round-trips per purpose', () => {
    const sealer = agentPiiSealerFor(Buffer.alloc(32, 7));
    const sealed = sealer.seal(AGENT_SEAL_PURPOSES.pan, 'ABCDE1234F');
    expect(sealer.open(AGENT_SEAL_PURPOSES.pan, sealed)).toBe('ABCDE1234F');
  });
});
