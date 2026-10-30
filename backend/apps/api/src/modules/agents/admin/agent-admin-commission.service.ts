/**
 * Admin operations on commissions: list, approve, cancel, override. Permission
 * first (in the transaction), a reason on every mutation, the audit row in the
 * same transaction, and money moves through the ledger only: a cancel or an
 * override of a commission that was already credited writes an ADJUSTMENT
 * entry (with the reason) instead of editing anything.
 */
import { randomUUID } from 'node:crypto';
import type { AgentCommissionApprovalService } from '../commission/agent-commission-approval.service';
import { buildAdjustmentEntry } from '../commission/ledger-entries';
import { AgentMoneyError } from '../errors/agent-money-error';
import {
  OPEN_COMMISSION_STATUSES,
  type AgentLedgerRepository,
  type CommissionRecord,
  type CommissionRepository,
  type CommissionStatusValue,
} from '../ports/agent-commission-ports';
import type { AgentRepository } from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type {
  AgentAuditPort,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import {
  PERM,
  decodeCursor,
  encodeCursor,
  pageLimit,
  requireId,
  requirePermission,
  requireReason,
  type AdminActor,
} from './agent-admin-support';

export interface AgentAdminCommissionServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  approval: AgentCommissionApprovalService;
  permission: AgentPermissionPort;
  audit: AgentAuditPort;
  clock: AgentClock;
}

export type PublicCommissionStatus =
  'ON_HOLD' | 'APPROVED' | 'PAID' | 'CANCELLED';

export interface AdminCommission {
  id: string;
  agentId: string;
  attributionId: string;
  paymentId: string;
  /** What staff see. */
  status: CommissionStatusValue;
  /** What the agent sees. */
  publicStatus: PublicCommissionStatus;
  calcType: string;
  ruleValue: number;
  basePaise: number | null;
  amountPaise: number | null;
  amountPaidPaise: number;
  creditedPaise: number;
  reversedPaise: number;
  holdUntil: string;
  reviewReasons: string[];
  approvedAt: string | null;
  paidAt: string | null;
  cancelledAt: string | null;
  payoutId: string | null;
  createdAt: string;
}

const PUBLIC_STATUS: Record<CommissionStatusValue, PublicCommissionStatus> = {
  ON_HOLD: 'ON_HOLD',
  AWAITING_VERIFICATION: 'ON_HOLD',
  IN_REVIEW: 'ON_HOLD',
  FROZEN: 'ON_HOLD',
  READY: 'ON_HOLD',
  APPROVED: 'APPROVED',
  PAID: 'PAID',
  CANCELLED: 'CANCELLED',
  REVERSED: 'CANCELLED',
};

export function toAdminCommission(c: CommissionRecord): AdminCommission {
  return {
    id: c.id,
    agentId: c.agentId,
    attributionId: c.attributionId,
    paymentId: c.paymentId,
    status: c.status,
    publicStatus: PUBLIC_STATUS[c.status],
    calcType: c.calcType,
    ruleValue: c.ruleValue,
    basePaise: c.basePaise,
    amountPaise: c.amountPaise,
    amountPaidPaise: c.amountPaidPaise,
    creditedPaise: c.creditedPaise,
    reversedPaise: c.reversedPaise,
    holdUntil: c.holdUntil.toISOString(),
    reviewReasons: [...c.reviewReasons],
    approvedAt: c.approvedAt?.toISOString() ?? null,
    paidAt: c.paidAt?.toISOString() ?? null,
    cancelledAt: c.cancelledAt?.toISOString() ?? null,
    payoutId: c.payoutId,
    createdAt: c.createdAt.toISOString(),
  };
}

export class AgentAdminCommissionService {
  private readonly newId: () => string;

  constructor(
    private readonly deps: AgentAdminCommissionServiceDeps,
    options: { newId?: () => string } = {},
  ) {
    this.newId = options.newId ?? randomUUID;
  }

  async list(
    actor: AdminActor,
    query: {
      status?: CommissionStatusValue;
      agentId?: string;
      cursor?: string;
      limit?: number;
    } = {},
  ): Promise<{ items: AdminCommission[]; nextCursor: string | null }> {
    const limit = pageLimit(query.limit);
    const after = decodeCursor(query.cursor);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.commissionView,
        tx,
      );
      const rows = await this.deps.commissions.listPage(
        { agentId: query.agentId, status: query.status },
        { limit: limit + 1, after },
        tx,
      );
      const page = rows.slice(0, limit);
      const last = page[page.length - 1];
      return {
        items: page.map(toAdminCommission),
        nextCursor:
          rows.length > limit && last
            ? encodeCursor({ at: last.createdAt, id: last.id })
            : null,
      };
    });
  }

  /**
   * READY or IN_REVIEW -> APPROVED, only while the earning agent is ACTIVE and
   * the amount is known. The daily job approves READY ones itself when
   * auto-approve is on; this mostly handles IN_REVIEW.
   */
  async approve(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminCommission> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.commissionApprove,
        tx,
      );
      const commission = await this.mustFind(id, tx);
      if (commission.status !== 'READY' && commission.status !== 'IN_REVIEW') {
        throw new AgentMoneyError('COMMISSION_STATUS_NOT_ALLOWED');
      }
      const agent = await this.deps.agents.findById(commission.agentId, tx);
      if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
      if (agent.status !== 'ACTIVE') {
        throw new AgentMoneyError('AGENT_STATUS_NOT_ALLOWED', {
          agentStatus: agent.status,
        });
      }
      return toAdminCommission(
        await this.deps.approval.approve(
          commission,
          this.deps.clock.now(),
          actor.userId,
          text,
          tx,
          'commission.approve',
        ),
      );
    });
  }

  /**
   * Any open status, or APPROVED while not in a payout -> CANCELLED. Whatever
   * was credited and not yet reversed is taken back with one ADJUSTMENT entry.
   */
  async cancel(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminCommission> {
    requireId('id', id);
    const text = requireReason(reason);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.commissionCancel,
        tx,
      );
      const commission = await this.mustFind(id, tx);
      this.requireChangeable(commission);
      const now = this.deps.clock.now();
      const outstanding = commission.creditedPaise - commission.reversedPaise;
      const cancelled = await this.deps.commissions.transition(
        id,
        commission.status,
        {
          status: 'CANCELLED',
          cancelledAt: now,
          reversedPaise: commission.creditedPaise,
        },
        tx,
      );
      if (cancelled === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'commission.cancel',
          entity: 'Commission',
          entityId: id,
          reason: text,
          before: {
            status: commission.status,
            creditedPaise: commission.creditedPaise,
          },
          after: { status: 'CANCELLED', clawedBackPaise: outstanding },
        },
        tx,
      );
      if (outstanding > 0) {
        await this.deps.ledger.append(
          buildAdjustmentEntry({
            agentId: commission.agentId,
            amountPaise: -outstanding,
            reason: text,
            idempotencyKey: `commission-cancel:${id}`,
          }),
          tx,
        );
      }
      return toAdminCommission(cancelled);
    });
  }

  /**
   * Sets the amount: any open status, or APPROVED while not in a payout. Not
   * above what the member paid. The status does not change. An approved
   * commission's credit is corrected by one ADJUSTMENT entry for the
   * difference.
   */
  async override(
    actor: AdminActor,
    id: string,
    amountPaise: number,
    reason: string,
  ): Promise<AdminCommission> {
    requireId('id', id);
    const text = requireReason(reason);
    if (!Number.isSafeInteger(amountPaise) || amountPaise < 0) {
      throw new AgentMoneyError('VALIDATION_FAILED', {
        fields: ['amountPaise'],
      });
    }
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.commissionOverride,
        tx,
      );
      const commission = await this.mustFind(id, tx);
      this.requireChangeable(commission);
      if (amountPaise > commission.amountPaidPaise) {
        throw new AgentMoneyError('AMOUNT_EXCEEDS_PAID');
      }
      // A refund may already have clawed some of the credit back.
      if (
        commission.status === 'APPROVED' &&
        amountPaise < commission.reversedPaise
      ) {
        throw new AgentMoneyError('VALIDATION_FAILED', {
          fields: ['amountPaise'],
        });
      }
      const credited = commission.status === 'APPROVED';
      const delta = credited ? amountPaise - commission.creditedPaise : 0;
      const updated = await this.deps.commissions.transition(
        id,
        commission.status,
        credited
          ? { amountPaise, creditedPaise: amountPaise }
          : { amountPaise },
        tx,
      );
      if (updated === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
      await this.deps.audit.record(
        {
          actorId: actor.userId,
          action: 'commission.override',
          entity: 'Commission',
          entityId: id,
          reason: text,
          before: { amountPaise: commission.amountPaise },
          after: { amountPaise },
        },
        tx,
      );
      if (delta !== 0) {
        await this.deps.ledger.append(
          buildAdjustmentEntry({
            agentId: commission.agentId,
            amountPaise: delta,
            reason: text,
            idempotencyKey: `commission-override:${id}:${this.newId()}`,
          }),
          tx,
        );
      }
      return toAdminCommission(updated);
    });
  }

  private async mustFind(id: string, tx: AgentTx): Promise<CommissionRecord> {
    const commission = await this.deps.commissions.findById(id, tx);
    if (commission === null) throw new AgentMoneyError('COMMISSION_NOT_FOUND');
    return commission;
  }

  /** Open statuses, or APPROVED while not in a payout. */
  private requireChangeable(commission: CommissionRecord): void {
    if (commission.status === 'APPROVED') {
      if (commission.payoutId !== null) {
        throw new AgentMoneyError('COMMISSION_IN_PAYOUT');
      }
      return;
    }
    if (!OPEN_COMMISSION_STATUSES.includes(commission.status)) {
      throw new AgentMoneyError('COMMISSION_STATUS_NOT_ALLOWED');
    }
  }
}
