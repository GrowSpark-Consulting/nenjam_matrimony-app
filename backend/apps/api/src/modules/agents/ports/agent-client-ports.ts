/**
 * Ports for agent-added clients ("Way 2"): the client drafts, the pointer to
 * the newest one-time code sent to a client's phone, the proof that a client
 * holds her phone, and the member account an accepted invitation creates.
 *
 * Domain shapes, not Prisma shapes (the Prisma adapters map them). Every
 * method takes the optional `tx` of `AgentUnitOfWork`, as in
 * `agent-data-ports.ts`.
 *
 * The table enforces most rules itself (migration 20261103090000): one open
 * draft per agent and phone, the allowed status changes, nothing editable
 * after submit, a closed draft never changing, only a DRAFT deleted. The
 * repositories below only ever ask for changes those rules allow, and the
 * conditional writes (`updateDetails`, `submit`, `discard`, `markRejected`,
 * the expiry) say whether the row was still in the expected state instead of
 * failing, so a service can answer a lost race with a clean refusal.
 *
 * PII. The phone and the details are stored sealed (purposes
 * `agent.client_phone` and `agent.client_details`) and looked up by the
 * peppered phone hash. Lookups take EVERY active hash of the phone
 * (`AgentIdentifierHasher.hashAll`), so a draft stored under an older pepper
 * is still found during a rotation; a new row is written under the newest.
 */
import type { ClientProfile } from '../clients/client-profile';
import type { AgentTx } from './agent-unit-of-work.port';

export type ClientDraftStatus =
  'DRAFT' | 'WAITING_FOR_CLIENT' | 'ACCEPTED' | 'REJECTED' | 'EXPIRED';

export const CLIENT_DRAFT_STATUSES: readonly ClientDraftStatus[] = [
  'DRAFT',
  'WAITING_FOR_CLIENT',
  'ACCEPTED',
  'REJECTED',
  'EXPIRED',
];

/** Open: it takes one of the agent's slots, and that agent cannot add the phone again. */
export const OPEN_CLIENT_DRAFT_STATUSES: readonly ClientDraftStatus[] = [
  'DRAFT',
  'WAITING_FOR_CLIENT',
];

/** Why an EXPIRED draft closed. Internal: never shown to the agent. */
export type ClientDraftClosedReason =
  | 'TIMED_OUT'
  | 'CLIENT_ACCEPTED_ANOTHER'
  | 'CLIENT_ALREADY_MEMBER'
  | 'AGENT_TERMINATED';

export interface AgentClientDraftRecord {
  id: string;
  agentId: string;
  status: ClientDraftStatus;
  /** The newest-pepper hash of the client's phone when the draft was made. */
  phoneHash: string;
  /** Sealed (`agent.client_phone`). Set while open and on REJECTED, else null. */
  phoneSealed: string | null;
  /** "+91 98***210". */
  phoneMasked: string;
  /** "Priya S.". */
  displayName: string;
  /** Sealed JSON of the `ClientProfile` (`agent.client_details`). Set only while open. */
  detailsSealed: string | null;
  expiresAt: Date;
  submittedAt: Date | null;
  acceptedAt: Date | null;
  closedAt: Date | null;
  closedReason: ClientDraftClosedReason | null;
  /** The member an accepted draft created; null once she deletes her account. */
  memberId: string | null;
  /** The attribution an accepted draft created. */
  attributionId: string | null;
  createdAt: Date;
}

/** What `create` stores: always a DRAFT. */
export type NewAgentClientDraft = Pick<
  AgentClientDraftRecord,
  | 'id'
  | 'agentId'
  | 'phoneHash'
  | 'phoneSealed'
  | 'phoneMasked'
  | 'displayName'
  | 'detailsSealed'
  | 'expiresAt'
  | 'createdAt'
> & { phoneSealed: string; detailsSealed: string };

/** Position in the newest-first order: (createdAt, id), both descending. */
export interface ClientDraftPageCursor {
  at: Date;
  id: string;
}

/**
 * Filter of the agent's list by the status the agent SEES: an open draft
 * whose `expiresAt` has passed is EXPIRED even before the daily job records
 * it, so the filter needs `now`.
 */
export interface ClientDraftListFilter {
  status?: ClientDraftStatus;
  now: Date;
}

export interface AgentClientDraftRepository {
  /** Throws AgentConflictError DUPLICATE_OPEN_CLIENT_DRAFT (one open per agent and phone) or DUPLICATE_ID. */
  create(
    draft: NewAgentClientDraft,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord>;
  /** Null when unknown OR another agent's (the two look the same). */
  findByIdForAgent(
    id: string,
    agentId: string,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /** Newest first, ordered by (createdAt, id) descending, strictly after `after`. */
  listPageByAgent(
    agentId: string,
    filter: ClientDraftListFilter,
    page: { limit: number; after?: ClientDraftPageCursor },
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord[]>;
  /** The agent's open drafts (DRAFT and WAITING_FOR_CLIENT), expired or not. */
  countOpen(agentId: string, tx?: AgentTx): Promise<number>;
  /**
   * Locks the agent's row until the transaction ends (SELECT ... FOR
   * UPDATE), so two creates for one agent are counted one after the other.
   * Needs a `tx`.
   */
  lockAgent(agentId: string, tx: AgentTx): Promise<void>;
  /** The agent's open draft for any of these phone hashes, or null. */
  findOpenByAgentAndHashes(
    agentId: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /** True when a client with any of these phone hashes rejected this agent. */
  wasRejectedBy(
    agentId: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<boolean>;
  /**
   * Replaces the details while the draft is still the agent's DRAFT and has
   * not run out; null otherwise (unknown, another agent's, submitted, closed
   * or past `expiresAt`).
   */
  updateDetails(
    id: string,
    agentId: string,
    changes: { displayName: string; detailsSealed: string },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /** DRAFT -> WAITING_FOR_CLIENT under the same conditions as `updateDetails`; null otherwise. */
  submit(
    id: string,
    agentId: string,
    changes: { submittedAt: Date; expiresAt: Date },
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /** Deletes the agent's DRAFT (any expiry); false when there was none. */
  discard(id: string, agentId: string, tx?: AgentTx): Promise<boolean>;
  /** The draft with this id whose phone is one of these hashes, in any status, or null. */
  findForPhone(
    id: string,
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /** The waiting drafts for these phone hashes that have not run out, oldest first. */
  listWaitingForHashes(
    phoneHashes: readonly string[],
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord[]>;
  /**
   * Locks, until the transaction ends, this draft AND every open draft for
   * these phone hashes (any agent), always in id order; then returns this
   * draft if it is WAITING_FOR_CLIENT, for one of these hashes and not past
   * `expiresAt`, else null. Accept starts with this: an accept, a reject and
   * the expiry of one draft can never all win, and two accepts for one phone
   * (two agents' invitations) wait for each other instead of deadlocking on
   * the member's phone. Needs a `tx`.
   */
  lockWaitingForAccept(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /**
   * WAITING_FOR_CLIENT -> ACCEPTED, linking the member and the attribution
   * and deleting the sealed phone and details. Only after
   * `lockWaitingForAccept` in the same `tx`.
   */
  markAccepted(
    id: string,
    changes: { memberId: string; attributionId: string; acceptedAt: Date },
    tx: AgentTx,
  ): Promise<AgentClientDraftRecord>;
  /**
   * WAITING_FOR_CLIENT -> REJECTED while for one of these hashes and not
   * past `expiresAt`. Deletes the details, KEEPS the sealed phone (the
   * lasting "never again" block). Null when it was not waiting.
   */
  markRejected(
    id: string,
    phoneHashes: readonly string[],
    now: Date,
    tx?: AgentTx,
  ): Promise<AgentClientDraftRecord | null>;
  /**
   * Closes one open draft as EXPIRED with `reason` (deleting its sealed
   * phone and details); false when it was no longer open.
   */
  close(
    id: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<boolean>;
  /**
   * Closes every OTHER open draft for these phone hashes (any agent) as
   * EXPIRED with `reason`. Returns the ids it closed.
   */
  closeOthersForPhone(
    phoneHashes: readonly string[],
    exceptId: string,
    reason: ClientDraftClosedReason,
    now: Date,
    tx?: AgentTx,
  ): Promise<string[]>;
  /**
   * Closes up to `limit` open drafts of this agent (or of every agent, when
   * `agentId` is null) whose `expiresAt` is at or before `now`, as EXPIRED
   * TIMED_OUT. Returns the ids it closed, oldest expiry first.
   */
  expireDue(
    agentId: string | null,
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]>;
  /**
   * Closes up to `limit` open drafts whose agent is TERMINATED, as EXPIRED
   * AGENT_TERMINATED. Returns the ids it closed.
   */
  closeOfTerminatedAgents(
    now: Date,
    limit: number,
    tx?: AgentTx,
  ): Promise<string[]>;
}

/** The newest one-time code sent to a client's phone (one row per phone hash). */
export interface AgentClientConsentCodeRecord {
  phoneHash: string;
  challengeId: string;
  expiresAt: Date;
}

export interface AgentClientConsentCodeStore {
  /** Insert or replace the pointer for this phone hash. */
  save(record: AgentClientConsentCodeRecord, tx?: AgentTx): Promise<void>;
  /** The pointer for the first of these hashes that has one (any expiry), or null. */
  find(
    phoneHashes: readonly string[],
    tx?: AgentTx,
  ): Promise<AgentClientConsentCodeRecord | null>;
  /** Deletes the pointers of these hashes. */
  delete(phoneHashes: readonly string[], tx?: AgentTx): Promise<void>;
  /** Deletes up to `limit` pointers expired before `before`; returns how many. */
  purgeExpired(before: Date, limit: number, tx?: AgentTx): Promise<number>;
}

// --- Proof that the client holds her phone ----------------------------------

/**
 * What the client presents. Only CODE is implemented: the one-time code of
 * `OtpService` (purpose AGENT_CLIENT_CONSENT). FIREBASE_ID_TOKEN is the real
 * end state (Firebase phone sign-in) and is one adapter away.
 */
export type ClientPhoneProof =
  | { kind: 'CODE'; phoneE164: string; code: string }
  | { kind: 'FIREBASE_ID_TOKEN'; idToken: string };

export type ClientPhoneProofFailure =
  | 'NOT_FOUND'
  | 'EXPIRED'
  | 'ALREADY_USED'
  | 'INVALID_CODE'
  | 'TOO_MANY_ATTEMPTS'
  | 'UNSUPPORTED';

export type ClientPhoneProofResult =
  | { ok: true; phoneE164: string }
  | { ok: false; reason: ClientPhoneProofFailure };

/**
 * The swap point between the test (dummy) code and real SMS.
 *
 * `canReach` says whether a code can reach this phone at all. With the
 * dummy code that is ONLY an explicitly approved test number, in every
 * environment. `send` rejects with AgentServiceError OTP_DELIVERY_UNAVAILABLE
 * for a phone it cannot reach and with `AgentOtpRateLimitError` when asked
 * too often; it remembers the newest code per phone. `verify` never throws
 * for a wrong code, phone or proof.
 */
export interface ClientPhoneProofPort {
  canReach(phoneE164: string): boolean;
  send(phoneE164: string): Promise<{ expiresAt: Date }>;
  verify(proof: ClientPhoneProof): Promise<ClientPhoneProofResult>;
}

// --- The member account an accepted invitation creates ---------------------

export interface AgentClientMember {
  memberId: string;
  /** Null for a row that has no Firebase account any more. */
  firebaseUid: string | null;
}

/**
 * Member accounts, for Way 2 only: is this phone already a member (staff and
 * deleted rows included), make the Firebase account, create the member row
 * with her registration draft, and mint the Firebase custom token she signs
 * in with.
 */
export interface AgentClientAccountPort {
  findMemberByPhone(
    phoneE164: string,
    tx?: AgentTx,
  ): Promise<AgentClientMember | null>;
  /** The member with this id, or null when she is gone. */
  findMemberById(
    memberId: string,
    tx?: AgentTx,
  ): Promise<AgentClientMember | null>;
  /** The Firebase account for the phone, created if needed. Safe to retry. Not in a transaction. */
  ensureFirebaseUser(phoneE164: string): Promise<{ uid: string }>;
  /**
   * Creates the member row and her registration draft holding every section
   * of the profile the agent filled (`toClientWizardDraft`). Throws
   * AgentConflictError DUPLICATE_MEMBER_PHONE when the phone or the Firebase
   * account already has a member row.
   */
  createMember(
    input: { uid: string; phoneE164: string; profile: ClientProfile },
    tx: AgentTx,
  ): Promise<{ memberId: string }>;
  /** A Firebase custom token for `signInWithCustomToken`. */
  mintSessionToken(uid: string): Promise<string>;
}

/**
 * The member profile (`user_profiles`) of an accepted client, made from the
 * registration draft accept wrote, exactly as a member's own registration
 * save makes it, so the member app opens the home page and not the
 * registration wizard. Not in a transaction: it runs after accept commits.
 */
export interface AgentClientMemberProfilePort {
  /** Whether the member already has her profile row. */
  exists(memberId: string): Promise<boolean>;
  /**
   * Makes it from her registration draft. Throws when it fails; makes
   * nothing (and does not throw) when the draft lacks what a member's own
   * save would need, which `exists` then shows.
   */
  createFromDraft(memberId: string): Promise<void>;
}

// --- Master data for the client profile ---------------------------------------

/**
 * Checks the master-data codes of a client profile (religion, community,
 * country, state, city) exactly as the member's own profile save does, and
 * fills in their labels, so the profile holds both, as the wizard does.
 * A code that is unknown, or does not belong to its parent (a city outside
 * its state, a community outside its religion), or a child without its
 * parent code, is refused naming its section.
 */
export interface ClientReferenceDataPort {
  withLabels(
    profile: ClientProfile,
  ): Promise<
    { ok: true; profile: ClientProfile } | { ok: false; fields: string[] }
  >;
}
