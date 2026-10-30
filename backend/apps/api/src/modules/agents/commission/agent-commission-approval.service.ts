/**
 * Moves commissions to APPROVED: the daily approval job and the shared
 * "approve one commission" step the admin service reuses.
 *
 * `runDailyApproval(now, batchSize)` is a plain callable function. Nothing
 * schedules it (Render has no worker or scheduler); a cron, a queue or an
 * admin button can call it later. Each commission is handled in its own
 * transaction, so one failure never blocks the rest.
 *
 * What moves is decided by `decideCommissionTransition` (pure). Approving
 * credits the agent's ledger once (`credit:<commissionId>` is the idempotency
 * key) in the same transaction as the status change, so a replay or a lost
 * race can never credit twice.
 */
import { AgentConfigError } from '../config/agent-config.service';
import { AgentMoneyError } from '../errors/agent-money-error';
import type {
  AgentLedgerRepository,
  CommissionRecord,
  CommissionRepository,
  CommissionStatusValue,
} from '../ports/agent-commission-ports';
import type {
  AgentRepository,
  ReferralAttributionRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentMemberProfilePort } from '../ports/agent-money-ports';
import type {
  AgentAuditPort,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import {
  COMMISSION_AUTO_APPROVE_KEY,
  COMMISSION_BASE_KEY,
  COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
  parseAgentProgramSettings,
  type CommissionBase,
} from '../settings/agent-program-settings';
import { calculateCommission } from './calculate-commission';
import {
  decideCommissionTransition,
  type OpenCommissionStatus,
} from './decide-commission-transition';
import { buildCreditEntry } from './ledger-entries';
import { isProfileEligibleForCommission } from './profile-eligibility';
import { reduceForRefund } from './plan-refund-effect';

export interface AgentCommissionApprovalDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  attributions: ReferralAttributionRepository;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  settings: AgentSettingsPort;
  audit: AgentAuditPort;
  clock: AgentClock;
  profiles: AgentMemberProfilePort;
}

export interface DailyApprovalSummary {
  examined: number;
  approved: number;
  /** Moved to another open status (for example FROZEN or AWAITING_VERIFICATION). */
  moved: number;
  unchanged: number;
  /** Commissions whose transaction failed; the rest were still processed. */
  failedIds: string[];
}

/** The commission base amount for a commission, from the amounts stored on it. */
export function baseFor(
  base: CommissionBase | null | undefined,
  commission: Pick<CommissionRecord, 'amountPaidPaise' | 'taxableAmountPaise'>,
): number | null {
  if (base === 'AMOUNT_PAID_EXCLUDING_GST')
    return commission.taxableAmountPaise;
  if (base === 'AMOUNT_PAID') return commission.amountPaidPaise;
  return null;
}

export class AgentCommissionApprovalService {
  constructor(private readonly deps: AgentCommissionApprovalDeps) {}

  async runDailyApproval(
    now: Date,
    batchSize: number,
  ): Promise<DailyApprovalSummary> {
    if (!Number.isSafeInteger(batchSize) || batchSize < 1) {
      throw new RangeError('batchSize must be a positive integer.');
    }
    if (Number.isNaN(now.getTime())) {
      throw new RangeError('now must be a valid date.');
    }
    const raw = await this.deps.settings.getMany([
      COMMISSION_AUTO_APPROVE_KEY,
      COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
      COMMISSION_BASE_KEY,
    ]);
    const { settings } = parseAgentProgramSettings(raw);
    if (settings.commissionAutoApprove === undefined) {
      throw new AgentConfigError([COMMISSION_AUTO_APPROVE_KEY]);
    }
    const run = {
      autoApprove: settings.commissionAutoApprove,
      requireVerifiedProfile: raw[COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY],
      base: settings.commissionBase ?? null,
    };

    const summary: DailyApprovalSummary = {
      examined: 0,
      approved: 0,
      moved: 0,
      unchanged: 0,
      failedIds: [],
    };
    let afterId: string | undefined;
    for (;;) {
      const page = await this.deps.commissions.listOpen({
        limit: batchSize,
        afterId,
      });
      for (const open of page) {
        summary.examined += 1;
        try {
          const result = await this.deps.uow.run((tx) =>
            this.processOne(open.id, now, run, tx),
          );
          summary[result] += 1;
        } catch {
          summary.failedIds.push(open.id);
        }
      }
      if (page.length < batchSize) return summary;
      afterId = page[page.length - 1].id;
    }
  }

  private async processOne(
    id: string,
    now: Date,
    run: {
      autoApprove: boolean;
      requireVerifiedProfile: unknown;
      base: CommissionBase | null;
    },
    tx: AgentTx,
  ): Promise<'approved' | 'moved' | 'unchanged'> {
    const { commissions } = this.deps;
    let commission = await commissions.findById(id, tx);
    if (commission === null) return 'unchanged';
    const from = commission.status;
    if (!isOpen(from)) return 'unchanged';

    // The base was not configured when the payment came in: now that it is,
    // fill the amount from the amounts stored on the commission (the tax is
    // never recomputed).
    if (commission.amountPaise === null && run.base !== null) {
      const basePaise = baseFor(run.base, commission);
      if (basePaise !== null) {
        const fullAmount = calculateCommission(
          { calcType: commission.calcType, value: commission.ruleValue },
          basePaise,
          commission.amountPaidPaise,
        );
        // A partial refund that came in before the base was set was recorded
        // as a running total: apply the same refunded fraction now, so a
        // later base does not undo the refund.
        const refunded = commission.refundedPaise > 0;
        const amountPaise = refunded
          ? reduceForRefund(
              fullAmount,
              commission.amountPaidPaise,
              commission.refundedPaise,
            )
          : fullAmount;
        commission = await commissions.update(
          id,
          {
            basePaise,
            amountPaise,
            ...(refunded && { preRefundAmountPaise: fullAmount }),
          },
          tx,
        );
      }
    }

    const agent = await this.deps.agents.findById(commission.agentId, tx);
    if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');

    const profileEligible = await this.profileEligible(
      commission,
      run.requireVerifiedProfile,
      tx,
    );
    const decision = decideCommissionTransition({
      status: from,
      now,
      holdUntil: commission.holdUntil,
      agentStatus: agent.status,
      autoApprove: run.autoApprove,
      profileEligible,
      commissionBaseConfigured: run.base !== null,
    });

    if (decision.next === 'APPROVED') {
      await this.approve(commission, now, null, decision.reason, tx);
      return 'approved';
    }
    if (decision.next === from) return 'unchanged';
    const moved = await commissions.transition(
      id,
      from,
      { status: decision.next },
      tx,
    );
    if (moved === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
    await this.deps.audit.record(
      {
        actorId: null,
        action: 'COMMISSION_STATUS_CHANGED',
        entity: 'commission',
        entityId: id,
        metadata: { from, to: decision.next, reason: decision.reason },
      },
      tx,
    );
    return 'moved';
  }

  /**
   * APPROVED, with the ledger credit, in the caller's transaction. Refuses a
   * commission without an amount. The status change is conditional on the
   * commission still being in the status it was read in, so two approvals
   * racing cannot both credit (the ledger key would stop a second credit
   * anyway). `actorId` is null for the system.
   */
  async approve(
    commission: CommissionRecord,
    at: Date,
    actorId: string | null,
    reason: string,
    tx: AgentTx,
    auditAction = 'COMMISSION_APPROVED',
  ): Promise<CommissionRecord> {
    if (commission.amountPaise === null) {
      throw new AgentMoneyError('COMMISSION_AMOUNT_NOT_SET');
    }
    const moved = await this.deps.commissions.transition(
      commission.id,
      commission.status,
      {
        status: 'APPROVED',
        approvedAt: at,
        creditedPaise: commission.amountPaise,
      },
      tx,
    );
    if (moved === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
    await this.deps.audit.record(
      {
        actorId,
        action: auditAction,
        entity: 'commission',
        entityId: commission.id,
        reason: actorId === null ? undefined : reason,
        metadata: { from: commission.status, reason },
      },
      tx,
    );
    if (commission.amountPaise > 0) {
      await this.deps.ledger.append(
        buildCreditEntry({
          agentId: commission.agentId,
          commissionId: commission.id,
          amountPaise: commission.amountPaise,
          calcType: commission.calcType,
          value: commission.ruleValue,
          ruleSnapshot: {
            calcType: commission.calcType,
            value: commission.ruleValue,
            policyVersionId: commission.policyVersionId,
          },
        }),
        tx,
      );
    }
    return moved;
  }

  private async profileEligible(
    commission: CommissionRecord,
    requireVerifiedProfile: unknown,
    tx: AgentTx,
  ): Promise<boolean> {
    // The member is only looked up when verification is required.
    let profileVerified: boolean | null = null;
    if (requireVerifiedProfile === true) {
      const attribution = await this.deps.attributions.findByIdForAgent(
        commission.attributionId,
        commission.agentId,
        tx,
      );
      profileVerified =
        attribution?.memberId != null
          ? await this.deps.profiles.isProfileVerified(attribution.memberId)
          : false;
    }
    return isProfileEligibleForCommission({
      requireVerifiedProfile,
      profileVerified,
    }).eligible;
  }
}

const OPEN: ReadonlySet<CommissionStatusValue> = new Set([
  'ON_HOLD',
  'AWAITING_VERIFICATION',
  'IN_REVIEW',
  'FROZEN',
  'READY',
]);

function isOpen(status: CommissionStatusValue): status is OpenCommissionStatus {
  return OPEN.has(status);
}
