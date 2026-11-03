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
  AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY,
  AGENT_CLIENT_DRAFT_LIMIT_KEY,
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
import { AgentMoneyService } from '../agent/agent-money.service';
import {
  FakeAgentLedgerRepository,
  FakeAgentPayoutRepository,
  FakeCommissionRepository,
} from './fake-agent-commission-repositories';
import {
  FakeAgentCommissionDisplay,
  FakeAgentDeviceRepository,
} from './fake-agent-money-read';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';
import { DummyClientPhoneProof } from '../adapters/platform/dummy-client-phone-proof';
import { AgentClientDraftService } from '../clients/agent-client-draft.service';
import { ClientInviteService } from '../clients/client-invite.service';
import type { ClientBasicDetails } from '../ports/agent-client-ports';
import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import { FakeAgentClientAccount } from './fake-agent-client-account';
import {
  FakeAgentClientConsentCodeStore,
  FakeAgentClientDraftRepository,
} from './fake-agent-clients';

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

/** Agent-added clients: two approved test numbers and one that is not. */
export const CLIENT_PHONE = '+919000000001';
export const CLIENT_PHONE_2 = '+919000000002';
export const UNAPPROVED_PHONE = '+919999999999';
export const CLIENT_DRAFT_LIMIT = 3;
export const CLIENT_EXPIRY_DAYS = 14;
/** The client token's own audience (the agent portal's is AUTH_OPTIONS.audience). */
export const CLIENT_TOKEN_OPTIONS = {
  issuer: 'nenjam-agent',
  audience: 'client-invite',
};
export const CLIENT_DETAILS: ClientBasicDetails = {
  firstName: 'Priya',
  lastName: 'Sundaram',
  gender: 'FEMALE',
  dob: '1998-04-12',
  maritalStatus: 'NEVER_MARRIED',
  profileCreatedFor: 'Daughter',
};

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
    /** Earlier pepper versions still active (a rotation in progress). */
    olderPeppers?: readonly string[];
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
    [AGENT_CLIENTS_ENABLED_KEY]: true,
    [AGENT_CLIENT_DRAFT_LIMIT_KEY]: CLIENT_DRAFT_LIMIT,
    [AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY]: CLIENT_EXPIRY_DAYS,
    ...settingsOverrides,
  });
  const otp = new FakeAgentOtp({
    clock,
    ttlMs: OTP_TTL_MS,
    maxAttempts: 3,
    sendLimit: 3,
    sendWindowMs: 600_000,
  });
  const hasher = new FakeAgentIdentifierHasher(
    'hash-secret',
    options.olderPeppers ?? [],
  );
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

  const ledger = new FakeAgentLedgerRepository();
  const payouts = new FakeAgentPayoutRepository();
  const commissionDisplay = new FakeAgentCommissionDisplay();
  const devices = new FakeAgentDeviceRepository();
  const money = new AgentMoneyService({
    access: me,
    commissions,
    ledger,
    payouts,
    display: commissionDisplay,
    devices,
    settings,
  });

  const drafts = new FakeAgentClientDraftRepository(agents);
  const consentCodes = new FakeAgentClientConsentCodeStore();
  const clientAccount = new FakeAgentClientAccount();
  const clientProof = new DummyClientPhoneProof({
    otp,
    codes: consentCodes,
    hasher,
    config: {
      dummyEnabled: true,
      dummyPhones: [CLIENT_PHONE, CLIENT_PHONE_2],
      // Not used by the fake OTP (it makes its own codes); only must be set.
      dummyCode: '000000',
    },
  });
  const clientLog = { warn: jest.fn<void, [message: string]>() };
  let draftCounter = 0;
  const clients = new AgentClientDraftService({
    access: me,
    drafts,
    attributions,
    accounts: clientAccount,
    proof: clientProof,
    hasher,
    sealer,
    settings,
    content,
    uow,
    audit,
    clock,
    newId: () => `draft-${++draftCounter}`,
    logger: clientLog,
  });

  // Its own key: the agent signer can never verify a client token.
  const clientSigner = new FakeAgentTokenSigner('client-signer-key');
  let clientAttributionCounter = 0;
  const clientInvites = new ClientInviteService({
    settings,
    proof: clientProof,
    hasher,
    drafts,
    agents,
    attributions,
    accounts: clientAccount,
    sealer,
    uow,
    audit,
    clock,
    signer: clientSigner,
    options: CLIENT_TOKEN_OPTIONS,
    newId: () => `client-attribution-${++clientAttributionCounter}`,
  });

  /** request + verify with the code she would have received: a client signing in. */
  const clientSignIn = async (phone = CLIENT_PHONE) => {
    await clientInvites.requestCode(phone);
    const pointer = await consentCodes.find([hasher.hash('PHONE', phone)]);
    if (pointer === null) throw new Error('no code was sent');
    return clientInvites.verifyCode(phone, otp.codeFor(pointer.challengeId));
  };

  /** The verified claims inside a client token. */
  const clientClaimsOf = async (session: { accessToken: string }) => {
    const claims = await clientSigner.verify(session.accessToken);
    if (claims === null) throw new Error('not a client token');
    return claims;
  };

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
    ledger,
    payouts,
    commissionDisplay,
    devices,
    money,
    drafts,
    consentCodes,
    clientAccount,
    clientProof,
    clientLog,
    clients,
    clientSigner,
    clientInvites,
    clientSignIn,
    clientClaimsOf,
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
