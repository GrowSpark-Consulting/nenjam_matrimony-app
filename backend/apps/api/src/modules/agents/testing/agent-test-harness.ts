/**
 * One place that wires the agent services to the in-memory fakes, so the
 * service specs read as behaviour and not as set-up. Tests only.
 */
import { AgentProfileBuilder } from '../agent/agent-profile-builder';
import type { AgentStatus } from '../agent/agent-status';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import {
  AgentAuthOptions,
  AgentSessionIssuer,
} from '../auth/agent-session-issuer';
import { AgentSignInService } from '../auth/agent-sign-in.service';
import { StaticAgentContent } from '../content/agent-content';
import type { AgentRecord } from '../ports/agent-data-ports';
import type { AgentTokenSigner } from '../ports/agent-infra-ports';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
} from '../settings/agent-program-settings';
import { FakeAgentClock, FakeAgentTokenSigner } from './fake-agent-infra';
import {
  FakeAgentAudit,
  FakeAgentIdentifierHasher,
  FakeAgentOtp,
  FakeAgentPermission,
  FakeAgentSettings,
} from './fake-agent-platform';
import {
  FakeAgentApplicantRepository,
  FakeAgentRefreshTokenRepository,
  FakeAgentRepository,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentSecretSealer } from './fake-agent-secret-sealer';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

export const PHONE = '+919876543210';
export const START = new Date('2026-10-28T10:00:00.000Z');

export const ACCESS_TTL = 900;
export const REFRESH_TTL = 2_592_000;
export const RESEND_AFTER = 30;
export const OTP_TTL_MS = 300_000;

export const AUTH_OPTIONS: AgentAuthOptions = {
  issuer: 'nenjam-agent',
  audience: 'agent-portal',
  refreshTokenPepper: 'test-pepper',
  applicantPhoneTtlSeconds: 1_800,
};

/** Signs like the fake, but can be told to fail. */
export class ControllableSigner implements AgentTokenSigner {
  failing = false;
  private readonly inner = new FakeAgentTokenSigner('signer-key');

  sign(claims: AgentAccessClaims): Promise<string> {
    return this.failing
      ? Promise.reject(new Error('signer unavailable'))
      : this.inner.sign(claims);
  }

  verify(token: string): Promise<AgentAccessClaims | null> {
    return this.inner.verify(token);
  }
}

export function makeAgentHarness(
  settingsOverrides: Record<string, unknown> = {},
) {
  const clock = new FakeAgentClock(START);
  const settings = new FakeAgentSettings({
    [AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY]: ACCESS_TTL,
    [AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY]: REFRESH_TTL,
    [AGENT_OTP_RESEND_AFTER_SECONDS_KEY]: RESEND_AFTER,
    ...settingsOverrides,
  });
  const otp = new FakeAgentOtp({
    clock,
    ttlMs: OTP_TTL_MS,
    maxAttempts: 3,
    sendLimit: 3,
    sendWindowMs: 600_000,
  });
  const hasher = new FakeAgentIdentifierHasher('hash-secret');
  const agents = new FakeAgentRepository();
  const codes = new FakeReferralCodeRepository();
  const tokens = new FakeAgentRefreshTokenRepository();
  const applicants = new FakeAgentApplicantRepository();
  const sealer = new FakeAgentSecretSealer();
  const audit = new FakeAgentAudit();
  const permission = new FakeAgentPermission();
  const uow = new FakeAgentUnitOfWork();
  const signer = new ControllableSigner();
  const content = new StaticAgentContent();
  const profiles = new AgentProfileBuilder(content, codes);
  let counter = 0;
  const issuer = new AgentSessionIssuer({
    signer,
    clock,
    settings,
    refreshTokens: tokens,
    profiles,
    options: AUTH_OPTIONS,
    newId: () => `id-${++counter}`,
  });
  const signIn = new AgentSignInService({
    otp,
    hasher,
    agents,
    refreshTokens: tokens,
    applicants,
    sealer,
    uow,
    audit,
    settings,
    clock,
    issuer,
    options: AUTH_OPTIONS,
  });

  /** Creates an agent record for `phone` in the given status. */
  const seedAgent = async (
    status: string = 'ACTIVE',
    overrides: Partial<AgentRecord> = {},
  ): Promise<AgentRecord> => {
    const phone = overrides.phoneE164 ?? PHONE;
    const created = await agents.create({
      id: overrides.id ?? 'agent-1',
      phoneHash: hasher.hash('PHONE', phone),
      phoneE164: phone,
      name: 'Ravi Kumar',
      city: 'Coimbatore',
      state: 'Tamil Nadu',
      panLast4: null,
      panSealed: null,
      createdAt: START,
    });
    return agents.update(created.id, {
      status: status as AgentStatus,
      approvedAt: status === 'ACTIVE' ? START : null,
      ...overrides,
    });
  };

  /** start + verify with the right code: what a user does. */
  const signInAs = async (phone = PHONE) => {
    const { challengeId } = await signIn.start(phone);
    return signIn.verify(challengeId, otp.codeFor(challengeId));
  };

  return {
    clock,
    settings,
    otp,
    hasher,
    agents,
    codes,
    tokens,
    applicants,
    sealer,
    audit,
    permission,
    uow,
    signer,
    content,
    profiles,
    issuer,
    signIn,
    seedAgent,
    signInAs,
  };
}

export type AgentHarness = ReturnType<typeof makeAgentHarness>;

/** Asserts a promise rejects with an AgentServiceError of this code. */
export async function expectServiceError(
  promise: Promise<unknown>,
  code: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  await expect(promise).rejects.toMatchObject({
    name: 'AgentServiceError',
    code,
    ...extra,
  });
}
