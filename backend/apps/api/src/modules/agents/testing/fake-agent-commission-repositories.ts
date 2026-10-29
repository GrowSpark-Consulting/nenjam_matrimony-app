/**
 * In-memory commission, ledger and payout repositories. Tests only.
 *
 * Like `fake-agent-repositories.ts`: every method accepts the optional `tx`,
 * a write given a `tx` is undone if the transaction fails, and reads see live
 * state. They must pass the same contract suite as the Prisma adapters
 * (`agent-commission.contract.ts`).
 */
import type { LedgerEntry } from '../commission/ledger-entries';
import {
  OPEN_COMMISSION_STATUSES,
  type AgentLedgerRepository,
  type AgentPayoutListFilter,
  type AgentPayoutRecord,
  type AgentPayoutRepository,
  type CommissionChanges,
  type CommissionListFilter,
  type CommissionPageCursor,
  type CommissionPolicyRepository,
  type CommissionPolicyVersionRecord,
  type CommissionRecord,
  type CommissionRepository,
  type CommissionStatusValue,
  type StoredLedgerEntry,
} from '../ports/agent-commission-ports';
import { AgentConflictError } from '../ports/agent-data-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { trackWrite } from './fake-agent-unit-of-work';

const copy = <T extends object>(row: T): T => ({ ...row });

const newestFirst = (
  a: { createdAt: Date; id: string },
  b: { createdAt: Date; id: string },
) =>
  b.createdAt.getTime() - a.createdAt.getTime() ||
  (a.id < b.id ? 1 : a.id > b.id ? -1 : 0);

const isAfterCursor = (
  row: { createdAt: Date; id: string },
  after: CommissionPageCursor,
) =>
  row.createdAt.getTime() < after.at.getTime() ||
  (row.createdAt.getTime() === after.at.getTime() && row.id < after.id);

// --- Policy -----------------------------------------------------------------

export class FakeCommissionPolicyRepository implements CommissionPolicyRepository {
  private readonly rows = new Map<string, CommissionPolicyVersionRecord>();
  private readonly assigned = new Map<string, string>();

  /** Test helper: adds a version. */
  add(version: CommissionPolicyVersionRecord): void {
    this.rows.set(version.id, copy(version));
  }

  findById(id: string): Promise<CommissionPolicyVersionRecord | null> {
    const row = this.rows.get(id);
    return Promise.resolve(row ? copy(row) : null);
  }

  findActive(at: Date): Promise<CommissionPolicyVersionRecord | null> {
    const active = [...this.rows.values()]
      .filter((r) => r.effectiveFrom.getTime() <= at.getTime())
      .sort((a, b) => b.version - a.version)[0];
    return Promise.resolve(active ? copy(active) : null);
  }

  async findForAgent(
    agentId: string,
    at: Date,
  ): Promise<CommissionPolicyVersionRecord | null> {
    const own = this.assigned.get(agentId);
    if (own !== undefined) return this.findById(own);
    return this.findActive(at);
  }

  assignToAgent(
    agentId: string,
    policyId: string | null,
    tx?: AgentTx,
  ): Promise<void> {
    const track = trackWrite(tx);
    if (policyId !== null && !this.rows.has(policyId)) {
      return Promise.reject(new Error(`Unknown policy ${policyId}`));
    }
    const before = this.assigned.get(agentId);
    if (policyId === null) this.assigned.delete(agentId);
    else this.assigned.set(agentId, policyId);
    track(() => {
      if (before === undefined) this.assigned.delete(agentId);
      else this.assigned.set(agentId, before);
    });
    return Promise.resolve();
  }
}

// --- Commissions ------------------------------------------------------------

export class FakeCommissionRepository implements CommissionRepository {
  private readonly rows = new Map<string, CommissionRecord>();

  create(
    commission: CommissionRecord,
    tx?: AgentTx,
  ): Promise<CommissionRecord> {
    const track = trackWrite(tx);
    const rows = [...this.rows.values()];
    if (this.rows.has(commission.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    if (
      rows.some(
        (r) =>
          r.paymentId === commission.paymentId ||
          r.attributionId === commission.attributionId ||
          r.phoneHash === commission.phoneHash,
      )
    ) {
      return Promise.reject(new AgentConflictError('DUPLICATE_COMMISSION'));
    }
    this.rows.set(commission.id, this.clone(commission));
    track(() => {
      this.rows.delete(commission.id);
    });
    return Promise.resolve(this.clone(commission));
  }

  findById(id: string): Promise<CommissionRecord | null> {
    return Promise.resolve(this.get(id));
  }

  findByPaymentId(paymentId: string): Promise<CommissionRecord | null> {
    const row = [...this.rows.values()].find((r) => r.paymentId === paymentId);
    return Promise.resolve(row ? this.clone(row) : null);
  }

  findByAttributionId(attributionId: string): Promise<CommissionRecord | null> {
    const row = [...this.rows.values()].find(
      (r) => r.attributionId === attributionId,
    );
    return Promise.resolve(row ? this.clone(row) : null);
  }

  update(
    id: string,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row) return Promise.reject(new Error(`Unknown commission ${id}`));
    const before = this.clone(row);
    Object.assign(row, definedOnly(changes));
    track(() => {
      this.rows.set(id, before);
    });
    return Promise.resolve(this.clone(row));
  }

  transition(
    id: string,
    from: CommissionStatusValue,
    changes: CommissionChanges,
    tx?: AgentTx,
  ): Promise<CommissionRecord | null> {
    const row = this.rows.get(id);
    if (!row || row.status !== from) return Promise.resolve(null);
    return this.update(id, changes, tx);
  }

  listOpen(page: {
    limit: number;
    afterId?: string;
  }): Promise<CommissionRecord[]> {
    const after = page.afterId;
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            OPEN_COMMISSION_STATUSES.includes(r.status) &&
            (after === undefined || r.id > after),
        )
        .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
        .slice(0, page.limit)
        .map((r) => this.clone(r)),
    );
  }

  listPayableByAgent(agentId: string): Promise<CommissionRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            r.agentId === agentId &&
            r.status === 'APPROVED' &&
            r.payoutId === null,
        )
        .sort(
          (a, b) =>
            a.createdAt.getTime() - b.createdAt.getTime() ||
            (a.id < b.id ? -1 : 1),
        )
        .map((r) => this.clone(r)),
    );
  }

  listByPayout(payoutId: string): Promise<CommissionRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter((r) => r.payoutId === payoutId)
        .sort(
          (a, b) =>
            a.createdAt.getTime() - b.createdAt.getTime() ||
            (a.id < b.id ? -1 : 1),
        )
        .map((r) => this.clone(r)),
    );
  }

  listPage(
    filter: CommissionListFilter,
    page: { limit: number; after?: CommissionPageCursor },
  ): Promise<CommissionRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            (filter.agentId === undefined || r.agentId === filter.agentId) &&
            (filter.status === undefined || r.status === filter.status) &&
            (page.after === undefined || isAfterCursor(r, page.after)),
        )
        .sort(newestFirst)
        .slice(0, page.limit)
        .map((r) => this.clone(r)),
    );
  }

  attachToPayout(
    commissionIds: readonly string[],
    payoutId: string,
    tx?: AgentTx,
  ): Promise<number> {
    const track = trackWrite(tx);
    const attached: CommissionRecord[] = [];
    for (const id of new Set(commissionIds)) {
      const row = this.rows.get(id);
      if (row && row.status === 'APPROVED' && row.payoutId === null) {
        row.payoutId = payoutId;
        attached.push(row);
      }
    }
    track(() => {
      for (const row of attached) row.payoutId = null;
    });
    return Promise.resolve(attached.length);
  }

  releaseFromPayout(payoutId: string, tx?: AgentTx): Promise<number> {
    const track = trackWrite(tx);
    const released = [...this.rows.values()].filter(
      (r) => r.payoutId === payoutId,
    );
    for (const row of released) row.payoutId = null;
    track(() => {
      for (const row of released) row.payoutId = payoutId;
    });
    return Promise.resolve(released.length);
  }

  markPaidForPayout(payoutId: string, at: Date, tx?: AgentTx): Promise<number> {
    const track = trackWrite(tx);
    const paid = [...this.rows.values()].filter(
      (r) => r.payoutId === payoutId && r.status === 'APPROVED',
    );
    for (const row of paid) {
      row.status = 'PAID';
      row.paidAt = new Date(at.getTime());
    }
    track(() => {
      for (const row of paid) {
        row.status = 'APPROVED';
        row.paidAt = null;
      }
    });
    return Promise.resolve(paid.length);
  }

  private get(id: string): CommissionRecord | null {
    const row = this.rows.get(id);
    return row ? this.clone(row) : null;
  }

  private clone(row: CommissionRecord): CommissionRecord {
    return { ...row, reviewReasons: [...row.reviewReasons] };
  }
}

function definedOnly<T extends object>(changes: T): Partial<T> {
  return Object.fromEntries(
    Object.entries(changes).filter(([, value]) => value !== undefined),
  ) as Partial<T>;
}

// --- Ledger -----------------------------------------------------------------

/** A copy that keeps real Dates and plain-data snapshots (structuredClone yields a foreign Date under jest). */
function cloneEntry<T extends LedgerEntry>(entry: T): T {
  const copied = { ...entry } as T & { createdAt?: Date };
  if (copied.createdAt) copied.createdAt = new Date(copied.createdAt.getTime());
  if (entry.ruleSnapshot !== null && entry.ruleSnapshot !== undefined) {
    copied.ruleSnapshot = JSON.parse(
      JSON.stringify(entry.ruleSnapshot),
    ) as unknown;
  }
  return copied;
}

export class FakeAgentLedgerRepository implements AgentLedgerRepository {
  private rows: StoredLedgerEntry[] = [];
  private nextId = 1;

  constructor(private readonly now: () => Date = () => new Date()) {}

  append(entry: LedgerEntry, tx?: AgentTx): Promise<{ inserted: boolean }> {
    const track = trackWrite(tx);
    if (this.rows.some((r) => r.idempotencyKey === entry.idempotencyKey)) {
      return Promise.resolve({ inserted: false });
    }
    const row: StoredLedgerEntry = {
      ...cloneEntry(entry),
      id: `ledger-${this.nextId++}`,
      createdAt: this.now(),
    };
    this.rows.push(row);
    track(() => {
      this.rows = this.rows.filter((r) => r !== row);
    });
    return Promise.resolve({ inserted: true });
  }

  findByKey(idempotencyKey: string): Promise<StoredLedgerEntry | null> {
    const row = this.rows.find((r) => r.idempotencyKey === idempotencyKey);
    return Promise.resolve(row ? cloneEntry(row) : null);
  }

  balance(agentId: string): Promise<number> {
    return Promise.resolve(
      this.rows
        .filter((r) => r.agentId === agentId)
        .reduce((sum, r) => sum + r.amountPaise, 0),
    );
  }

  listByAgent(agentId: string): Promise<StoredLedgerEntry[]> {
    return Promise.resolve(
      this.rows.filter((r) => r.agentId === agentId).map((r) => cloneEntry(r)),
    );
  }

  /** Test helper: every stored entry. */
  get all(): readonly StoredLedgerEntry[] {
    return this.rows.map((r) => cloneEntry(r));
  }
}

// --- Payouts ----------------------------------------------------------------

export class FakeAgentPayoutRepository implements AgentPayoutRepository {
  private readonly rows = new Map<string, AgentPayoutRecord>();

  create(payout: AgentPayoutRecord, tx?: AgentTx): Promise<AgentPayoutRecord> {
    const track = trackWrite(tx);
    if (this.rows.has(payout.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    if (
      payout.status !== 'CANCELLED' &&
      [...this.rows.values()].some(
        (r) =>
          r.agentId === payout.agentId &&
          r.period === payout.period &&
          r.status !== 'CANCELLED',
      )
    ) {
      return Promise.reject(new AgentConflictError('DUPLICATE_PAYOUT'));
    }
    this.rows.set(payout.id, copy(payout));
    track(() => {
      this.rows.delete(payout.id);
    });
    return Promise.resolve(copy(payout));
  }

  findById(id: string): Promise<AgentPayoutRecord | null> {
    const row = this.rows.get(id);
    return Promise.resolve(row ? copy(row) : null);
  }

  findActiveByAgentPeriod(
    agentId: string,
    period: string,
  ): Promise<AgentPayoutRecord | null> {
    const row = [...this.rows.values()].find(
      (r) =>
        r.agentId === agentId &&
        r.period === period &&
        r.status !== 'CANCELLED',
    );
    return Promise.resolve(row ? copy(row) : null);
  }

  findByReference(reference: string): Promise<AgentPayoutRecord | null> {
    const row = [...this.rows.values()].find((r) => r.reference === reference);
    return Promise.resolve(row ? copy(row) : null);
  }

  markPaid(
    id: string,
    paid: { reference: string; paidAt: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row || row.status !== 'CREATED') return Promise.resolve(null);
    if (
      [...this.rows.values()].some(
        (r) => r.id !== id && r.reference === paid.reference,
      )
    ) {
      return Promise.reject(
        new AgentConflictError('DUPLICATE_PAYOUT_REFERENCE'),
      );
    }
    const before = copy(row);
    row.status = 'PAID';
    row.reference = paid.reference;
    row.paidAt = new Date(paid.paidAt.getTime());
    track(() => {
      this.rows.set(id, before);
    });
    return Promise.resolve(copy(row));
  }

  cancel(
    id: string,
    cancelled: { reason: string; at: Date },
    tx?: AgentTx,
  ): Promise<AgentPayoutRecord | null> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row || row.status !== 'CREATED') return Promise.resolve(null);
    const before = copy(row);
    row.status = 'CANCELLED';
    row.cancelReason = cancelled.reason;
    row.cancelledAt = new Date(cancelled.at.getTime());
    track(() => {
      this.rows.set(id, before);
    });
    return Promise.resolve(copy(row));
  }

  listPage(
    filter: AgentPayoutListFilter,
    page: { limit: number; after?: { at: Date; id: string } },
  ): Promise<AgentPayoutRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            (filter.agentId === undefined || r.agentId === filter.agentId) &&
            (filter.status === undefined || r.status === filter.status) &&
            (filter.period === undefined || r.period === filter.period) &&
            (page.after === undefined || isAfterCursor(r, page.after)),
        )
        .sort(newestFirst)
        .slice(0, page.limit)
        .map(copy),
    );
  }
}
