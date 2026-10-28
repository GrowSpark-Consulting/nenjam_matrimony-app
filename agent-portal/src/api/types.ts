// Types for the agent API — docs/agent-program/agent-api.openapi.yaml.
//
// Sign-in uses a challenge: `POST /agent/auth/otp/request` returns a
// `challengeId`, and `POST /agent/auth/otp/verify` takes `{ challengeId, code }`
// (the phone comes from the verified challenge).
//
// Money is always integer paise. Calendar dates are `YYYY-MM-DD` (Indian time).

export type AgentStatus =
  | 'PENDING_APPROVAL'
  | 'ACTIVE'
  | 'REJECTED'
  | 'SUSPENDED'
  | 'TERMINATED';

export type ReferralStage = 'REGISTERED' | 'PROFILE_COMPLETE' | 'PURCHASED';

export type CommissionStatus = 'ON_HOLD' | 'APPROVED' | 'PAID' | 'CANCELLED';

export type PayoutStatus = 'CREATED' | 'PAID' | 'CANCELLED';

export interface LocalizedText {
  en: string;
  ta: string;
}

export interface OtpRequestResponse {
  challengeId: string;
  expiresInSeconds: number;
  resendAfterSeconds: number;
}

export interface AgentProfile {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: AgentStatus;
  statusLabel: LocalizedText;
  rejectionReason: string | null;
  approvedAt: string | null;
  panLast4: string | null;
  payoutDetailsSet: boolean;
  primaryCode: string | null;
}

export interface AgentSession {
  scope: 'AGENT';
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  agent: AgentProfile;
}

/** No refresh token: when it expires, the applicant verifies by OTP again. */
export interface ApplicantSession {
  scope: 'APPLICANT';
  accessToken: string;
  expiresInSeconds: number;
}

export type Session = AgentSession | ApplicantSession;

export interface ApplicationInput {
  name: string;
  city: string;
  state: string;
  pan?: string;
}

export interface AgentConfig {
  statusLabels: Partial<Record<AgentStatus, LocalizedText>>;
  stageLabels: Partial<Record<ReferralStage, LocalizedText>>;
  commissionStatusLabels: Partial<Record<CommissionStatus, LocalizedText>>;
  payoutStatusLabels: Partial<Record<PayoutStatus, LocalizedText>>;
  /** Templates. The portal never renders them — see ReferralLink. */
  shareMessages: { id: string; text: LocalizedText }[];
  settings: {
    holdDays: number;
    creditWindowDays: number;
    minPayoutPaise: number;
    referredMemberDiscountPercent: number;
  };
}

export interface ShareMessage {
  id: string;
  /** Finished text from the backend. Shown and shared exactly as received. */
  text: LocalizedText;
}

export interface ReferralLink {
  codeId: string;
  code: string;
  isPrimary: boolean;
  /** Null until the public web address is decided. */
  link: string | null;
  /** Null whenever `link` is null. */
  qrPayload: string | null;
  shareMessages: ShareMessage[];
  /** False while the agent is paused. */
  shareable: boolean;
}

/** The ONLY fields an agent sees about a referred member (privacy rule). */
export interface ReferralView {
  id: string;
  displayName: string;
  age: number;
  city: string;
  signedUpAt: string;
  stage: ReferralStage;
  profileCompletenessPct: number;
  planName: string | null;
  purchasedAt: string | null;
  commissionStatus: CommissionStatus | null;
  maskedPhone: string;
}

export interface Commission {
  id: string;
  referralId: string;
  referralDisplayName: string;
  planName: string;
  basePaise: number;
  amountPaise: number;
  rate: { calcType: 'PERCENTAGE'; value: number };
  status: CommissionStatus;
  earnedOn: string;
  holdEndsOn: string | null;
  approvedOn: string | null;
  paidOn: string | null;
}

export interface Balance {
  onHoldPaise: number;
  availablePaise: number;
  paidPaise: number;
  minPayoutPaise: number;
  /** Informational only: agents cannot create payouts. */
  canRequestPayout: boolean;
}

export interface Payout {
  id: string;
  amountPaise: number;
  status: PayoutStatus;
  reference: string | null;
  createdOn: string;
  paidOn: string | null;
  commissionCount: number;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export type PayoutDetailsInput =
  | { upi: { vpa: string } }
  | { bank: { accountHolderName: string; accountNumber: string; ifsc: string } };

export interface PayoutDetailsSummary {
  method: 'UPI' | 'BANK';
  display: string;
}
