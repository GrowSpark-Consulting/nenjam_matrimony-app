/**
 * Shared setup for the commission, approval and payout service specs: fakes
 * for every port, the services wired to them, and builders for agents,
 * attributions, policy versions and payment events. Tests only.
 */
import type { PaymentRefunded, PaymentSucceeded } from '@app/common';
import { AgentCommissionApprovalService } from '../commission/agent-commission-approval.service';
import { AgentCommissionEventsService } from '../commission/agent-commission-events.service';
import { AgentPayoutService } from '../payout/agent-payout.service';
import type { AgentStatus } from '../agent/agent-status';
import type {
  AgentPaymentSourcePort,
  AgentMemberProfilePort,
} from '../ports/agent-money-ports';
import type {
  CommissionPolicyVersionRecord,
  CommissionRecord,
} from '../ports/agent-commission-ports';
import type { AgentRecord } from '../ports/agent-data-ports';
import {
  FakeAgentLedgerRepository,
  FakeAgentPayoutRepository,
  FakeCommissionPolicyRepository,
  FakeCommissionRepository,
} from './fake-agent-commission-repositories';
import { FakeAgentClock } from './fake-agent-infra';
import { FakeAgentAudit, FakeAgentSettings } from './fake-agent-platform';
import {
  FakeAgentPayoutDetailsRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
} from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

export const T0 = new Date('2026-10-29T09:00:00.000Z');
export const DAY = 86_400_000;
export const HOUR = 3_600_000;

export class FakePaymentSources implements AgentPaymentSourcePort {
  readonly used = new Set<string>();
  calls = 0;

  wasUsedByAnotherMember(input: {
    paymentSourceHash: string;
  }): Promise<boolean> {
    this.calls += 1;
    return Promise.resolve(this.used.has(input.paymentSourceHash));
  }
}

export class FakeMemberProfiles implements AgentMemberProfilePort {
  readonly verified = new Set<string>();
  calls = 0;

  isProfileVerified(memberId: string): Promise<boolean> {
    this.calls += 1;
    return Promise.resolve(this.verified.has(memberId));
  }
}

/** The settings the commission services read, with the decided values. */
export const DEFAULT_SETTINGS: Record<string, unknown> = {
  'commission.auto_approve': true,
  'commission.require_verified_profile': false,
  'commission.base': 'AMOUNT_PAID_EXCLUDING_GST',
  'payout.minimum_amount_paise': 50_000,
  'agent.payout_details_wait_hours': 72,
  'payout.tax_withholding': null,
};

export function makeCommissionHarness(
  settings: Record<string, unknown> = DEFAULT_SETTINGS,
) {
  const clock = new FakeAgentClock(T0);
  const uow = new FakeAgentUnitOfWork();
  const agents = new FakeAgentRepository();
  const attributions = new FakeReferralAttributionRepository();
  const policy = new FakeCommissionPolicyRepository();
  const commissions = new FakeCommissionRepository();
  const ledger = new FakeAgentLedgerRepository(() => clock.now());
  const payouts = new FakeAgentPayoutRepository();
  const payoutDetails = new FakeAgentPayoutDetailsRepository();
  const settingsPort = new FakeAgentSettings(settings);
  const audit = new FakeAgentAudit();
  const paymentSources = new FakePaymentSources();
  const profiles = new FakeMemberProfiles();

  let ids = 0;
  const newId = () => `id-${++ids}`;

  const events = new AgentCommissionEventsService(
    {
      uow,
      agents,
      attributions,
      policy,
      commissions,
      ledger,
      settings: settingsPort,
      paymentSources,
      audit,
      clock,
    },
    { newId },
  );
  const approval = new AgentCommissionApprovalService({
    uow,
    agents,
    attributions,
    commissions,
    ledger,
    settings: settingsPort,
    audit,
    clock,
    profiles,
  });
  const payoutService = new AgentPayoutService(
    {
      uow,
      agents,
      payoutDetails,
      commissions,
      ledger,
      payouts,
      settings: settingsPort,
      audit,
      clock,
    },
    { newId },
  );

  const seedPolicy = (
    o: Partial<CommissionPolicyVersionRecord> = {},
  ): CommissionPolicyVersionRecord => {
    const version: CommissionPolicyVersionRecord = {
      id: 'pol-1',
      version: 1,
      calcType: 'PERCENTAGE',
      value: 1000,
      holdDays: 14,
      effectiveFrom: new Date('2026-01-01T00:00:00.000Z'),
      ...o,
    };
    policy.add(version);
    return version;
  };

  const seedAgent = async (
    status: AgentStatus = 'ACTIVE',
    o: Partial<AgentRecord> = {},
  ): Promise<AgentRecord> => {
    const id = o.id ?? 'agent-1';
    const created = await agents.create({
      id,
      phoneHash: o.phoneHash ?? `v1:agent-hash-${id}`,
      phoneE164: o.phoneE164 ?? '+919000000001',
      name: o.name ?? 'Ravi',
      city: 'Madurai',
      state: 'Tamil Nadu',
      panLast4: null,
      panSealed: null,
      createdAt: T0,
    });
    return agents.update(created.id, { status, ...o });
  };

  /** A referral of `memberId` to an agent, inside a 60 day window from `T0`. */
  const seedAttribution = (
    n: number,
    o: {
      agentId?: string;
      memberId?: string | null;
      status?: 'ACTIVE' | 'CONVERTED' | 'EXPIRED' | 'REJECTED';
      windowEndsAt?: Date;
      memberPhoneHash?: string;
    } = {},
  ) =>
    attributions.create({
      id: `attr-${n}`,
      memberId: o.memberId === undefined ? `member-${n}` : o.memberId,
      agentId: o.agentId ?? 'agent-1',
      codeId: null,
      source: 'CODE_AT_SIGNUP',
      memberPhoneHash: o.memberPhoneHash ?? `v1:member-hash-${n}`,
      attributedAt: T0,
      status: o.status ?? 'ACTIVE',
      windowEndsAt: o.windowEndsAt ?? new Date(T0.getTime() + 60 * DAY),
      needsReview: false,
    });

  /** GST-inclusive 9500 paid at 18%: the payment stored 8051 + 1449. */
  const paymentSucceeded = (
    n: number,
    o: Partial<PaymentSucceeded> = {},
  ): PaymentSucceeded => ({
    type: 'payment.succeeded',
    version: 1,
    paymentId: `pay-${n}`,
    memberId: `member-${n}`,
    subscriptionId: `sub-${n}`,
    planDurationId: 'plan-gold-12',
    paidBy: 'MEMBER',
    isFirstPaidPlan: true,
    listAmountPaise: 10_000,
    discountPaise: 500,
    discountSource: 'REFERRAL_FIRST_PLAN',
    heldReferralCodeId: null,
    amountPaidPaise: 9_500,
    taxRateBps: 1_800,
    taxPaise: 1_449,
    taxableAmountPaise: 8_051,
    currency: 'INR',
    paymentSourceHash: null,
    paidAt: new Date(T0.getTime() + HOUR).toISOString(),
    ...o,
  });

  const paymentRefunded = (
    n: number,
    refundN: number,
    o: Partial<PaymentRefunded> = {},
  ): PaymentRefunded => ({
    type: 'payment.refunded',
    version: 1,
    refundId: `rf-${refundN}`,
    paymentId: `pay-${n}`,
    memberId: `member-${n}`,
    refundedPaise: 9_500,
    refundedTaxPaise: 1_449,
    totalRefundedPaise: 9_500,
    fullyRefunded: true,
    refundedAt: new Date(T0.getTime() + 2 * HOUR).toISOString(),
    ...o,
  });

  /** Policy + agent + attribution + the commission for payment `n`. */
  const seedCommission = async (
    n = 1,
    o: Partial<CommissionRecord> = {},
  ): Promise<CommissionRecord> => {
    if (!(await agents.findById('agent-1'))) await seedAgent();
    if ((await policy.findActive(T0)) === null) seedPolicy();
    if ((await attributions.findByMemberId('member-' + n)) === null) {
      await seedAttribution(n);
    }
    await events.onPaymentSucceeded(paymentSucceeded(n));
    const created = await commissions.findByPaymentId(`pay-${n}`);
    if (!created) throw new Error('commission was not created');
    return Object.keys(o).length > 0
      ? commissions.update(created.id, o)
      : created;
  };

  return {
    clock,
    uow,
    agents,
    attributions,
    policy,
    commissions,
    ledger,
    payouts,
    payoutDetails,
    settings: settingsPort,
    audit,
    paymentSources,
    profiles,
    events,
    approval,
    payoutService,
    seedPolicy,
    seedAgent,
    seedAttribution,
    seedCommission,
    paymentSucceeded,
    paymentRefunded,
  };
}

export type CommissionHarness = ReturnType<typeof makeCommissionHarness>;
