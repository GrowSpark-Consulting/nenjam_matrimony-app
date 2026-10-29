import type { AgentApi, PageQuery } from './agentApi';
import { ApiError } from './errors';
import type { SessionStore } from './session';
import type {
  AgentConfig,
  AgentProfile,
  AgentSession,
  AgentStatus,
  ApplicationInput,
  Balance,
  Commission,
  CommissionStatus,
  LocalizedText,
  OtpRequestResponse,
  Page,
  Payout,
  PayoutDetailsInput,
  PayoutDetailsSummary,
  ReferralLink,
  ReferralStage,
  ReferralView,
  Session,
} from './types';

/**
 * In-browser stand-in for the agent API while the backend endpoints are
 * designed but not built. Shapes follow the contract on main. Development and
 * tests only: a production build cannot load this module (see api/index.ts).
 * Nothing here is a real agent or member.
 *
 * Seeded test phones (any 4–8 digit OTP is accepted, like the dummy OTP):
 *   +919000000001 PENDING_APPROVAL   +919000000004 TERMINATED
 *   +919000000002 REJECTED           +919000000005 ACTIVE
 *   +919000000003 SUSPENDED (Paused)
 * Any other valid phone signs in as an applicant.
 */
const TBS = '<to be supplied>';
const label = (en: string): LocalizedText => ({ en, ta: TBS });

const SEEDED: Record<string, AgentStatus> = {
  '+919000000001': 'PENDING_APPROVAL',
  '+919000000002': 'REJECTED',
  '+919000000003': 'SUSPENDED',
  '+919000000004': 'TERMINATED',
  '+919000000005': 'ACTIVE',
};

// The approved share templates, filled in here the way the backend's
// renderShareMessage does (mock only — the portal UI never renders them).
const APPROVED_EN =
  "Hi! I'm {agent_name}. Join Nenjam, a trusted matrimony app, and use my referral code {code} when you sign up to get {discount_percent}% off your first plan.\n\n{link}";
const APPROVED_TA =
  'வணக்கம்! நான் {agent_name}. நம்பகமான திருமண வரன் தேடல் செயலியான "நெஞ்சம்" (Nenjam)-இல் இணையுங்கள். பதிவு செய்யும்போது என் பரிந்துரைக் குறியீடு {code} பயன்படுத்தினால், உங்கள் முதல் திட்டத்தில் {discount_percent}% தள்ளுபடி கிடைக்கும்.\n\n{link}';

function mockRender(template: string, agentName: string, code: string, percent: number) {
  // No web address yet: the {link} line is dropped, with no trailing blank.
  const lines = template.split('\n').filter((l) => !l.includes('{link}'));
  while (lines.length && lines[lines.length - 1].trim() === '') lines.pop();
  return lines
    .join('\n')
    .replace(/\{agent_name\}/g, agentName)
    .replace(/\{code\}/g, code)
    .replace(/\{discount_percent\}/g, String(percent));
}

const CONFIG: AgentConfig = {
  statusLabels: {
    PENDING_APPROVAL: label('Under review'),
    ACTIVE: label('Active'),
    REJECTED: label('Not approved'),
    SUSPENDED: label('Paused'),
    TERMINATED: label('Closed'),
  },
  stageLabels: {
    REGISTERED: label('Registered'),
    PROFILE_COMPLETE: label('Profile complete'),
    PURCHASED: label('Bought a plan'),
  },
  commissionStatusLabels: {
    ON_HOLD: label('On hold'),
    APPROVED: label('Approved'),
    PAID: label('Paid'),
    CANCELLED: label('Cancelled'),
  },
  payoutStatusLabels: {
    CREATED: label('Processing'),
    PAID: label('Paid'),
    CANCELLED: label('Cancelled'),
  },
  shareMessages: [{ id: 'default', text: { en: APPROVED_EN, ta: APPROVED_TA } }],
  settings: {
    holdDays: 14,
    creditWindowDays: 60,
    minPayoutPaise: 50000,
    referredMemberDiscountPercent: 5,
  },
};

const REFERRALS: ReferralView[] = [
  {
    id: 'att-1',
    displayName: 'Priya S.',
    age: 27,
    city: 'Chennai',
    signedUpAt: '2026-10-20',
    stage: 'PROFILE_COMPLETE',
    profileCompletenessPct: 80,
    planName: null,
    purchasedAt: null,
    commissionStatus: null,
    maskedPhone: '+91 98***210',
  },
  {
    id: 'att-2',
    displayName: 'Arun K.',
    age: 30,
    city: 'Madurai',
    signedUpAt: '2026-10-24',
    stage: 'REGISTERED',
    profileCompletenessPct: 35,
    planName: null,
    purchasedAt: null,
    commissionStatus: null,
    maskedPhone: '+91 97***431',
  },
];

const PHONE = /^\+[1-9][0-9]{7,14}$/;
const UPI = /^[a-z0-9._-]{2,256}@[a-z][a-z0-9]{1,63}$/;
const ACCOUNT = /^[0-9]{9,18}$/;
const IFSC = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const PAN = /^[A-Z]{5}[0-9]{4}[A-Z]$/;

export class MockAgentApi implements AgentApi {
  private readonly sessions: SessionStore;
  private challenges = new Map<string, string>();
  private agents = new Map<string, AgentProfile>();
  private seq = 0;

  constructor(sessions: SessionStore) {
    this.sessions = sessions;
    for (const [phone, status] of Object.entries(SEEDED)) {
      this.agents.set(phone, this.profile(phone, 'Ravi Kumar', 'Chennai', 'Tamil Nadu', status));
    }
  }

  async requestOtp(phone: string): Promise<OtpRequestResponse> {
    if (!PHONE.test(phone)) throw validation('phone must be in E.164 format');
    const challengeId = `mock-challenge-${++this.seq}`;
    this.challenges.set(challengeId, phone);
    return { challengeId, expiresInSeconds: 300, resendAfterSeconds: 30 };
  }

  async verifyOtp(challengeId: string, code: string): Promise<Session> {
    const phone = this.challenges.get(challengeId);
    // Contract: an unknown challenge is reported as OTP_INVALID, revealing nothing.
    if (!phone) throw new ApiError(401, 'That code is not right.', { code: 'OTP_INVALID' });
    if (!/^[0-9]{4,8}$/.test(code)) {
      throw new ApiError(401, 'That code is not right.', { code: 'OTP_INVALID' });
    }
    this.challenges.delete(challengeId);
    const agent = this.agents.get(phone);
    if (!agent) {
      return { scope: 'APPLICANT', accessToken: `mock-applicant:${phone}`, expiresInSeconds: 900 };
    }
    return this.agentSession(phone, agent);
  }

  async logout(): Promise<void> {}

  async apply(input: ApplicationInput): Promise<AgentSession> {
    const phone = this.phone();
    const existing = this.agents.get(phone);
    if (existing) {
      // Contract: 409 APPLICATION_EXISTS, with agentStatus saying which.
      throw new ApiError(409, 'An application already exists for this phone.', {
        code: 'APPLICATION_EXISTS',
        agentStatus: existing.status,
      });
    }
    const name = input.name.trim();
    if (name.length < 2 || name.length > 100) throw validation('name must be 2–100 characters');
    if (!input.city.trim() || !input.state.trim()) throw validation('city and state are required');
    if (input.pan !== undefined && !PAN.test(input.pan)) throw validation('pan is not valid');
    const agent = this.profile(phone, name, input.city.trim(), input.state.trim(), 'PENDING_APPROVAL');
    if (input.pan) agent.panLast4 = input.pan.slice(-4);
    this.agents.set(phone, agent);
    return this.agentSession(phone, agent);
  }

  async getMe(): Promise<AgentProfile> {
    const agent = this.agents.get(this.phone());
    if (!agent) throw new ApiError(404, 'No agent record for this phone.', { code: 'AGENT_NOT_FOUND' });
    return { ...agent };
  }

  async getConfig(): Promise<AgentConfig> {
    this.requireAgent();
    return CONFIG;
  }

  async getReferralLinks(): Promise<ReferralLink[]> {
    const agent = this.requireStatus(['ACTIVE', 'SUSPENDED']);
    const code = agent.primaryCode ?? 'NM7K2P9X';
    const percent = CONFIG.settings.referredMemberDiscountPercent;
    return [
      {
        codeId: 'code-1',
        code,
        isPrimary: true,
        link: null,
        qrPayload: null,
        shareMessages: [
          {
            id: 'default',
            text: {
              en: mockRender(APPROVED_EN, agent.name, code, percent),
              ta: mockRender(APPROVED_TA, agent.name, code, percent),
            },
          },
        ],
        shareable: agent.status === 'ACTIVE',
      },
    ];
  }

  async getReferrals(query: PageQuery & { stage?: ReferralStage }): Promise<Page<ReferralView>> {
    this.requireStatus(['ACTIVE', 'SUSPENDED']);
    const items = REFERRALS.filter((r) => !query.stage || r.stage === query.stage);
    return { items, nextCursor: null };
  }

  async getCommissions(_query: PageQuery & { status?: CommissionStatus }): Promise<Page<Commission>> {
    this.requireStatus(['ACTIVE', 'SUSPENDED', 'TERMINATED']);
    // Payments aren't built yet, so there are no commissions.
    return { items: [], nextCursor: null };
  }

  async getBalance(): Promise<Balance> {
    this.requireStatus(['ACTIVE', 'SUSPENDED', 'TERMINATED']);
    return {
      onHoldPaise: 0,
      availablePaise: 0,
      paidPaise: 0,
      minPayoutPaise: CONFIG.settings.minPayoutPaise,
      canRequestPayout: false,
    };
  }

  async getPayouts(_query: PageQuery): Promise<Page<Payout>> {
    this.requireStatus(['ACTIVE', 'SUSPENDED', 'TERMINATED']);
    return { items: [], nextCursor: null };
  }

  async updatePayoutDetails(input: PayoutDetailsInput): Promise<PayoutDetailsSummary> {
    const agent = this.requireStatus(['ACTIVE']);
    let summary: PayoutDetailsSummary;
    if ('upi' in input) {
      if (!UPI.test(input.upi.vpa)) throw validation('upi.vpa is not valid');
      summary = { method: 'UPI', display: `${input.upi.vpa.slice(0, 2)}****@${input.upi.vpa.split('@')[1]}` };
    } else {
      const { accountHolderName, accountNumber, ifsc } = input.bank;
      if (!accountHolderName.trim()) throw validation('bank.accountHolderName is required');
      if (!ACCOUNT.test(accountNumber)) throw validation('bank.accountNumber must be 9–18 digits');
      if (!IFSC.test(ifsc)) throw validation('bank.ifsc is not valid');
      summary = { method: 'BANK', display: `${ifsc.slice(0, 4)} ****${accountNumber.slice(-4)}` };
    }
    agent.payoutDetailsSet = true;
    return summary;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  private phone(): string {
    const token = this.sessions.get()?.session.accessToken ?? '';
    const phone = token.split(':')[1];
    if (!phone) throw new ApiError(401, 'Please sign in.', { code: 'UNAUTHORIZED' });
    return phone;
  }

  private requireAgent(): AgentProfile {
    const agent = this.agents.get(this.phone());
    if (!agent) throw new ApiError(403, 'Not available for applicants.', { code: 'UNAUTHORIZED' });
    return agent;
  }

  private requireStatus(allowed: AgentStatus[]): AgentProfile {
    const agent = this.requireAgent();
    if (!allowed.includes(agent.status)) {
      throw new ApiError(403, 'Not available for your account status.', {
        code: 'AGENT_NOT_ACTIVE',
        agentStatus: agent.status,
      });
    }
    return agent;
  }

  private agentSession(phone: string, agent: AgentProfile): AgentSession {
    return {
      scope: 'AGENT',
      accessToken: `mock-agent:${phone}`,
      refreshToken: `mock-refresh:${phone}:${++this.seq}`,
      expiresInSeconds: 900,
      agent: { ...agent },
    };
  }

  private profile(
    phone: string,
    name: string,
    city: string,
    state: string,
    status: AgentStatus,
  ): AgentProfile {
    const approved = status === 'ACTIVE' || status === 'SUSPENDED' || status === 'TERMINATED';
    return {
      id: `agent-${phone.slice(-4)}`,
      name,
      phoneMasked: `${phone.slice(0, 3)} ${phone.slice(3, 5)}***${phone.slice(-3)}`,
      city,
      state,
      status,
      statusLabel: CONFIG.statusLabels[status] ?? label(status),
      rejectionReason: status === 'REJECTED' ? 'Mock: details could not be verified.' : null,
      approvedAt: approved ? '2026-10-01' : null,
      panLast4: null,
      payoutDetailsSet: false,
      primaryCode: approved ? 'NM7K2P9X' : null,
    };
  }
}

function validation(message: string) {
  return new ApiError(400, message, { code: 'VALIDATION_FAILED' });
}
