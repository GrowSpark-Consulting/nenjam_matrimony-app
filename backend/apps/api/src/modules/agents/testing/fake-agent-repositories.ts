/** In-memory repositories and member port. Tests only. */
import type { ReferralViewSource } from '../referral/agent-referral-view';
import {
  AgentConflictError,
  AgentMemberReadPort,
  AgentMemberSnapshot,
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

  create(agent: NewAgentRecord): Promise<AgentRecord> {
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
    return Promise.resolve(copy(row));
  }

  update(
    id: string,
    changes: Parameters<AgentRepository['update']>[1],
  ): Promise<AgentRecord> {
    const row = this.rows.get(id);
    if (!row) return Promise.reject(new Error(`Unknown agent ${id}`));
    Object.assign(row, changes);
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

  create(code: ReferralCodeRecord): Promise<ReferralCodeRecord> {
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
    return Promise.resolve(copy(code));
  }
}

export class FakeAgentRefreshTokenRepository implements AgentRefreshTokenRepository {
  private readonly rows = new Map<string, AgentRefreshTokenRecord>();

  create(token: AgentRefreshTokenRecord): Promise<AgentRefreshTokenRecord> {
    if (this.rows.has(token.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    this.rows.set(token.id, copy(token));
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
  ): Promise<AgentRefreshTokenRecord> {
    const current = this.rows.get(currentId);
    if (!current)
      return Promise.reject(new Error(`Unknown token ${currentId}`));
    if (current.revokedAt !== null) {
      return Promise.reject(new AgentConflictError('ALREADY_REVOKED'));
    }
    if (this.rows.has(next.id)) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ID'));
    }
    current.revokedAt = new Date(at.getTime());
    this.rows.set(next.id, copy(next));
    return Promise.resolve(copy(next));
  }

  revokeAllForAgent(agentId: string, at: Date): Promise<number> {
    let count = 0;
    for (const row of this.rows.values()) {
      if (row.agentId === agentId && row.revokedAt === null) {
        row.revokedAt = new Date(at.getTime());
        count += 1;
      }
    }
    return Promise.resolve(count);
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
  ): Promise<ReferralAttributionRecord> {
    const rows = [...this.rows.values()];
    if (
      this.rows.has(attribution.id) ||
      rows.some((row) => row.memberId === attribution.memberId)
    ) {
      return Promise.reject(new AgentConflictError('DUPLICATE_ATTRIBUTION'));
    }
    this.rows.set(attribution.id, copy(attribution));
    return Promise.resolve(copy(attribution));
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
