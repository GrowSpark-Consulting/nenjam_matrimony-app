/**
 * In-memory `AgentClientAccountPort`: member rows by phone, Firebase
 * accounts by phone, and minted custom tokens. Tests only.
 */
import {
  AgentConflictError,
  type AgentConflictReason,
} from '../ports/agent-data-ports';
import type {
  AgentClientAccountPort,
  AgentClientMember,
} from '../ports/agent-client-ports';
import type { ClientProfile } from '../clients/client-profile';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { trackWrite } from './fake-agent-unit-of-work';

interface FakeMember {
  memberId: string;
  firebaseUid: string | null;
  phoneE164: string;
  /** The profile her registration draft was made from, for members made by `createMember`. */
  profile: ClientProfile | null;
}

export class FakeAgentClientAccount implements AgentClientAccountPort {
  private readonly members = new Map<string, FakeMember>();
  private readonly firebaseUids = new Map<string, string>();
  private counter = 0;
  /** Calls made, for assertions. */
  readonly calls = { ensureFirebaseUser: 0, createMember: 0, mint: 0 };
  /** Make the next calls fail (Firebase down, a database error...). */
  failEnsure: Error | null = null;
  failMint: Error | null = null;
  failCreate: Error | null = null;

  /** Test helper: a member that already exists (an earlier signup). */
  addMember(
    memberId: string,
    phoneE164: string,
    firebaseUid: string | null = `uid-${memberId}`,
  ): void {
    this.members.set(memberId, {
      memberId,
      firebaseUid,
      phoneE164,
      profile: null,
    });
  }

  /** Test helper: the member row as stored. */
  member(memberId: string): FakeMember | undefined {
    const m = this.members.get(memberId);
    return m ? { ...m } : undefined;
  }

  /** Test helper: removes a member (an account deletion). */
  deleteMember(memberId: string): void {
    this.members.delete(memberId);
  }

  count(): number {
    return this.members.size;
  }

  findMemberByPhone(phoneE164: string): Promise<AgentClientMember | null> {
    for (const m of this.members.values()) {
      if (m.phoneE164 === phoneE164) {
        return Promise.resolve({
          memberId: m.memberId,
          firebaseUid: m.firebaseUid,
        });
      }
    }
    return Promise.resolve(null);
  }

  findMemberById(memberId: string): Promise<AgentClientMember | null> {
    const m = this.members.get(memberId);
    return Promise.resolve(
      m ? { memberId: m.memberId, firebaseUid: m.firebaseUid } : null,
    );
  }

  ensureFirebaseUser(phoneE164: string): Promise<{ uid: string }> {
    this.calls.ensureFirebaseUser += 1;
    if (this.failEnsure) return Promise.reject(this.failEnsure);
    let uid = this.firebaseUids.get(phoneE164);
    if (uid === undefined) {
      uid = `firebase-uid-${this.firebaseUids.size + 1}`;
      this.firebaseUids.set(phoneE164, uid);
    }
    return Promise.resolve({ uid });
  }

  createMember(
    input: { uid: string; phoneE164: string; profile: ClientProfile },
    tx: AgentTx,
  ): Promise<{ memberId: string }> {
    const track = trackWrite(tx);
    this.calls.createMember += 1;
    if (this.failCreate) return Promise.reject(this.failCreate);
    const reason: AgentConflictReason = 'DUPLICATE_MEMBER_PHONE';
    for (const m of this.members.values()) {
      if (m.phoneE164 === input.phoneE164 || m.firebaseUid === input.uid) {
        return Promise.reject(new AgentConflictError(reason));
      }
    }
    this.counter += 1;
    const memberId = `new-member-${this.counter}`;
    this.members.set(memberId, {
      memberId,
      firebaseUid: input.uid,
      phoneE164: input.phoneE164,
      profile: structuredClone(input.profile),
    });
    track(() => {
      this.members.delete(memberId);
    });
    return Promise.resolve({ memberId });
  }

  mintSessionToken(uid: string): Promise<string> {
    this.calls.mint += 1;
    if (this.failMint) return Promise.reject(this.failMint);
    return Promise.resolve(`custom-token-${uid}-${this.calls.mint}`);
  }
}
