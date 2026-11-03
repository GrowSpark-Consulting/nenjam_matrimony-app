import type { PrismaClient } from '@app/database';
import { buildAgentAccessClaims } from '../auth/agent-access-claims';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import {
  AGENT_TOKEN_AUDIENCE,
  AGENT_TOKEN_ISSUER,
  CLIENT_TOKEN_AUDIENCE,
  buildAgentProgram,
  type AgentProgramDeps,
} from './agent-program';

// Test-only value, not a secret.
const SECRET = 'test-only-agent-jwt-secret-not-real-0000';

function program(env: Record<string, string | undefined>) {
  const deps: AgentProgramDeps = {
    prisma: {} as PrismaClient,
    platformSettings: {} as AgentProgramDeps['platformSettings'],
    otp: {} as AgentProgramDeps['otp'],
    hashing: {} as AgentProgramDeps['hashing'],
    adminAudit: {} as AgentProgramDeps['adminAudit'],
    firebase: {} as AgentProgramDeps['firebase'],
    agentOtp: { dummyEnabled: false, dummyPhones: [] },
    env,
    logger: { warn: jest.fn() },
  };
  return buildAgentProgram(deps);
}

const now = new Date();
const sign = (audience: string, scope: 'AGENT' | 'CLIENT') =>
  new AgentJwtTokenSigner(
    {
      secret: SECRET,
      issuer: AGENT_TOKEN_ISSUER,
      audience,
      scopes: [scope],
    },
    { now: () => now },
  ).sign(
    buildAgentAccessClaims({
      agentId: scope === 'AGENT' ? 'agent-1' : null,
      phoneHash: '',
      clientRef: scope === 'CLIENT' ? 'sealed-phone' : undefined,
      scope,
      now,
      ttlSeconds: 900,
      issuer: AGENT_TOKEN_ISSUER,
      audience,
    }),
  );

describe('the client token as the real wiring builds it', () => {
  it('has its own audience', () => {
    expect(CLIENT_TOKEN_AUDIENCE).toBe('nenjam-client-invite');
    expect(CLIENT_TOKEN_AUDIENCE).not.toBe(AGENT_TOKEN_AUDIENCE);
  });

  it('the client checker accepts a client token and refuses an agent token; the agent checker the reverse', async () => {
    const p = program({ AGENT_JWT_SECRET: SECRET });
    const client = await sign(CLIENT_TOKEN_AUDIENCE, 'CLIENT');
    const agent = await sign(AGENT_TOKEN_AUDIENCE, 'AGENT');
    await expect(p.clientTokens!.check(client)).resolves.toMatchObject({
      ok: true,
      claims: { scope: 'CLIENT' },
    });
    await expect(p.clientTokens!.check(agent)).resolves.toEqual({
      ok: false,
      reason: 'INVALID',
    });
    await expect(p.tokens!.check(client)).resolves.toEqual({
      ok: false,
      reason: 'INVALID',
    });
    await expect(p.tokens!.check(agent)).resolves.toMatchObject({ ok: true });
  });

  it('an agent-scoped token minted for the client audience is still refused there', async () => {
    const p = program({ AGENT_JWT_SECRET: SECRET });
    const forged = await new AgentJwtTokenSigner(
      {
        secret: SECRET,
        issuer: AGENT_TOKEN_ISSUER,
        audience: CLIENT_TOKEN_AUDIENCE,
        scopes: ['AGENT'],
      },
      { now: () => now },
    ).sign(
      buildAgentAccessClaims({
        agentId: 'agent-1',
        phoneHash: '',
        scope: 'AGENT',
        now,
        ttlSeconds: 900,
        issuer: AGENT_TOKEN_ISSUER,
        audience: CLIENT_TOKEN_AUDIENCE,
      }),
    );
    await expect(p.clientTokens!.check(forged)).resolves.toEqual({
      ok: false,
      reason: 'INVALID',
    });
  });

  it('without the secret there is no client checker either', () => {
    const p = program({});
    expect(p.tokens).toBeNull();
    expect(p.clientTokens).toBeNull();
  });
});
