/**
 * In-memory repositories and member port. Tests only.
 *
 * Every method accepts the optional `tx`. A write given a `tx` is undone if
 * the transaction fails (see `FakeAgentUnitOfWork`); reads see live state.
 */
import type { ReferralViewSource } from '../referral/agent-referral-view';
import {
  AgentApplicantRecord,
  AgentApplicantRepository,
  AgentConflictError,
  AgentMemberReadPort,
  AgentMemberSnapshot,
  AgentPayoutDetailsRecord,
  AgentPayoutDetailsRepository,
  AgentRecord,
  AgentRefreshTokenRecord,
  AgentRefreshTokenRepository,
  AgentRepository,
  NewAgentRecord,
  ReferralAttributionRecord,
  ReferralAttributionRepository,
  ReferralCodeRecord,
  ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { trackWrite } from './fake-agent-unit-of-work';

/** Returned objects are copies: callers cannot edit stored rows in place. */
const copy = <T extends object>(row: T): T => ({ ...row });

export class FakeAgentRepository implements AgentRepository {
  private readonly rows = new Map<string, AgentRecord>();

  findById(id: string): Promise<AgentRecord | null> {
    const row = this.rows.get(id);
    return Promise.resolve(row ? copy(row) : null);
  }

  findByPhoneHash(phoneHash: string): Promise<AgentRecord | null> {
    for (const row of this.rows.values()) {
      if (row.phoneHash === phoneHash) return Promise.resolve(copy(row));
    }
    return Promise.resolve(null);
  }

  create(agent: NewAgentRecord, tx?: AgentTx): Promise<AgentRecord> {
    const track = trackWrite(tx);
    if (this.rows.has(agent.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    for (const row of this.rows.values()) {
      if (row.phoneHash === agent.phoneHash) {
        return Promise.reject(new AgentConflictError('DUPLICATE_PHONE_HASH'));
      }
    }
    const row: AgentRecord = {
      ...agent,
      status: 'PENDING_APPROVAL',
      rejectionReason: null,
      approvedAt: null,
      payoutDetailsSet: false,
    };
    this.rows.set(row.id, row);
    track(() => {
      this.rows.delete(row.id);
    });
    return Promise.resolve(copy(row));
  }

  update(
    id: string,
    changes: Parameters<AgentRepository['update']>[1],
    tx?: AgentTx,
  ): Promise<AgentRecord> {
    const track = trackWrite(tx);
    const row = this.rows.get(id);
    if (!row) return Promise.reject(new Error(`Unknown agent ${id}`));
    const before = copy(row);
    Object.assign(row, changes);
    track(() => {
      this.rows.set(id, before);
    });
    return Promise.resolve(copy(row));
  }
}

export class FakeReferralCodeRepository implements ReferralCodeRepository {
  private readonly rows = new Map<string, ReferralCodeRecord>();

  findByCode(code: string): Promise<ReferralCodeRecord | null> {
    for (const row of this.rows.values()) {
      if (row.code === code) return Promise.resolve(copy(row));
    }
    return Promise.resolve(null);
  }

  listByAgent(agentId: string): Promise<ReferralCodeRecord[]> {
    return Promise.resolve(
      [...this.rows.values()]
        .filter((row) => row.agentId === agentId)
        .map(copy),
    );
  }

  codeExists(code: string): Promise<boolean> {
    return Promise.resolve(
      [...this.rows.values()].some((row) => row.code === code),
    );
  }

  create(code: ReferralCodeRecord, tx?: AgentTx): Promise<ReferralCodeRecord> {
    const track = trackWrite(tx);
    const rows = [...this.rows.values()];
    if (this.rows.has(code.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    if (rows.some((row) => row.code === code.code)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_CODE'));
    }
    if (
      code.isPrimary &&
      rows.some((row) => row.agentId === code.agentId && row.isPrimary)
    ) {
      return Promise.reject(new AgentConflictError('DUPLICATE_PRIMARY_CODE'));
    }
    this.rows.set(code.id, copy(code));
    track(() => {
      this.rows.delete(code.id);
    });
    return Promise.resolve(copy(code));
  }
}

export class FakeAgentRefreshTokenRepository implements AgentRefreshTokenRepository {
  private readonly rows = new Map<string, AgentRefreshTokenRecord>();

  create(
    token: AgentRefreshTokenRecord,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord> {
    const track = trackWrite(tx);
    if (this.rows.has(token.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    this.rows.set(token.id, copy(token));
    track(() => {
      this.rows.delete(token.id);
    });
    return Promise.resolve(copy(token));
  }

  findByHash(tokenHash: string): Promise<AgentRefreshTokenRecord | null> {
    for (const row of this.rows.values()) {
      if (row.tokenHash === tokenHash) return Promise.resolve(copy(row));
    }
    return Promise.resolve(null);
  }

  rotate(
    currentId: string,
    next: AgentRefreshTokenRecord,
    at: Date,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord> {
    const track = trackWrite(tx);
    const current = this.rows.get(currentId);
    if (!current) {
      return Promise.reject(new Error(`Unknown token ${currentId}`));
    }
    if (current.revokedAt !== null) {
      return Promise.reject(new AgentConflictError('ALREADY_REVOKED'));
    }
    if (this.rows.has(next.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    current.revokedAt = new Date(at.getTime());
    this.rows.set(next.id, copy(next));
    track(() => {
      current.revokedAt = null;
      this.rows.delete(next.id);
    });
    return Promise.resolve(copy(next));
  }

  revoke(tokenId: string, at: Date, tx?: AgentTx): Promise<boolean> {
    const track = trackWrite(tx);
    const row = this.rows.get(tokenId);
    if (!row || row.revokedAt !== null) return Promise.resolve(false);
    row.revokedAt = new Date(at.getTime());
    track(() => {
      row.revokedAt = null;
    });
    return Promise.resolve(true);
  }

  revokeAllForAgent(agentId: string, at: Date, tx?: AgentTx): Promise<number> {
    const track = trackWrite(tx);
    const revoked: AgentRefreshTokenRecord[] = [];
    for (const row of this.rows.values()) {
      if (row.agentId === agentId && row.revokedAt === null) {
        row.revokedAt = new Date(at.getTime());
        revoked.push(row);
      }
    }
    track(() => {
      for (const row of revoked) row.revokedAt = null;
    });
    return Promise.resolve(revoked.length);
  }
}

export class FakeReferralAttributionRepository implements ReferralAttributionRepository {
  private readonly rows = new Map<string, ReferralAttributionRecord>();

  findByMemberId(memberId: string): Promise<ReferralAttributionRecord | null> {
    for (const row of this.rows.values()) {
      if (row.memberId === memberId) return Promise.resolve(copy(row));
    }
    return Promise.resolve(null);
  }

  listByAgent(agentId: string): Promise<ReferralAttributionRecord[]> {
    return Promise.resolve(
      [...this.rows.values()].filter((r) => r.agentId === agentId).map(copy),
    );
  }

  isPhoneHashCredited(phoneHash: string): Promise<boolean> {
    return Promise.resolve(
      [...this.rows.values()].some((r) => r.memberPhoneHash === phoneHash),
    );
  }

  create(
    attribution: ReferralAttributionRecord,
    tx?: AgentTx,
  ): Promise<ReferralAttributionRecord> {
    const track = trackWrite(tx);
    const rows = [...this.rows.values()];
    if (
      this.rows.has(attribution.id) ||
      rows.some((row) => row.memberId === attribution.memberId)
    ) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ATTRIBUTION'));
    }
    this.rows.set(attribution.id, copy(attribution));
    track(() => {
      this.rows.delete(attribution.id);
    });
    return Promise.resolve(copy(attribution));
  }
}

export class FakeAgentApplicantRepository implements AgentApplicantRepository {
  private readonly rows = new Map<string, AgentApplicantRecord>();

  save(record: AgentApplicantRecord, tx?: AgentTx): Promise<void> {
    const track = trackWrite(tx);
    const before = this.rows.get(record.phoneHash);
    this.rows.set(record.phoneHash, copy(record));
    track(() => {
      if (before) this.rows.set(record.phoneHash, before);
      else this.rows.delete(record.phoneHash);
    });
    return Promise.resolve();
  }

  find(phoneHash: string): Promise<AgentApplicantRecord | null> {
    const row = this.rows.get(phoneHash);
    return Promise.resolve(row ? copy(row) : null);
  }

  delete(phoneHash: string, tx?: AgentTx): Promise<void> {
    const track = trackWrite(tx);
    const before = this.rows.get(phoneHash);
    this.rows.delete(phoneHash);
    track(() => {
      if (before) this.rows.set(phoneHash, before);
    });
    return Promise.resolve();
  }
}

export class FakeAgentPayoutDetailsRepository implements AgentPayoutDetailsRepository {
  private readonly rows = new Map<string, AgentPayoutDetailsRecord>();

  find(agentId: string): Promise<AgentPayoutDetailsRecord | null> {
    const row = this.rows.get(agentId);
    return Promise.resolve(row ? copy(row) : null);
  }

  save(record: AgentPayoutDetailsRecord, tx?: AgentTx): Promise<void> {
    const track = trackWrite(tx);
    const before = this.rows.get(record.agentId);
    this.rows.set(record.agentId, copy(record));
    track(() => {
      if (before) this.rows.set(record.agentId, before);
      else this.rows.delete(record.agentId);
    });
    return Promise.resolve();
  }
}

type ViewFields = Omit<
  ReferralViewSource,
  'attributionId' | 'commissionStatus'
>;

export class FakeAgentMemberRead implements AgentMemberReadPort {
  private readonly members = new Map<string, AgentMemberSnapshot>();
  private readonly views = new Map<string, ViewFields>();

  add(member: AgentMemberSnapshot, view?: ViewFields): void {
    this.members.set(member.memberId, copy(member));
    if (view) this.views.set(member.memberId, copy(view));
  }

  getMember(memberId: string): Promise<AgentMemberSnapshot | null> {
    const member = this.members.get(memberId);
    return Promise.resolve(member ? copy(member) : null);
  }

  getReferralViewFields(memberId: string): Promise<ViewFields | null> {
    const view = this.views.get(memberId);
    return Promise.resolve(view ? copy(view) : null);
  }
}
