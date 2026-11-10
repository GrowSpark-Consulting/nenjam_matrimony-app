/**
 * Response shapes of the /admin API (backend/apps/api/src/modules/admin).
 * Dates arrive as ISO strings. Money is integer paise.
 */

export interface AdminMe {
  adminAccountId: string;
  userId: string;
  email: string;
  department: string;
  lastLoginAt: string | null;
  roles: Array<{ key: string; name: string }>;
  permissions: string[];
}

export interface AdminSession {
  sessionToken: string;
  expiresAt: string;
  idleTimeoutSeconds: number;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

// --- Plans -------------------------------------------------------------------

export type FeatureKind = 'boolean' | 'level' | 'cap' | 'quota';

export interface FeatureDescriptor {
  key: string;
  kind: FeatureKind;
  section: string;
  label: string;
  period?: 'DAY' | 'MONTH' | 'SUBSCRIPTION';
  levels?: string[];
  requiredOnEveryPlan?: boolean;
}

export interface LimitValue {
  limit: number | null;
  perMonths?: number;
  fairUse?: number;
}

export type EntitlementValue = boolean | string | LimitValue;
export type Entitlements = Record<string, EntitlementValue>;

export interface Duration {
  months: number;
  durationDays: number;
  bonusDays: number;
  priceInPaise: number | null;
  isActive: boolean;
}

export interface CatalogDuration extends Duration {
  id: string;
  currency: string;
  displayOrder: number;
}

export interface PlanVersionSummary {
  id: string;
  version: number;
  effectiveFrom: string;
  changeNote: string | null;
  createdById: string | null;
  createdAt: string;
  isCurrent: boolean;
  isScheduled: boolean;
}

export interface PlanRow {
  code: string;
  name: string;
  description: string | null;
  tier: number;
  displayOrder: number;
  isActive: boolean;
  isFree: boolean;
  activeSubscribers: number;
  currentVersion: {
    id: string;
    version: number;
    effectiveFrom: string;
    entitlements: Entitlements;
    problems: string[];
  } | null;
  versions: PlanVersionSummary[];
  durations: CatalogDuration[];
  openDraft: { id: string; status: DraftStatus } | null;
}

export interface PlansResponse {
  plans: PlanRow[];
  features: FeatureDescriptor[];
}

export type DraftStatus =
  | 'DRAFT'
  | 'SUBMITTED'
  | 'PUBLISHED'
  | 'REJECTED'
  | 'DISCARDED';

export interface DraftReview {
  entitlementProblems: string[];
  durationProblems: string[];
  changedFeatures: string[];
  reductionsVsCurrent: string[];
  durationChanges: Array<{
    months: number;
    before: Duration | null;
    after: Duration;
  }>;
  hasChanges: boolean;
  publishable: boolean;
}

export interface PlanDraft {
  id: string;
  planCode: string;
  planName: string;
  status: DraftStatus;
  changeNote: string;
  entitlements: Entitlements;
  durations: Duration[];
  baseVersion: number | null;
  currentVersion: number | null;
  stale: boolean;
  createdById: string;
  updatedById: string;
  submittedById: string | null;
  submittedAt: string | null;
  decidedById: string | null;
  decidedAt: string | null;
  decisionNote: string | null;
  publishedVersionId: string | null;
  createdAt: string;
  updatedAt: string;
  review: DraftReview;
  publishedVersion?: number | null;
}

// --- Subscriptions -----------------------------------------------------------

export interface MemberSummary {
  userId: string;
  email: string | null;
  phone: string | null;
  name: string | null;
}

export interface SubscriptionRow {
  id: string;
  status: 'ACTIVE' | 'EXPIRED' | 'CANCELLED' | 'PENDING';
  source: 'PURCHASE' | 'ADMIN_GRANT';
  plan: { code: string; name: string };
  months: number | null;
  startDate: string;
  endDate: string;
  priceInPaise: number | null;
  currency: string | null;
  cancelledAt: string | null;
  cancellationReason: string | null;
  createdAt: string;
  member: MemberSummary;
  lastPayment: {
    status: string;
    amountInPaise: number;
    paidAt: string | null;
  } | null;
}

export interface SubscriptionDetail extends SubscriptionRow {
  autoRenew: boolean;
  activatedAt: string | null;
  planVersion: number | null;
  events: Array<{
    id: string;
    type: string;
    fromStatus: string | null;
    toStatus: string | null;
    actorId: string | null;
    metadata: unknown;
    createdAt: string;
  }>;
  payments: Array<{
    id: string;
    razorpayOrderId: string | null;
    razorpayPaymentId: string | null;
    amountInPaise: number;
    currency: string;
    status: string;
    paidAt: string | null;
    failureReason: string | null;
    refundedAmount: number;
    refundedAt: string | null;
    createdAt: string;
  }>;
}

// --- Audit, overview, roles ----------------------------------------------------

export interface AuditRow {
  id: string;
  createdAt: string;
  actorId: string | null;
  actor: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  reason: string | null;
  before: unknown;
  after: unknown;
  metadata: unknown;
  requestId: string | null;
  ipAddress: string | null;
}

export interface Overview {
  generatedAt: string;
  members: { total: number; byStatus: Record<string, number> };
  activeSubscriptions: Array<{ planCode: string; planName: string; count: number }>;
  planDrafts: { open: number; awaitingApproval: number };
  revenueLast30Days: {
    payments: number;
    grossInPaise: number;
    refundedInPaise: number;
  } | null;
}

export interface RolesResponse {
  roles: Array<{
    key: string;
    name: string;
    description: string | null;
    isSystem: boolean;
    permissions: string[];
    admins: Array<{
      email: string;
      active: boolean;
      authenticatorEnrolled: boolean;
      lastLoginAt: string | null;
    }>;
  }>;
  permissions: Array<{ key: string; description: string; isSensitive: boolean }>;
}

/** The agent program (`/admin/agents/*`, owned by the agent-program backend). */
export type AgentStatus = 'PENDING_APPROVAL' | 'ACTIVE' | 'REJECTED' | 'SUSPENDED' | 'TERMINATED';

export interface AgentsSummary {
  byStatus: Record<AgentStatus, number>;
  payoutDetailsAwaitingVerification: number;
  referralsNeedingReview: number;
  /** Null until the commission tables exist. */
  commissionsReady: number | null;
  payoutsCreated: number | null;
}

export interface AgentRow {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: AgentStatus;
  createdAt: string;
  approvedAt: string | null;
  panOnFile: boolean;
  panVerified: boolean;
  payoutDetailsSet: boolean;
  payoutDetailsVerified: boolean;
  primaryCode: string | null;
}

export interface AgentDetail {
  id: string;
  name: string;
  phoneMasked: string;
  city: string;
  state: string;
  status: AgentStatus;
  rejectionReason: string | null;
  approvedAt: string | null;
  createdAt: string;
  updatedAt: string;
  panLast4: string | null;
  panOnFile: boolean;
  panVerifiedAt: string | null;
  payoutDetailsSet: boolean;
  payoutDetails: {
    method: 'UPI' | 'BANK';
    display: string;
    verifiedAt: string | null;
    changedAt: string;
  } | null;
  codes: Array<{ id: string; code: string; isPrimary: boolean; isActive: boolean; createdAt: string }>;
  counts: { referrals: number; byAttributionStatus: Record<string, number>; needsReview: number };
  /** Null until the commission tables exist. */
  commissions: null;
  statusHistory: Array<{
    from: AgentStatus;
    to: AgentStatus;
    at: string;
    actorId: string | null;
    actorType: 'STAFF' | 'MEMBER' | 'AGENT' | 'SYSTEM';
    reason: string | null;
  }>;
}

/** `POST /admin/agents/:id/reveal`: shown once, never stored or cached. */
export interface RevealedValues {
  revealedAt: string;
  pan?: string;
  phone?: string;
  payoutDetails?: {
    upi?: { vpa: string };
    bank?: { accountHolderName: string; accountNumber: string; ifsc: string };
  };
}

export type CommissionStatus =
  | 'ON_HOLD'
  | 'AWAITING_VERIFICATION'
  | 'IN_REVIEW'
  | 'FROZEN'
  | 'READY'
  | 'APPROVED'
  | 'PAID'
  | 'CANCELLED'
  | 'REVERSED';

export interface CommissionRow {
  id: string;
  agentId: string;
  agentName: string;
  agentStatus: AgentStatus;
  referralId: string;
  planName: string;
  /** What the member paid: the cap for an override. */
  paidPaise: number;
  /** Null while commission.base is undecided. */
  basePaise: number | null;
  /** Null while the base is undecided, until set by an override. */
  amountPaise: number | null;
  creditedPaise: number;
  reversedPaise: number;
  rate: { calcType: 'PERCENTAGE'; value: number };
  status: CommissionStatus;
  publicStatus: string;
  earnedOn: string;
  holdEndsOn: string | null;
  approvedOn: string | null;
  paidOn: string | null;
  payoutId: string | null;
}

export type PayoutStatus = 'CREATED' | 'PAID' | 'CANCELLED';

export type PayoutIneligibleReason =
  | 'AGENT_NOT_PAYABLE'
  | 'PAN_NOT_VERIFIED'
  | 'DETAILS_NOT_VERIFIED'
  | 'WAIT_NOT_OVER'
  | 'NOTHING_TO_PAY'
  | 'BELOW_MINIMUM'
  | 'PAYOUT_EXISTS'
  | 'TAX_RULE_UNSUPPORTED'
  | 'LEDGER_BALANCE_TOO_LOW';

export interface PayableAgent {
  agentId: string;
  agentName: string;
  agentCode: string | null;
  agentStatus: AgentStatus;
  period: string;
  /** Approved and unpaid. */
  balancePaise: number;
  commissionCount: number;
  panVerified: boolean;
  payoutDetails: { method: 'UPI' | 'BANK'; display: string; verifiedAt: string | null } | null;
  eligible: boolean;
  reasons: PayoutIneligibleReason[];
  warnings: string[];
}

export interface PayoutRow {
  id: string;
  agentId: string;
  agentName: string;
  agentCode: string | null;
  period: string;
  amountPaise: number;
  taxWithheldPaise: number;
  netPaise: number;
  status: PayoutStatus;
  reference: string | null;
  paidAt: string | null;
  createdAt: string;
  createdBy: string;
  commissionIds: string[];
  warnings: string[];
  cancelReason: string | null;
}

export interface PayoutDetail extends PayoutRow {
  commissions: CommissionRow[];
  /** Present only with payout.execute and a fresh authenticator check. */
  destination?: {
    upi?: { vpa: string };
    bank?: { accountHolderName: string; accountNumber: string; ifsc: string };
  };
}

// --- User Management ---------------------------------------------------------

export interface AdminUserStats {
  totalUsers: number;
  activeUsers: number;
  blockedUsers: number;
  registeredToday: number;
  incompleteProfiles: number;
  premiumMembers: number;
}

export interface AdminUserListItem {
  id: string;
  fullName: string;
  gender: 'MALE' | 'FEMALE' | null;
  age: number | null;
  location: string | null;
  phone: string | null;
  email: string | null;
  membership: string;
  membershipCode: string;
  profileStatus: 'COMPLETE' | 'INCOMPLETE';
  profileCompletePct: number;
  accountStatus:
    | 'ACTIVE'
    | 'BLOCKED'
    | 'SUSPENDED'
    | 'PENDING_VERIFICATION'
    | 'DEACTIVATED'
    | 'BANNED';
  primaryPhotoUrl: string | null;
  photoApproved: boolean;
  registrationDate: string;
}

export interface AdminUserListResponse {
  items: AdminUserListItem[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

export interface AdminUserDetail {
  id: string;
  firebaseUid: string;
  status:
    | 'ACTIVE'
    | 'BLOCKED'
    | 'SUSPENDED'
    | 'PENDING_VERIFICATION'
    | 'DEACTIVATED'
    | 'BANNED';
  role: string;
  trustScore: number;
  createdAt: string;
  updatedAt: string;

  basicInfo: {
    fullName: string | null;
    firstName: string | null;
    lastName: string | null;
    dob: string | null;
    age: number | null;
    gender: 'MALE' | 'FEMALE' | null;
    maritalStatus: string | null;
    religion: string | null;
    caste: string | null;
    subCaste: string | null;
    community: string | null;
    motherTongue: string | null;
    languagesKnown: string[];
    heightCm: number | null;
    weightKg: number | null;
    isProfileComplete: boolean;
    profileCompletePct: number;
    bio: string | null;
    profileCreatedAt: string | null;
    profileUpdatedAt: string | null;
  };

  contactInfo: {
    phone: string | null;
    email: string | null;
    isPhoneMasked: boolean;
    isEmailMasked: boolean;
    currentCity: string | null;
    currentState: string | null;
    country: string | null;
    nativeCity: string | null;
    area: string | null;
    pinCode: string | null;
  };

  careerAndFamily: {
    highestEducation: string | null;
    college: string | null;
    educationDetails: string | null;
    profession: string | null;
    employerName: string | null;
    workIndustry: string | null;
    annualIncomeLakhs: number | null;
    familyType: string | null;
    familyValues: string | null;
    familyStatus: string | null;
    fatherOccupation: string | null;
    motherOccupation: string | null;
    siblings: number;
    siblingDetails: string[];
    dietaryHabits: string | null;
    smokingHabits: string | null;
    drinkingHabits: string | null;
  };

  partnerPreferences: {
    minAge: number | null;
    maxAge: number | null;
    minHeightCm: number | null;
    maxHeightCm: number | null;
    preferredReligions: string[];
    preferredCastes: string[];
    minIncomeLakhs: number | null;
    preferredCities: string[];
    preferredStates: string[];
  } | null;

  astrologyProfile: {
    rasi: string | null;
    nakshatra: string | null;
    dosham: string | null;
    lagnam: string | null;
    gotram: string | null;
    birthDate: string | null;
    birthTime: string | null;
    birthPlace: string | null;
  } | null;

  membership: {
    currentPlan: string;
    currentPlanCode: string;
    subscriptionStatus: string;
    startDate: string | null;
    expiryDate: string | null;
    autoRenew: boolean;
    history: Array<{
      id: string;
      planName: string;
      planCode: string;
      tier: number;
      status: string;
      startDate: string;
      endDate: string;
      autoRenew: boolean;
      createdAt: string;
      payments: Array<{
        id: string;
        amountInr: string | number;
        currency: string;
        status: string;
        paidAt: string | null;
        createdAt: string;
      }>;
    }>;
  };

  photosAndMedia: {
    primaryPhotoUrl: string | null;
    photos: Array<{
      id: string;
      cdnUrl: string;
      isPrimary: boolean;
      order: number;
      isApproved: boolean;
      createdAt: string;
    }>;
    verification: {
      faceVerified: boolean;
      faceVerificationStatus: string;
      kycVerifications: Array<{
        id: string;
        docType: string;
        status: string;
        rejectionReason: string | null;
        createdAt: string;
      }>;
    };
  };

  internalNotes: Array<{
    id: string;
    authorId: string;
    authorName: string | null;
    note: string;
    createdAt: string;
    updatedAt: string;
  }>;

  supportTickets: Array<{
    id: string;
    type: string;
    subject: string;
    status: string;
    adminResponse: string | null;
    createdAt: string;
  }>;

  accountActivity: {
    registrationDate: string;
    lastProfileUpdate: string;
    trustScore: number;
    trustScoreHistory: Array<{
      id: string;
      oldScore: number;
      newScore: number;
      reason: string;
      createdAt: string;
    }>;
    blocksMadeCount: number;
    blocksReceivedCount: number;
    reportsMadeCount: number;
    reportsAgainstCount: number;
  };
}

export interface BlockUserResult {
  success: boolean;
  userId: string;
  previousStatus: string;
  status: 'BLOCKED';
  reason: string;
}

export interface UnblockUserResult {
  success: boolean;
  userId: string;
  previousStatus: 'BLOCKED';
  status: 'ACTIVE';
}

export interface RevealPiiResult {
  userId: string;
  email: string | null;
  phone: string | null;
  location: {
    city: string | null;
    state: string | null;
    country: string | null;
    pinCode: string | null;
  } | null;
}

export interface MemberNoteResult {
  id: string;
  userId: string;
  authorId: string;
  authorName: string | null;
  note: string;
  createdAt: string;
}

