/**
 * Handlers for the two payment events (`PaymentSucceeded`, `PaymentRefunded`,
 * the contract in `@app/common` `referral-events.ts`).
 *
 * Both are idempotent, because the events are delivered at least once:
 * - `onPaymentSucceeded` is keyed on `paymentId`: a commission exists at most
 *   once per payment (also once per attribution and per phone hash, enforced
 *   by the database), and a replay answers ALREADY_PROCESSED.
 * - `onPaymentRefunded` is keyed on `refundId`: the ledger reversal entry is
 *   `reversal:<refundId>`, and a refund that was already applied is skipped.
 *   Refunds before approval cancel the commission, which is idempotent by
 *   state (an already cancelled commission is left alone).
 *
 * Amounts come from the event as stored on the payment and are used as they
 * are: the tax is never recomputed. Plan prices are EXCLUSIVE of GST (Raja,
 * 29 Oct): the member pays `taxableAmountPaise + taxPaise` = `amountPaidPaise`,
 * and GST is added on top, never found inside. The commission base follows the
 * `commission.base` setting: AMOUNT_PAID_EXCLUDING_GST uses
 * `taxableAmountPaise`, AMOUNT_PAID uses `amountPaidPaise` (GST included, what
 * the member paid; the cap uses it too), and no setting
 * leaves the amount empty (filled by the daily approval once it is set).
 */
import { randomUUID } from 'node:crypto';
import type { PaymentRefunded, PaymentSucceeded } from '@app/common';
import { AgentMoneyError } from '../errors/agent-money-error';
import type {
  AgentLedgerRepository,
  CommissionPolicyRepository,
  CommissionRecord,
  CommissionRepository,
} from '../ports/agent-commission-ports';
import {
  AgentConflictError,
  type AgentMemberReadPort,
  type AgentRepository,
  type ReferralAttributionRecord,
  type ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentPaymentSourcePort } from '../ports/agent-money-ports';
import type {
  AgentAuditPort,
  AgentIdentifierHasher,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import {
  COMMISSION_BASE_KEY,
  parseAgentProgramSettings,
} from '../settings/agent-program-settings';
import { baseFor } from './agent-commission-approval.service';
import { buildCommissionDraft } from './build-commission-draft';
import { buildReversalEntry } from './ledger-entries';
import { planRefundEffect } from './plan-refund-effect';

export interface AgentCommissionEventsDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  policy: CommissionPolicyRepository;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  settings: AgentSettingsPort;
  paymentSources: AgentPaymentSourcePort;
  /** Read only. Gives the member's phone, to look for a duplicate under every pepper version. */
  members: AgentMemberReadPort;
  hasher: AgentIdentifierHasher;
  audit: AgentAuditPort;
  clock: AgentClock;
}

export type PaymentSucceededOutcome =
  | 'CREATED'
  /** livemode is not true: a Razorpay test payment, nothing credited. */
  | 'TEST_MODE'
  | 'ALREADY_PROCESSED'
  | 'NOT_FIRST_PLAN'
  | 'NO_ATTRIBUTION'
  | 'ATTRIBUTION_NOT_ACTIVE'
  | 'OUTSIDE_CREDIT_WINDOW'
  /** Another version of this phone's hash already has a commission: marked for review, nothing credited. */
  | 'DUPLICATE_PHONE_REVIEW';

export interface PaymentSucceededResult {
  outcome: PaymentSucceededOutcome;
  commissionId?: string;
}

export type PaymentRefundedOutcome =
  | 'REVERSED'
  | 'REDUCED'
  /** livemode is not true: nothing to change. */
  | 'TEST_MODE'
  | 'CANCELLED'
  | 'ALREADY_PROCESSED'
  | 'NO_COMMISSION'
  | 'NOTHING_TO_REVERSE';

export interface PaymentRefundedResult {
  outcome: PaymentRefundedOutcome;
  commissionId?: string;
  reversalPaise?: number;
  /** With REDUCED: the new amount (null while the amount is still unknown). */
  reducedAmountPaise?: number | null;
}

export class AgentCommissionPolicyMissingError extends Error {
  constructor() {
    super('No commission policy version is in effect.');
    this.name = 'AgentCommissionPolicyMissingError';
  }
}

export class AgentCommissionEventsService {
  private readonly newId: () => string;

  constructor(
    private readonly deps: AgentCommissionEventsDeps,
    options: { newId?: () => string } = {},
  ) {
    this.newId = options.newId ?? randomUUID;
  }

  async onPaymentSucceeded(
    event: PaymentSucceeded,
  ): Promise<PaymentSucceededResult> {
    const paidAt = checkSucceeded(event);
    // A Razorpay TEST payment never earns a real commission (contract:
    // livemode). Anything but an explicit true is treated as test: money
    // fails closed.
    if (event.livemode !== true) return { outcome: 'TEST_MODE' };
    // Only a member's first paid plan earns a commission.
    if (!event.isFirstPaidPlan) return { outcome: 'NOT_FIRST_PLAN' };

    const raw = await this.deps.settings.getMany([COMMISSION_BASE_KEY]);
    const base = parseAgentProgramSettings(raw).settings.commissionBase ?? null;

    try {
      return await this.deps.uow.run(async (tx) => {
        const { commissions } = this.deps;
        const existing = await commissions.findByPaymentId(event.paymentId, tx);
        if (existing) {
          return { outcome: 'ALREADY_PROCESSED', commissionId: existing.id };
        }

        const attribution = await this.deps.attributions.findByMemberId(
          event.memberId,
          tx,
        );
        if (attribution === null) return { outcome: 'NO_ATTRIBUTION' };
        if (attribution.status !== 'ACTIVE') {
          return { outcome: 'ATTRIBUTION_NOT_ACTIVE' };
        }
        // PENDING DECISION (Raja): a purchase after the credit window ends
        // earns nothing. This is the only place that rule lives.
        if (paidAt.getTime() > attribution.windowEndsAt.getTime()) {
          return { outcome: 'OUTSIDE_CREDIT_WINDOW' };
        }

        // The unique indexes only see two hashes made with the SAME pepper
        // version. During a rotation the same phone can exist under another
        // version, so look at every active version before inserting. If any
        // already has a commission (or an attribution that earned one), never
        // credit twice: mark this referral for review and stop.
        if (await this.phoneAlreadyEarned(event, attribution, tx)) {
          if (!attribution.needsReview) {
            await this.deps.attributions.correct(
              attribution.id,
              attribution.status,
              { needsReview: true },
              tx,
            );
            await this.deps.audit.record(
              {
                actorId: null,
                action: 'COMMISSION_BLOCKED_DUPLICATE_PHONE',
                entity: 'ReferralAttribution',
                entityId: attribution.id,
                metadata: { paymentId: event.paymentId },
              },
              tx,
            );
          }
          return { outcome: 'DUPLICATE_PHONE_REVIEW' };
        }

        const agent = await this.deps.agents.findById(attribution.agentId, tx);
        if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
        const policy = await this.deps.policy.findForAgent(
          agent.id,
          paidAt,
          tx,
        );
        if (policy === null) throw new AgentCommissionPolicyMissingError();

        const paymentSourceReused =
          event.paymentSourceHash !== null &&
          (await this.deps.paymentSources.wasUsedByAnotherMember({
            paymentSourceHash: event.paymentSourceHash,
            memberId: event.memberId,
            excludePaymentId: event.paymentId,
          }));
        const basePaise = baseFor(base, {
          amountPaidPaise: event.amountPaidPaise,
          taxableAmountPaise: event.taxableAmountPaise,
        });
        const draft = buildCommissionDraft({
          rule: { calcType: policy.calcType, value: policy.value },
          holdDays: policy.holdDays,
          now: paidAt,
          amountPaidPaise: event.amountPaidPaise,
          basePaise,
          paidBy: event.paidBy,
          paymentSourceReused,
          memberPhoneMatchesAgent:
            attribution.memberPhoneHash === agent.phoneHash,
        });

        const created = await commissions.create(
          {
            id: this.newId(),
            agentId: agent.id,
            attributionId: attribution.id,
            paymentId: event.paymentId,
            // The attribution's STORED hash, copied as it is: never
            // re-hashed here, so a rotation cannot give one member two hashes.
            phoneHash: attribution.memberPhoneHash,
            policyVersionId: policy.id,
            status: draft.status,
            calcType: draft.calcType,
            ruleValue: draft.value,
            basePaise,
            amountPaise: draft.amountPaise,
            amountPaidPaise: event.amountPaidPaise,
            taxableAmountPaise: event.taxableAmountPaise,
            refundedPaise: 0,
            preRefundAmountPaise: null,
            creditedPaise: 0,
            reversedPaise: 0,
            holdUntil: draft.holdUntil,
            reviewReasons: draft.reasons,
            approvedAt: null,
            paidAt: null,
            cancelledAt: null,
            payoutId: null,
            createdAt: this.deps.clock.now(),
          },
          tx,
        );
        await this.deps.audit.record(
          {
            actorId: null,
            action: 'COMMISSION_CREATED',
            entity: 'commission',
            entityId: created.id,
            metadata: {
              paymentId: event.paymentId,
              status: created.status,
              reasons: draft.reasons,
            },
          },
          tx,
        );
        return { outcome: 'CREATED', commissionId: created.id };
      });
    } catch (error) {
      // The same payment handled twice at once: the database kept the first.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_COMMISSION'
      ) {
        const existing = await this.deps.commissions.findByPaymentId(
          event.paymentId,
        );
        if (existing) {
          return { outcome: 'ALREADY_PROCESSED', commissionId: existing.id };
        }
        // Another payment of the same attribution or phone: nothing more to do.
        return { outcome: 'ALREADY_PROCESSED' };
      }
      throw error;
    }
  }

  async onPaymentRefunded(
    event: PaymentRefunded,
  ): Promise<PaymentRefundedResult> {
    const refundedAt = checkRefunded(event);
    // A test payment never had a commission, so its refund changes nothing.
    if (event.livemode !== true) return { outcome: 'TEST_MODE' };
    return this.deps.uow.run(async (tx) => {
      const { commissions, ledger } = this.deps;
      const commission = await commissions.findByPaymentId(event.paymentId, tx);
      if (commission === null) return { outcome: 'NO_COMMISSION' };

      // This refund was already applied.
      const reversalKey = `reversal:${event.refundId}`;
      if ((await ledger.findByKey(reversalKey, tx)) !== null) {
        return { outcome: 'ALREADY_PROCESSED', commissionId: commission.id };
      }
      if (commission.amountPaidPaise <= 0) {
        return { outcome: 'NOTHING_TO_REVERSE', commissionId: commission.id };
      }

      const plan = planRefundEffect({
        commissionStatus: commission.status,
        creditedPaise: commission.creditedPaise,
        alreadyReversedPaise: commission.reversedPaise,
        amountPaidPaise: commission.amountPaidPaise,
        refundedTotalPaise: event.totalRefundedPaise,
        isFullRefund: event.fullyRefunded,
        payoutStatus: commission.status === 'PAID' ? 'PAID' : 'NONE',
        // Before approval: the amount before any refund reduced it, and the
        // running total already applied. After approval: only set when a
        // refund reduced the commission before it was approved.
        originalAmountPaise:
          commission.preRefundAmountPaise ??
          (isOpen(commission.status) ? commission.amountPaise : null),
        alreadyRefundedPaise: commission.refundedPaise,
      });

      if (plan.commissionNext === 'UNCHANGED' && plan.reversalPaise === 0) {
        return { outcome: 'NOTHING_TO_REVERSE', commissionId: commission.id };
      }

      // A PARTIAL refund before approval REDUCES the commission in
      // proportion (DECIDED, Ishu 29 Oct). Nothing was credited, so the ledger
      // is not touched; the status, rule snapshot and review reasons stay.
      // The running total makes a replayed refund a no-op (handled above, by
      // the plan returning UNCHANGED).
      if (plan.commissionNext === 'REDUCED') {
        const reduced = await commissions.transition(
          commission.id,
          commission.status,
          {
            refundedPaise: plan.refundedPaise,
            ...(plan.reducedAmountPaise !== null &&
              plan.reducedAmountPaise !== undefined && {
                amountPaise: plan.reducedAmountPaise,
                preRefundAmountPaise:
                  commission.preRefundAmountPaise ?? commission.amountPaise,
              }),
          },
          tx,
        );
        if (reduced === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
        await this.audit(
          commission,
          event,
          'COMMISSION_REDUCED_BY_REFUND',
          0,
          tx,
        );
        return {
          outcome: 'REDUCED',
          commissionId: commission.id,
          reducedAmountPaise: plan.reducedAmountPaise ?? null,
        };
      }

      if (plan.commissionNext === 'CANCELLED') {
        const cancelled = await commissions.transition(
          commission.id,
          commission.status,
          { status: 'CANCELLED', cancelledAt: refundedAt },
          tx,
        );
        if (cancelled === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
        await this.audit(
          commission,
          event,
          'COMMISSION_CANCELLED_BY_REFUND',
          0,
          tx,
        );
        return { outcome: 'CANCELLED', commissionId: commission.id };
      }

      if (plan.reversalPaise > 0) {
        const { inserted } = await ledger.append(
          buildReversalEntry({
            agentId: commission.agentId,
            commissionId: commission.id,
            refundId: event.refundId,
            reversalPaise: plan.reversalPaise,
          }),
          tx,
        );
        if (!inserted) {
          return { outcome: 'ALREADY_PROCESSED', commissionId: commission.id };
        }
      }
      const changed = await commissions.transition(
        commission.id,
        commission.status,
        {
          reversedPaise: commission.reversedPaise + plan.reversalPaise,
          ...(plan.commissionNext === 'REVERSED' && { status: 'REVERSED' }),
        },
        tx,
      );
      if (changed === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
      await this.audit(
        commission,
        event,
        'COMMISSION_REVERSED_BY_REFUND',
        plan.reversalPaise,
        tx,
      );
      return {
        outcome: 'REVERSED',
        commissionId: commission.id,
        reversalPaise: plan.reversalPaise,
      };
    });
  }

  /**
   * True when this member's phone, under ANY active pepper version, already
   * has a commission for another payment, or has another attribution that
   * earned one. Without the member's phone only the stored hash can be
   * compared (the unique indexes already cover that one).
   */
  private async phoneAlreadyEarned(
    event: PaymentSucceeded,
    attribution: ReferralAttributionRecord,
    tx: AgentTx,
  ): Promise<boolean> {
    const view = await this.deps.members.getReferralViewFields(
      event.memberId,
      tx,
    );
    const hashes = new Set<string>([attribution.memberPhoneHash]);
    if (view !== null) {
      for (const hash of this.deps.hasher.hashAll('PHONE', view.phoneE164)) {
        hashes.add(hash);
      }
    }
    for (const hash of hashes) {
      const commission = await this.deps.commissions.findByPhoneHash(hash, tx);
      // Another payment of THIS referral is not a duplicate phone: it gets the
      // "already processed" answer from the database's one-per-attribution rule.
      if (
        commission !== null &&
        commission.paymentId !== event.paymentId &&
        commission.attributionId !== attribution.id
      ) {
        return true;
      }
      const other = await this.deps.attributions.findByPhoneHash(hash, tx);
      if (other !== null && other.id !== attribution.id) {
        const earned = await this.deps.commissions.findByAttributionId(
          other.id,
          tx,
        );
        if (earned !== null) return true;
      }
    }
    return false;
  }

  private audit(
    commission: CommissionRecord,
    event: PaymentRefunded,
    action: string,
    reversalPaise: number,
    tx: Parameters<AgentAuditPort['record']>[1],
  ): Promise<void> {
    return this.deps.audit.record(
      {
        actorId: null,
        action,
        entity: 'commission',
        entityId: commission.id,
        metadata: {
          refundId: event.refundId,
          paymentId: event.paymentId,
          reversalPaise,
          fullyRefunded: event.fullyRefunded,
        },
      },
      tx,
    );
  }
}

const OPEN_STATUSES: ReadonlySet<string> = new Set([
  'ON_HOLD',
  'AWAITING_VERIFICATION',
  'IN_REVIEW',
  'FROZEN',
  'READY',
]);
const isOpen = (status: string): boolean => OPEN_STATUSES.has(status);

function assertPaise(name: string, value: unknown): asserts value is number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new RangeError(`${name} must be a non-negative integer (paise).`);
  }
}

function assertId(name: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new RangeError(`${name} must be a non-empty string.`);
  }
}

function checkSucceeded(event: PaymentSucceeded): Date {
  assertId('paymentId', event.paymentId);
  assertId('memberId', event.memberId);
  assertPaise('amountPaidPaise', event.amountPaidPaise);
  assertPaise('taxPaise', event.taxPaise);
  assertPaise('taxableAmountPaise', event.taxableAmountPaise);
  // The member pays the taxable amount plus the GST added on top, so the two
  // parts add up to what was paid. A mismatch is a broken event: refuse it
  // rather than pay on wrong numbers.
  if (event.taxPaise + event.taxableAmountPaise !== event.amountPaidPaise) {
    throw new RangeError(
      'taxPaise and taxableAmountPaise must add up to amountPaidPaise.',
    );
  }
  const paidAt = new Date(event.paidAt);
  if (Number.isNaN(paidAt.getTime())) {
    throw new RangeError('paidAt must be a valid date.');
  }
  return paidAt;
}

function checkRefunded(event: PaymentRefunded): Date {
  assertId('refundId', event.refundId);
  assertId('paymentId', event.paymentId);
  assertPaise('refundedPaise', event.refundedPaise);
  assertPaise('totalRefundedPaise', event.totalRefundedPaise);
  const refundedAt = new Date(event.refundedAt);
  if (Number.isNaN(refundedAt.getTime())) {
    throw new RangeError('refundedAt must be a valid date.');
  }
  return refundedAt;
}
