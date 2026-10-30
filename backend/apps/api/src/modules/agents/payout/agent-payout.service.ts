/**
 * Manual payouts: create, mark paid, cancel. Money moves outside the app; the
 * payout records it. No permission check here: the admin service checks the
 * caller and then calls this.
 *
 * Every method runs in one `AgentUnitOfWork` transaction with its audit row,
 * and is safe to repeat:
 * - `create` is idempotent by agent and period: a second call returns the
 *   payout that exists (`created: false`) and changes nothing. Two calls at
 *   once are decided by the database's one-payout rule.
 * - `markPaid` is idempotent by reference: the same reference again returns
 *   the paid payout; a different reference on a paid payout is refused. The
 *   change is one conditional update (only from CREATED).
 * - `cancel` is idempotent: a cancelled payout stays as it is. It releases
 *   the ledger debit (`payout-release:<payoutId>`) and frees the commissions.
 * Nothing is paid out of a ledger balance that cannot cover it.
 */
import { randomUUID } from 'node:crypto';
import { AgentConfigError } from '../config/agent-config.service';
import { AgentMoneyError } from '../errors/agent-money-error';
import {
  buildPayoutDebitEntry,
  buildPayoutReleaseEntry,
} from '../commission/ledger-entries';
import type {
  AgentLedgerRepository,
  AgentPayoutRecord,
  AgentPayoutRepository,
  CommissionRepository,
} from '../ports/agent-commission-ports';
import {
  AgentConflictError,
  type AgentPayoutDetailsRepository,
  type AgentRepository,
} from '../ports/agent-data-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type {
  AgentAuditEntry,
  AgentAuditPort,
  AgentSettingsPort,
} from '../ports/agent-platform-ports';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';
import {
  AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
  PAYOUT_TAX_WITHHOLDING_KEY,
  parseAgentProgramSettings,
} from '../settings/agent-program-settings';
import { decidePayoutEligibility } from './decide-payout-eligibility';
import { planPayout } from './plan-payout';

export interface AgentPayoutServiceDeps {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  payoutDetails: AgentPayoutDetailsRepository;
  commissions: CommissionRepository;
  ledger: AgentLedgerRepository;
  payouts: AgentPayoutRepository;
  settings: AgentSettingsPort;
  audit: AgentAuditPort;
  clock: AgentClock;
}

export interface CreatePayoutInput {
  agentId: string;
  /** 'YYYY-MM'. */
  period: string;
  /** The staff user who asked. */
  actorId: string;
  /** The request the change came from, for the audit row. */
  context?: AgentAuditEntry['context'];
  reason: string;
  /**
   * Join the caller's transaction (the admin service checks the permission in
   * it). A unique conflict then propagates to the caller, because Postgres has
   * aborted that transaction; the caller handles it after the transaction.
   */
  tx?: AgentTx;
}

export interface MarkPaidInput {
  payoutId: string;
  reference: string;
  paidAt: Date;
  actorId: string;
  /** The request the change came from, for the audit row. */
  context?: AgentAuditEntry['context'];
  reason: string;
  tx?: AgentTx;
}

export interface CancelPayoutInput {
  payoutId: string;
  actorId: string;
  /** The request the change came from, for the audit row. */
  context?: AgentAuditEntry['context'];
  reason: string;
  tx?: AgentTx;
}

export class AgentPayoutService {
  private readonly newId: () => string;

  constructor(
    private readonly deps: AgentPayoutServiceDeps,
    options: { newId?: () => string } = {},
  ) {
    this.newId = options.newId ?? randomUUID;
  }

  async create(
    input: CreatePayoutInput,
  ): Promise<{ payout: AgentPayoutRecord; created: boolean }> {
    requireText('agentId', input.agentId);
    requireText('actorId', input.actorId);
    requireReason(input.reason);
    const raw = await this.deps.settings.getMany([
      PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
      AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
      PAYOUT_TAX_WITHHOLDING_KEY,
    ]);
    const { settings } = parseAgentProgramSettings(raw);
    const missing = [
      settings.payoutMinimumAmountPaise === undefined &&
        PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
      settings.agentPayoutDetailsWaitHours === undefined &&
        AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
    ].filter((k): k is string => typeof k === 'string');
    if (missing.length > 0) throw new AgentConfigError(missing);
    // `payout.tax_withholding` legitimately stays null ("not decided").
    const minimumPaise = settings.payoutMinimumAmountPaise as number;
    const waitHours = settings.agentPayoutDetailsWaitHours as number;
    const taxWithholding = raw[PAYOUT_TAX_WITHHOLDING_KEY] ?? null;

    try {
      return await this.within(input.tx, async (tx) => {
        const { payouts } = this.deps;
        const existing = await payouts.findActiveByAgentPeriod(
          input.agentId,
          input.period,
          tx,
        );
        if (existing) return { payout: existing, created: false };

        const agent = await this.deps.agents.findById(input.agentId, tx);
        if (agent === null) throw new AgentMoneyError('AGENT_NOT_FOUND');
        const details = await this.deps.payoutDetails.find(agent.id, tx);
        const commissions = await this.deps.commissions.listPayableByAgent(
          agent.id,
          tx,
        );
        const payable = commissions.map((c) => ({
          id: c.id,
          creditedPaise: c.creditedPaise,
          reversedPaise: c.reversedPaise,
        }));
        const balancePaise = payable.reduce(
          (sum, c) => sum + (c.creditedPaise - c.reversedPaise),
          0,
        );
        const now = this.deps.clock.now();
        const eligibility = decidePayoutEligibility({
          agentStatus: agent.status,
          panVerified: agent.panVerifiedAt !== null,
          payoutDetailsVerified: details?.verifiedAt != null,
          payoutDetailsChangedAt: details?.changedAt ?? null,
          waitHours,
          now,
          balancePaise,
          minimumPaise,
          hasPayoutForPeriod: false,
        });
        const plan = planPayout({
          agentId: agent.id,
          period: input.period,
          commissions: payable,
          eligibility,
          taxWithholding,
        });
        if (!plan.ok) {
          throw new AgentMoneyError('PAYOUT_NOT_ELIGIBLE', {
            reasons: plan.reasons,
          });
        }
        // The ledger must be able to cover it (an earlier clawback may have
        // left less than the commissions add up to).
        const ledgerBalance = await this.deps.ledger.balance(agent.id, tx);
        if (ledgerBalance < plan.payout.amountPaise) {
          throw new AgentMoneyError('PAYOUT_NOT_ELIGIBLE', {
            reasons: ['LEDGER_BALANCE_TOO_LOW'],
          });
        }

        const payout = await payouts.create(
          {
            id: this.newId(),
            agentId: agent.id,
            period: plan.payout.period,
            amountPaise: plan.payout.amountPaise,
            taxWithheldPaise: plan.payout.taxWithheldPaise,
            netPaise: plan.payout.netPaise,
            status: 'CREATED',
            reference: null,
            paidAt: null,
            cancelReason: null,
            cancelledAt: null,
            createdBy: input.actorId,
            createdAt: now,
          },
          tx,
        );
        const attached = await this.deps.commissions.attachToPayout(
          plan.payout.commissionIds,
          payout.id,
          tx,
        );
        if (attached !== plan.payout.commissionIds.length) {
          throw new AgentMoneyError('CONCURRENT_CHANGE');
        }
        await this.deps.audit.record(
          {
            actorId: input.actorId,
            ...(input.context !== undefined && { context: input.context }),
            action: 'payout.create',
            entity: 'payout',
            entityId: payout.id,
            metadata: {
              agentId: agent.id,
              period: payout.period,
              amountPaise: payout.amountPaise,
              commissionCount: attached,
              reason: input.reason.trim(),
            },
          },
          tx,
        );
        await this.deps.ledger.append(
          buildPayoutDebitEntry({
            agentId: agent.id,
            payoutId: payout.id,
            amountPaise: payout.amountPaise,
          }),
          tx,
        );
        return { payout, created: true };
      });
    } catch (error) {
      // Two requests for the same agent and period at once: the database kept
      // the first; answer with it.
      if (
        input.tx === undefined &&
        error instanceof AgentConflictError &&
        error.reason === 'DUPLICATE_PAYOUT'
      ) {
        const existing = await this.deps.payouts.findActiveByAgentPeriod(
          input.agentId,
          input.period,
        );
        if (existing) return { payout: existing, created: false };
      }
      throw error;
    }
  }

  async markPaid(input: MarkPaidInput): Promise<AgentPayoutRecord> {
    requireText('payoutId', input.payoutId);
    requireText('actorId', input.actorId);
    requireText('reference', input.reference);
    requireReason(input.reason);
    if (Number.isNaN(input.paidAt.getTime())) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['paidAt'] });
    }
    const reference = input.reference.trim();
    const now = this.deps.clock.now();
    if (input.paidAt.getTime() > now.getTime()) {
      throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['paidAt'] });
    }
    try {
      return await this.within(input.tx, async (tx) => {
        const { payouts } = this.deps;
        const current = await payouts.findById(input.payoutId, tx);
        if (current === null) throw new AgentMoneyError('PAYOUT_NOT_FOUND');
        if (current.status === 'PAID') {
          // The same reference again is the same request: nothing changes.
          if (current.reference === reference) return current;
          throw new AgentMoneyError('PAYOUT_STATUS_NOT_ALLOWED');
        }
        if (current.status !== 'CREATED') {
          throw new AgentMoneyError('PAYOUT_STATUS_NOT_ALLOWED');
        }
        const paid = await payouts.markPaid(
          current.id,
          { reference, paidAt: input.paidAt },
          tx,
        );
        if (paid === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
        await this.deps.audit.record(
          {
            actorId: input.actorId,
            ...(input.context !== undefined && { context: input.context }),
            action: 'payout.mark_paid',
            entity: 'payout',
            entityId: current.id,
            metadata: { agentId: current.agentId, reason: input.reason.trim() },
          },
          tx,
        );
        await this.deps.commissions.markPaidForPayout(
          current.id,
          input.paidAt,
          tx,
        );
        return paid;
      });
    } catch (error) {
      if (error instanceof AgentConflictError) {
        if (error.reason === 'DUPLICATE_PAYOUT_REFERENCE') {
          throw new AgentMoneyError('REFERENCE_ALREADY_USED');
        }
      }
      if (
        input.tx === undefined &&
        error instanceof AgentMoneyError &&
        error.code === 'CONCURRENT_CHANGE'
      ) {
        // Lost a race: if the winner used the same reference, this is a repeat.
        const now = await this.deps.payouts.findById(input.payoutId);
        if (now?.status === 'PAID' && now.reference === reference) return now;
        if (now !== null)
          throw new AgentMoneyError('PAYOUT_STATUS_NOT_ALLOWED');
      }
      throw error;
    }
  }

  async cancel(input: CancelPayoutInput): Promise<AgentPayoutRecord> {
    requireText('payoutId', input.payoutId);
    requireText('actorId', input.actorId);
    requireReason(input.reason);
    const now = this.deps.clock.now();
    return this.within(input.tx, async (tx) => {
      const { payouts } = this.deps;
      const current = await payouts.findById(input.payoutId, tx);
      if (current === null) throw new AgentMoneyError('PAYOUT_NOT_FOUND');
      // Already cancelled: nothing more to do.
      if (current.status === 'CANCELLED') return current;
      if (current.status !== 'CREATED') {
        throw new AgentMoneyError('PAYOUT_STATUS_NOT_ALLOWED');
      }
      const cancelled = await payouts.cancel(
        current.id,
        { reason: input.reason.trim(), at: now },
        tx,
      );
      if (cancelled === null) throw new AgentMoneyError('CONCURRENT_CHANGE');
      await this.deps.audit.record(
        {
          actorId: input.actorId,
          ...(input.context !== undefined && { context: input.context }),
          action: 'payout.cancel',
          entity: 'payout',
          entityId: current.id,
          metadata: {
            agentId: current.agentId,
            reason: input.reason.trim(),
          },
        },
        tx,
      );
      await this.deps.commissions.releaseFromPayout(current.id, tx);
      await this.deps.ledger.append(
        buildPayoutReleaseEntry({
          agentId: current.agentId,
          payoutId: current.id,
          amountPaise: current.amountPaise,
        }),
        tx,
      );
      return cancelled;
    });
  }

  /** Runs in the caller's transaction when given one, else in a new one. */
  private within<T>(
    tx: AgentTx | undefined,
    fn: (tx: AgentTx) => Promise<T>,
  ): Promise<T> {
    return tx === undefined ? this.deps.uow.run(fn) : fn(tx);
  }
}

function requireText(name: string, value: unknown): void {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: [name] });
  }
}

/** A reason is 3 to 500 characters (the admin contract's `Reason`). */
function requireReason(value: unknown): void {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < 3 || text.length > 500) {
    throw new AgentMoneyError('VALIDATION_FAILED', { fields: ['reason'] });
  }
}
