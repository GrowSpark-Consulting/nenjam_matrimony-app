/**
 * Admin operations on payouts: list, detail, create, mark paid, cancel.
 *
 * - **The payee** (`agentName`, `agentCode`) is on every payout response: the
 *   payer holds no `agent.view`, so this is how they know who is being paid.
 * - **The destination** (the full UPI id or bank details) is for the person
 *   who pays, and only for them. It is included only when the admin holds
 *   `payout.execute` AND has a fresh step-up; otherwise the field is LEFT OUT,
 *   the answer is still successful, and NO audit row is written. When it is
 *   included, one `payout.destination.disclose` audit row (the payout id and
 *   the method, never the value) is written in the same transaction as the
 *   read, and if that write fails nothing is returned. It never appears in a
 *   list, in `mark-paid` or in `cancel`. A PAN is never part of it.
 * - `create`, `markPaid` and `cancel` need `payout.execute` and a fresh
 *   step-up, and run inside one transaction with the permission check, the
 *   change and the audit rows.
 */
import { AgentMoneyError } from '../errors/agent-money-error';
import {
  AgentConflictError,
  type AgentPayoutDetailsRepository,
  type AgentRepository,
  type ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type {
  AgentPayoutListFilter,
  AgentPayoutRecord,
  AgentPayoutRepository,
  CommissionRecord,
  CommissionRepository,
} from '../ports/agent-commission-ports';
import type {
  AgentAuditPort,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type { AgentSecretSealer } from '../ports/agent-secret-sealer.port';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import type { AgentPayoutService } from '../payout/agent-payout.service';
import {
  PERM,
  decodeCursor,
  encodeCursor,
  pageLimit,
  requireId,
  requirePermission,
  splitPermission,
  type AdminActor,
} from './agent-admin-support';
import {
  toAdminCommission,
  type AdminCommission,
} from './agent-admin-commission.service';

export interface AgentAdminPayoutServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  codes: ReferralCodeRepository;
  payoutDetails: AgentPayoutDetailsRepository;
  commissions: CommissionRepository;
  payouts: AgentPayoutRepository;
  payoutService: AgentPayoutService;
  permission: AgentPermissionPort;
  audit: AgentAuditPort;
  sealer: AgentSecretSealer;
}

/** The agent's payout details in the shape the agent sent: one of `upi` or `bank`. */
export type PayoutDestination = Record<string, unknown>;

export interface AdminPayout {
  id: string;
  agentId: string;
  agentName: string;
  agentCode: string | null;
  period: string;
  amountPaise: number;
  taxWithheldPaise: number;
  netPaise: number;
  status: AgentPayoutRecord['status'];
  reference: string | null;
  paidAt: string | null;
  createdAt: string;
  createdBy: string;
  commissionIds: string[];
  /** Always TAX_RULE_NOT_SET until the CA's rule is implemented. */
  warnings: string[];
  cancelReason: string | null;
}

export interface AdminPayoutDetail extends AdminPayout {
  commissions: AdminCommission[];
  /** Present only for the payer, with a fresh step-up. */
  destination?: PayoutDestination;
}

export interface AdminPayoutWithDestination extends AdminPayout {
  destination: PayoutDestination;
}

const PERIOD = /^\d{4}-(0[1-9]|1[0-2])$/;

/** An opaque cursor over agent ids; a malformed one is VALIDATION_FAILED. */
function decodeAgentCursor(cursor: string | undefined): string | undefined {
  if (!cursor) return undefined;
  const id = Buffer.from(cursor, 'base64url').toString('utf8');
  if (!/^[\w-]{1,64}$/.test(id)) {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['cursor'] });
  }
  return id;
}

/** The contract's PayableAgent. */
export interface AdminPayableAgent {
  agentId: string;
  agentName: string;
  agentCode: string | null;
  agentStatus: string;
  period: string;
  balancePaise: number;
  commissionCount: number;
  panVerified: boolean;
  payoutDetails: {
    method: string;
    display: string;
    verifiedAt: string | null;
    changedAt: string;
  } | null;
  eligible: boolean;
  reasons: string[];
  warnings: string[];
}

export class AgentAdminPayoutService {
  constructor(private readonly deps: AgentAdminPayoutServiceDeps) {}

  /** Masked data only: never a destination. */
  async list(
    actor: AdminActor,
    query: AgentPayoutListFilter & { cursor?: string; limit?: number } = {},
  ): Promise<{ items: AdminPayout[]; nextCursor: string | null }> {
    const limit = pageLimit(query.limit);
    const after = decodeCursor(query.cursor);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, PERM.payoutView, tx);
      const rows = await this.deps.payouts.listPage(
        { agentId: query.agentId, status: query.status, period: query.period },
        { limit: limit + 1, after },
        tx,
      );
      const page = rows.slice(0, limit);
      const last = page[page.length - 1];
      const items: AdminPayout[] = [];
      for (const payout of page) items.push(await this.view(payout, tx));
      return {
        items,
        nextCursor:
          rows.length > limit && last
            ? encodeCursor({ at: last.createdAt, id: last.id })
            : null,
      };
    });
  }

  /**
   * GET /admin/payouts/payable: the agents with approved, unpaid commission,
   * each with its balance for [period] and EVERY reason a payout cannot be
   * created now (the payout service's own judgement). Paged by agent id;
   * "eligible" filters the page, so a page may be shorter than the limit.
   */
  async listPayable(
    actor: AdminActor,
    query: {
      period: string;
      eligible?: boolean;
      cursor?: string;
      limit?: number;
    },
  ): Promise<{ items: AdminPayableAgent[]; nextCursor: string | null }> {
    if (typeof query.period !== 'string' || !PERIOD.test(query.period)) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['period'] });
    }
    const limit = pageLimit(query.limit);
    const afterAgentId = decodeAgentCursor(query.cursor);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, PERM.payoutView, tx);
      // Settings first: a missing one is 503 even when nobody is payable.
      await this.deps.payoutService.payoutSettings();
      const ids = await this.deps.commissions.listAgentIdsWithPayable(
        { afterAgentId, limit: limit + 1 },
        tx,
      );
      const page = ids.slice(0, limit);
      const items: AdminPayableAgent[] = [];
      for (const agentId of page) {
        const a = await this.deps.payoutService.assess(
          agentId,
          query.period,
          tx,
        );
        if (a === null) continue;
        if (query.eligible !== undefined && a.eligible !== query.eligible)
          continue;
        const codes = await this.deps.codes.listByAgent(agentId, tx);
        items.push({
          agentId,
          agentName: a.agent.name,
          agentCode: codes.find((c) => c.isPrimary)?.code ?? null,
          agentStatus: a.agent.status,
          period: query.period,
          balancePaise: a.balancePaise,
          commissionCount: a.commissionCount,
          panVerified: a.agent.panVerifiedAt !== null,
          payoutDetails: a.details
            ? {
                method: a.details.method,
                display: a.details.display,
                verifiedAt: a.details.verifiedAt?.toISOString() ?? null,
                changedAt: a.details.changedAt.toISOString(),
              }
            : null,
          eligible: a.eligible,
          reasons: a.reasons,
          warnings: a.warnings,
        });
      }
      const last = page[page.length - 1];
      return {
        items,
        nextCursor:
          ids.length > limit && last
            ? Buffer.from(last).toString('base64url')
            : null,
      };
    });
  }

  async get(actor: AdminActor, id: string): Promise<AdminPayoutDetail> {
    requireId('id', id);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(this.deps.permission, actor, PERM.payoutView, tx);
      const payout = await this.deps.payouts.findById(id, tx);
      if (payout === null) throw new AgentMoneyError('PAYOUT_NOT_FOUND');
      const commissions = await this.deps.commissions.listByPayout(id, tx);
      const detail: AdminPayoutDetail = {
        ...(await this.view(payout, tx, commissions)),
        commissions: commissions.map(toAdminCommission),
      };
      // The destination: only the payer with a fresh step-up. Anyone else
      // gets the same answer without the field, and no audit row.
      if (await this.mayReadDestination(actor, tx)) {
        const destination = await this.disclose(actor, payout, tx);
        if (destination !== null) detail.destination = destination;
      }
      return detail;
    });
  }

  /**
   * Idempotent by agent and period: a second call returns the payout that
   * exists (`created: false`). The destination is always included (create
   * needs `payout.execute` and a fresh step-up).
   */
  async create(
    actor: AdminActor,
    input: { agentId: string; period: string; reason: string },
  ): Promise<{ payout: AdminPayoutWithDestination; created: boolean }> {
    requireId('agentId', input.agentId);
    const attempt = () =>
      this.deps.uow.run(async (tx) => {
        await requirePermission(
          this.deps.permission,
          actor,
          PERM.payoutExecute,
          tx,
        );
        const { payout, created } = await this.deps.payoutService.create({
          agentId: input.agentId,
          period: input.period,
          actorId: actor.userId,
          context: actor.context,
          reason: input.reason,
          tx,
        });
        return {
          payout: await this.withDestination(actor, payout, tx),
          created,
        };
      });
    try {
      return await attempt();
    } catch (error) {
      // Two creates for one agent and period at once: the database kept the
      // first. This transaction is aborted, so ask again in a new one; the
      // one-payout rule now answers with the payout that won.
      if (
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_PAYOUT'
      ) {
        return attempt();
      }
      throw error;
    }
  }

  async markPaid(
    actor: AdminActor,
    id: string,
    input: { reference: string; paidAt: Date; reason: string },
  ): Promise<AdminPayout> {
    requireId('id', id);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.payoutExecute,
        tx,
      );
      const payout = await this.deps.payoutService.markPaid({
        payoutId: id,
        reference: input.reference,
        paidAt: input.paidAt,
        actorId: actor.userId,
        context: actor.context,
        reason: input.reason,
        tx,
      });
      return this.view(payout, tx);
    });
  }

  async cancel(
    actor: AdminActor,
    id: string,
    reason: string,
  ): Promise<AdminPayout> {
    requireId('id', id);
    return this.deps.uow.run(async (tx) => {
      await requirePermission(
        this.deps.permission,
        actor,
        PERM.payoutExecute,
        tx,
      );
      const payout = await this.deps.payoutService.cancel({
        payoutId: id,
        actorId: actor.userId,
        context: actor.context,
        reason,
        tx,
      });
      return this.view(payout, tx);
    });
  }

  // --- internals ----------------------------------------------------------------

  /** `payout.execute` held AND a fresh step-up. Never refuses: it answers. */
  private async mayReadDestination(
    actor: AdminActor,
    tx: AgentTx,
  ): Promise<boolean> {
    if (!actor.stepUpFresh) return false;
    return this.deps.permission.has(
      actor.userId,
      splitPermission(PERM.payoutExecute),
      tx,
    );
  }

  private async withDestination(
    actor: AdminActor,
    payout: AgentPayoutRecord,
    tx: AgentTx,
  ): Promise<AdminPayoutWithDestination> {
    const destination = await this.disclose(actor, payout, tx);
    if (destination === null) {
      // The agent's payout details must exist for a payout to have been made.
      throw new AgentMoneyError('PAYOUT_DETAILS_NOT_SET');
    }
    return { ...(await this.view(payout, tx)), destination };
  }

  /**
   * Opens the agent's payout details and writes the disclosure audit row in
   * the same transaction. The row holds the payout id and the method, never
   * the value. Returns null when the agent has no details on file.
   */
  private async disclose(
    actor: AdminActor,
    payout: AgentPayoutRecord,
    tx: AgentTx,
  ): Promise<PayoutDestination | null> {
    const details = await this.deps.payoutDetails.find(payout.agentId, tx);
    if (details === null) return null;
    const destination = JSON.parse(
      this.deps.sealer.open(details.detailsSealed),
    ) as PayoutDestination;
    await this.deps.audit.record(
      {
        actorId: actor.userId,
        ...(actor.context !== undefined && { context: actor.context }),
        action: 'payout.destination.disclose',
        entity: 'Payout',
        entityId: payout.id,
        metadata: { payoutId: payout.id, method: details.method },
      },
      tx,
    );
    return destination;
  }

  private async view(
    payout: AgentPayoutRecord,
    tx: AgentTx,
    commissions?: CommissionRecord[],
  ): Promise<AdminPayout> {
    const agent = await this.deps.agents.findById(payout.agentId, tx);
    const codes = await this.deps.codes.listByAgent(payout.agentId, tx);
    const primary = codes.find((c) => c.isPrimary) ?? null;
    const attached =
      commissions ?? (await this.deps.commissions.listByPayout(payout.id, tx));
    return {
      id: payout.id,
      agentId: payout.agentId,
      agentName: agent?.name ?? '',
      agentCode: primary?.code ?? null,
      period: payout.period,
      amountPaise: payout.amountPaise,
      taxWithheldPaise: payout.taxWithheldPaise,
      netPaise: payout.netPaise,
      status: payout.status,
      reference: payout.reference,
      paidAt: payout.paidAt?.toISOString() ?? null,
      createdAt: payout.createdAt.toISOString(),
      createdBy: payout.createdBy,
      commissionIds: attached.map((c) => c.id),
      warnings: ['TAX_RULE_NOT_SET'],
      cancelReason: payout.cancelReason,
    };
  }
}
