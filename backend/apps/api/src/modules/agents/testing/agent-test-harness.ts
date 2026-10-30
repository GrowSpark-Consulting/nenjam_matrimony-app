/**
 * One place that wires the agent services to the in-memory fakes, so the
 * service specs read as behaviour and not as set-up. Tests only.
 */
import { AgentReferralCodeService } from '../referral/agent-referral-code.service';
import { AgentReferralQuoteService } from '../referral/agent-referral-quote.service';
import { AgentReferralService } from '../referral/agent-referral.service';
import { AgentApplicationService } from '../application/agent-application.service';
import { AgentMeService } from '../agent/agent-me.service';
import { AgentProfileBuilder } from '../agent/agent-profile-builder';
import type { AgentStatus } from '../agent/agent-status';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import {
  AgentAuthOptions,
  AgentSessionIssuer,
} from '../auth/agent-session-issuer';
import { AgentSignInService } from '../auth/agent-sign-in.service';
import { StaticAgentContent } from '../content/agent-content';
import type {
  AgentAttributionStatus,
  AgentRecord,
} from '../ports/agent-data-ports';
import type { ReferralStage } from '../referral/agent-referral-view';
import type { AgentTokenSigner } from '../ports/agent-infra-ports';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
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
  FakeAgentMemberRead,
  FakeAgentPayoutDetailsRepository,
  FakeAgentRefreshTokenRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
  FakeReferralCodeAttemptStore,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentSecretSealer } from './fake-agent-secret-sealer';
import { FakeCommissionRepository } from './fake-agent-commission-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

export const PHONE = '+919876543210';
export const START = new Date('2026-10-28T10:00:00.000Z');

export const ACCESS_TTL = 900;
export const REFRESH_TTL = 2_592_000;
export const RESEND_AFTER = 30;
export const OTP_TTL_MS = 300_000;
export const IP_LIMIT = 3;
export const CODE_LIMIT = 2;
export const VALIDATION_WINDOW = 60;
export const CREDIT_WINDOW_DAYS = 60;

export const AUTH_OPTIONS: AgentAuthOptions & {
  applicantPhoneTtlSeconds: number;
} = {
  issuer: 'nenjam-agent',
  audience: 'agent-portal',
  refreshTokenPepper: 'test-pepper',
  applicantPhoneTtlSeconds: 1_800,
};

/** Signs like the fake, but can be told to fail. */
export class ControllableSigner implements AgentTokenSigner {
  failing = false;
  constructor(
    private readonly inner: AgentTokenSigner = new FakeAgentTokenSigner(
      'signer-key',
    ),
  ) {}

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
  options: {
    /** A different signer on the harness clock (e.g. the real HS256 one). */
    signerFor?: (clock: FakeAgentClock) => AgentTokenSigner;
  } = {},
) {
  const clock = new FakeAgentClock(START);
  const settings = new FakeAgentSettings({
    [AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY]: ACCESS_TTL,
    [AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY]: REFRESH_TTL,
    [AGENT_OTP_RESEND_AFTER_SECONDS_KEY]: RESEND_AFTER,
    [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 500,
    [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: CREDIT_WINDOW_DAYS,
    [REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY]: IP_LIMIT,
    [REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY]: CODE_LIMIT,
    [REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY]: VALIDATION_WINDOW,
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
  let attributionCounter = 0;
  const attributions = new FakeReferralAttributionRepository();
  const members = new FakeAgentMemberRead();
  const attempts = new FakeReferralCodeAttemptStore();
  const payoutDetails = new FakeAgentPayoutDetailsRepository();
  const sealer = new FakeAgentSecretSealer();
  const audit = new FakeAgentAudit();
  const permission = new FakeAgentPermission();
  const uow = new FakeAgentUnitOfWork();
  const signer = new ControllableSigner(options.signerFor?.(clock));
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

  const me = new AgentMeService({
    agents,
    payoutDetails,
    profiles,
    sealer,
    uow,
    audit,
    clock,
  });
  const commissions = new FakeCommissionRepository();
  const referrals = new AgentReferralService({
    access: me,
    codes,
    attributions,
    members,
    commissions,
    content,
    settings,
  });
  const referralCodes = new AgentReferralCodeService({
    settings,
    attempts,
    codes,
    agents,
    attributions,
    members,
    uow,
    audit,
    clock,
    newId: () => `attribution-${++attributionCounter}`,
  });
  const referralQuote = new AgentReferralQuoteService({
    settings,
    attempts,
    codes,
    agents,
    attributions,
    members,
    clock,
  });
  let agentCounter = 0;
  const application = new AgentApplicationService({
    agents,
    refreshTokens: tokens,
    applicants,
    sealer,
    uow,
    audit,
    clock,
    issuer,
    newId: () => `new-agent-${++agentCounter}`,
  });

  /** The verified claims inside a session's access token. */
  const claimsOf = async (session: { accessToken: string }) => {
    const claims = await signer.verify(session.accessToken);
    if (claims === null) throw new Error('not a token this harness signed');
    return claims;
  };

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

  /** A member who has signed up but is not (yet) credited to any agent. */
  const seedMember = (
    id: string,
    o: { phoneHash?: string | null; hasPaid?: boolean } = {},
  ) =>
    members.add(
      {
        memberId: id,
        phoneHash: o.phoneHash === undefined ? `hash-of-${id}` : o.phoneHash,
        signedUpAt: START,
        hasPaid: o.hasPaid ?? false,
      },
      {
        firstName: 'Priya',
        lastName: 'Sharma',
        phoneE164: '+919000000002',
        age: 27,
        city: 'Madurai',
        signedUpAt: START,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );

  /** Creates a referred member and the attribution that credits them to an agent. */
  const seedReferral = async (o: {
    id: string;
    agentId?: string;
    at?: Date;
    status?: AgentAttributionStatus;
    stage?: ReferralStage;
    firstName?: string;
    city?: string;
  }) => {
    const memberId = `member-${o.id}`;
    const at = o.at ?? START;
    members.add(
      {
        memberId,
        phoneHash: `member-hash-${o.id}`,
        signedUpAt: at,
        hasPaid: o.stage === 'PURCHASED',
      },
      {
        firstName: o.firstName ?? 'Priya',
        lastName: 'Sharma',
        phoneE164: '+919000000002',
        age: 27,
        city: o.city ?? 'Madurai',
        signedUpAt: at,
        stage: o.stage ?? 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
    return attributions.create({
      id: o.id,
      memberId,
      agentId: o.agentId ?? 'agent-1',
      codeId: 'code-1',
      source: 'CODE_AT_SIGNUP',
      memberPhoneHash: `member-hash-${o.id}`,
      attributedAt: at,
      status: o.status ?? 'ACTIVE',
      windowEndsAt: new Date(at.getTime() + 60 * 86_400_000),
      needsReview: false,
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
    attributions,
    members,
    attempts,
    payoutDetails,
    sealer,
    audit,
    permission,
    uow,
    signer,
    content,
    profiles,
    issuer,
    signIn,
    application,
    me,
    referrals,
    referralCodes,
    referralQuote,
    commissions,
    claimsOf,
    seedAgent,
    seedReferral,
    seedMember,
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
