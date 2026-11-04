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
  /** Way 2 (agent-added clients). Missing = an older server = disabled. */
  clientStatusLabels?: Partial<Record<ClientStatus, LocalizedText>>;
  clients?: { enabled: boolean; draftLimit: number | null; expiryDays: number | null };
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

// ─── Way 2: agent-added clients ───────────────────────────────────────

export type ClientStatus = 'DRAFT' | 'WAITING_FOR_CLIENT' | 'ACCEPTED' | 'REJECTED' | 'EXPIRED';

/** The client's profile: sections of fields, exactly as the API names them. */
export type ClientDetails = Record<string, unknown>;

export interface ClientDraft {
  id: string;
  status: ClientStatus;
  statusLabel: LocalizedText;
  displayName: string;
  phoneMasked: string;
  /** Null once the draft is closed (accepted, declined, expired). */
  details: ClientDetails | null;
  /** The required paths still empty. The only source for "N left" and Submit. */
  missingRequired: string[];
  editable: boolean;
  createdAt: string;
  submittedOn: string | null;
  /** Backend date `YYYY-MM-DD`; shown as received, never calculated here. */
  expiresOn: string | null;
  acceptedOn: string | null;
  referralId: string | null;
}

export interface CreateClientInput {
  phone: string;
  consentConfirmed: true;
  details?: ClientDetails;
}

/** One master-data row (`GET /reference-data/*`, no token). */
export interface RefItem {
  code: string;
  label: string;
}
