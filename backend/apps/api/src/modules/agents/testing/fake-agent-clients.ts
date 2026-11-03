/**
 * In-memory client draft repository and consent-code store. Tests only.
 *
 * They behave like the Prisma adapters on the table's rules (one open draft
 * per agent and phone, the allowed status changes, the conditional writes)
 * and pass the same contract suite (`agent-clients.contract.ts`). Writes
 * given a `tx` are undone when the transaction fails.
 */
import {
  AgentConflictError,
  type AgentRepository,
} from '../ports/agent-data-ports';
import {
  OPEN_CLIENT_DRAFT_STATUSES,
  type AgentClientConsentCodeRecord,
  type AgentClientConsentCodeStore,
  type AgentClientDraftRecord,
  type AgentClientDraftRepository,
  type ClientDraftClosedReason,
  type ClientDraftListFilter,
  type ClientDraftPageCursor,
  type NewAgentClientDraft,
} from '../ports/agent-client-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { effectiveClientDraftStatus } from '../clients/decide-client-draft';
import { onTxFinish, trackWrite } from './fake-agent-unit-of-work';

const copy = <T extends object>(row: T): T => ({ ...row });

const isOpen = (row: AgentClientDraftRecord) =>
  OPEN_CLIENT_DRAFT_STATUSES.includes(row.status);

const due = (row: AgentClientDraftRecord, now: Date) =>
  isOpen(row) && row.expiresAt.getTime() <= now.getTime();

/** Newest first: (createdAt, id) descending. */
const newestFirst = (a: AgentClientDraftRecord, b: AgentClientDraftRecord) =>
  b.createdAt.getTime() - a.createdAt.getTime() ||
  (a.id < b.id ? 1 : a.id > b.id ? -1 : 0);

const oldestFirst = (a: AgentClientDraftRecord, b: AgentClientDraftRecord) =>
  -newestFirst(a, b);

export class FakeAgentClientDraftRepository implements AgentClientDraftRepository {
  private readonly rows = new Map<string, AgentClientDraftRecord>();
  /** Held row locks ("agent:<id>", "draft:<id>"): released when the holding tx ends. */
  private readonly locks = new Map<
    string,
    { tx: AgentTx; released: Promise<void> }
  >();

  /** `agents` answers which agents are TERMINATED (the job closes their drafts). */
  constructor(private readonly agents?: Pick<AgentRepository, 'findById'>) {}

  /** Test helper: the stored row as it is (or undefined). */
  peek(id: string): AgentClientDraftRecord | undefined {
    const row = this.rows.get(id);
    return row ? copy(row) : undefined;
  }

  /** Test helper: every stored row. */
  all(): AgentClientDraftRecord[] {
    return [...this.rows.values()].map(copy);
  }

  create(
    draft: NewAgentClientDraft,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord> {
    const track = trackWrite(tx);
    if (this.rows.has(draft.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    for (const row of this.rows.values()) {
      if (
        isOpen(row) &&
        row.agentId === draft.agentId &&
        row.phoneHash === draft.phoneHash
      ) {
        return Promise.reject(
          new AgentConflictError('DUPLICATE_OPEN_CLIENT_DRAFT'),
        );
      }
    }
    const row: AgentClientDraftRecord = {
      ...draft,
      status: 'DRAFT',
      submittedAt: null,
      acceptedAt: null,
      closedAt: null,
      closedReason: null,
      memberId: null,
      attributionId: null,
    };
    this.rows.set(row.id, row);
    track(() => {
      this.rows.delete(row.id);
    });
    return Promise.resolve(copy(row));
  }

  findByIdForAgent(
    id: string,
    agentId: string,
  ): Promise<AgentClientDraftRecord | null> {
    const row = this.rows.get(id);
    return Promise.resolve(row && row.agentId === agentId ? copy(row) : null);
  }

  listPageByAgent(
    agentId: string,
    filter: ClientDraftListFilter,
    page: { limit: number; after?: ClientDraftPageCursor },
  ): Promise<AgentClientDraftRecord[]> {
    const { after } = page;
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            r.agentId === agentId &&
            (filter.status === undefined ||
              effectiveClientDraftStatus(r, filter.now) === filter.status) &&
            (after === undefined ||
              r.createdAt.getTime() < after.at.getTime() ||
              (r.createdAt.getTime() === after.at.getTime() &&
                r.id < after.id)),
        )
        .sort(newestFirst)
        .slice(0, page.limit)
        .map(copy),
    );
  }

  countOpen(agentId: string): Promise<number> {
    return Promise.resolve(
      [...this.rows.values()].filter((r) => r.agentId === agentId && isOpen(r))
        .length,
    );
  }

  lockAgent(agentId: string, tx: AgentTx): Promise<void> {
    return this.lock(`agent:${agentId}`, tx);
  }

  findOpenByAgentAndHashes(
    agentId: string,
    phoneHashes: readonly string[],
  ): Promise<AgentClientDraftRecord | null> {
    const row = [...this.rows.values()].find(
      (r) =>
        r.agentId === agentId && isOpen(r) && phoneHashes.includes(r.phoneHash),
    );
    return Promise.resolve(row ? copy(row) : null);
  }

  wasRejectedBy(
    agentId: string,
    phoneHashes: readonly string[],
  ): Promise<boolean> {
    return Promise.resolve(
      [...this.rows.values()].some(
        (r) =>
          r.agentId === agentId &&
          r.status === 'REJECTED' &&
          phoneHashes.includes(r.phoneHash),
      ),
    );
  }

  updateDetails(
    id: string,
    agentId: string,
    changes: { displayName: string; detailsSealed: string },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.change(
      id,
      (r) => r.agentId === agentId && r.status === 'DRAFT' && !due(r, now),
      changes,
      tx,
    );
  }

  submit(
    id: string,
    agentId: string,
    changes: { submittedAt: Date; expiresAt: Date },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.change(
      id,
      (r) => r.agentId === agentId && r.status === 'DRAFT' && !due(r, now),
      { ...changes, status: 'WAITING_FOR_CLIENT' },
      tx,
    );
  }

  discard(id: string, agentId: string, tx?: AgentTx): Promise<boolean> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row || row.agentId !== agentId || row.status !== 'DRAFT') {
      return Promise.resolve(false);
    }
    this.rows.delete(id);
    track(() => {
      this.rows.set(id, row);
    });
    return Promise.resolve(true);
  }

  findForPhone(
    id: string,
    phoneHashes: readonly string[],
  ): Promise<AgentClientDraftRecord | null> {
    const row = this.rows.get(id);
    return Promise.resolve(
      row && phoneHashes.includes(row.phoneHash) ? copy(row) : null,
    );
  }

  listWaitingForHashes(
    phoneHashes: readonly string[],
    now: Date,
  ): Promise<AgentClientDraftRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter(
          (r) =>
            r.status === 'WAITING_FOR_CLIENT' &&
            phoneHashes.includes(r.phoneHash) &&
            !due(r, now),
        )
        .sort(oldestFirst)
        .map(copy),
    );
  }

  async lockWaitingForAccept(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    await this.lock(`draft:${id}`, tx);
    const row = this.rows.get(id);
    return row &&
      row.status === 'WAITING_FOR_CLIENT' &&
      phoneHashes.includes(row.phoneHash) &&
      !due(row, now)
      ? copy(row)
      : null;
  }

  /** Waits for any other holder, then holds the lock until `tx` ends. */
  private async lock(key: string, tx: AgentTx): Promise<void> {
    trackWrite(tx);
    // Re-entrant, as a database row lock is within its own transaction.
    if (this.locks.get(key)?.tx === tx) return;
    for (let held = this.locks.get(key); held; held = this.locks.get(key)) {
      await held.released;
    }
    let release!: () => void;
    this.locks.set(key, {
      tx,
      released: new Promise<void>((resolve) => (release = resolve)),
    });
    onTxFinish(tx, () => {
      this.locks.delete(key);
      release();
    });
  }

  async markAccepted(
    id: string,
    changes: { memberId: string; attributionId: string; acceptedAt: Date },
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord> {
    const updated = await this.change(
      id,
      (r) => r.status === 'WAITING_FOR_CLIENT',
      {
        ...changes,
        status: 'ACCEPTED',
        phoneSealed: null,
        detailsSealed: null,
      },
      tx,
    );
    // As the database's trigger would: only a waiting draft can be accepted.
    if (updated === null) {
      throw new Error('Only a WAITING_FOR_CLIENT draft can be accepted.');
    }
    return updated;
  }

  markRejected(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    return this.change(
      id,
      (r) =>
        r.status === 'WAITING_FOR_CLIENT' &&
        phoneHashes.includes(r.phoneHash) &&
        !due(r, now),
      // The sealed phone stays: it is the lasting "never again" block.
      { status: 'REJECTED', closedAt: now, detailsSealed: null },
      tx,
    );
  }

  async close(
    id: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<boolean> {
    return (await this.closeWhere([id], reason, now, tx)).length === 1;
  }

  closeOthersForPhone(
    phoneHashes: readonly string[],
    exceptId: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<string[]> {
    const ids = [...this.rows.values()]
      .filter(
        (r) =>
          r.id !== exceptId && isOpen(r) && phoneHashes.includes(r.phoneHash),
      )
      .sort(oldestFirst)
      .map((r) => r.id);
    return this.closeWhere(ids, reason, now, tx);
  }

  expireDue(
    agentId: string | null,
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]> {
    const ids = [...this.rows.values()]
      .filter((r) => (agentId === null || r.agentId === agentId) && due(r, now))
      .sort(
        (a, b) =>
          a.expiresAt.getTime() - b.expiresAt.getTime() ||
          (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
      )
      .slice(0, limit)
      .map((r) => r.id);
    return this.closeWhere(ids, 'TIMED_OUT', now, tx);
  }

  async closeOfTerminatedAgents(
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]> {
    const ids: string[] = [];
    for (const r of [...this.rows.values()].sort(oldestFirst)) {
      if (ids.length >= limit) break;
      if (!isOpen(r)) continue;
      const agent = await this.agents?.findById(r.agentId);
      if (agent?.status === 'TERMINATED') ids.push(r.id);
    }
    return this.closeWhere(ids, 'AGENT_TERMINATED', now, tx);
  }

  private closeWhere(
    ids: readonly string[],
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<string[]> {
    const track = trackWrite(tx);
    const closed: string[] = [];
    for (const id of ids) {
      const row = this.rows.get(id);
      if (!row || !isOpen(row)) continue;
      const before = copy(row);
      Object.assign(row, {
        status: 'EXPIRED',
        closedAt: now,
        closedReason: reason,
        phoneSealed: null,
        detailsSealed: null,
      });
      track(() => {
        this.rows.set(id, before);
      });
      closed.push(id);
    }
    return Promise.resolve(closed);
  }

  private change(
    id: string,
    when: (row: AgentClientDraftRecord) => boolean,
    changes: Partial<AgentClientDraftRecord>,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row || !when(row)) return Promise.resolve(null);
    const before = copy(row);
    Object.assign(row, changes);
    track(() => {
      this.rows.set(id, before);
    });
    return Promise.resolve(copy(row));
  }
}

export class FakeAgentClientConsentCodeStore implements AgentClientConsentCodeStore {
  private readonly rows = new Map<string, AgentClientConsentCodeRecord>();

  save(record: AgentClientConsentCodeRecord, tx?: AgentTx): Promise<void> {
    const track = trackWrite(tx);
    const before = this.rows.get(record.phoneHash);
    this.rows.set(record.phoneHash, copy(record));
    track(() => {
      if (before) this.rows.set(record.phoneHash, before);
      else this.rows.delete(record.phoneHash);
    });
    return Promise.resolve();
  }

  find(
    phoneHashes: readonly string[],
  ): Promise<AgentClientConsentCodeRecord | null> {
    for (const hash of phoneHashes) {
      const row = this.rows.get(hash);
      if (row) return Promise.resolve(copy(row));
    }
    return Promise.resolve(null);
  }

  delete(phoneHashes: readonly string[], tx?: AgentTx): Promise<void> {
    const track = trackWrite(tx);
    for (const hash of phoneHashes) {
      const before = this.rows.get(hash);
      if (!before) continue;
      this.rows.delete(hash);
      track(() => {
        this.rows.set(hash, before);
      });
    }
    return Promise.resolve();
  }

  purgeExpired(before: Date, limit: number, tx?: AgentTx): Promise<number> {
    const stale = [...this.rows.values()]
      .filter((r) => r.expiresAt.getTime() < before.getTime())
      .slice(0, limit)
      .map((r) => r.phoneHash);
    return this.delete(stale, tx).then(() => stale.length);
  }

  /** Test helper. */
  size(): number {
    return this.rows.size;
  }
}
