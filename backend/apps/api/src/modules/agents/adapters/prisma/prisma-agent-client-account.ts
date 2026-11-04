/**
 * `AgentClientAccountPort`: the member account an accepted invitation
 * creates. The ONLY place agent code writes member data, and only these two
 * rows, in the accept transaction:
 *
 * - `users`: the Firebase uid, the verified phone, and the placeholder email
 *   every phone-only signup uses (`<uid>@firebase.invalid`, as the dummy-OTP
 *   session and FirebaseAuthGuard do). Role and status are the defaults of a
 *   new member.
 * - `registration_steps`: the wizard's draft holding every section the
 *   agent filled, under the wizard's own names (`toClientWizardDraft`),
 *   with those steps marked done: what saving each of them in the app
 *   writes (`ProfileRepository.mergeDraftSection`), so `GET /profiles/draft`
 *   resumes from it.
 *
 * The Firebase account is made BEFORE the transaction (`ensureFirebaseUser`,
 * idempotent by phone in `FirebaseService.findOrCreateUser`): if the
 * transaction then fails, the next attempt reuses it. A phone (or a uid)
 * that already has a member row is DUPLICATE_MEMBER_PHONE.
 *
 * Without Firebase Admin credentials, `FirebaseService` throws "not
 * configured"; that is reported as AgentConfigError (503
 * AGENT_PROGRAM_UNAVAILABLE), not as a 500.
 */
import { InternalServerErrorException } from '@nestjs/common';
import type { Prisma, PrismaClient } from '@app/database';
import type { FirebaseService } from '@app/firebase';
import { AgentConfigError } from '../../config/agent-config.service';
import type {
  AgentClientAccountPort,
  AgentClientMember,
} from '../../ports/agent-client-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import {
  toClientWizardDraft,
  type ClientProfile,
} from '../../clients/client-profile';
import { dbFor, unwrapTx } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const CLIENT_MEMBER_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  {
    constraint: 'users_phone_key',
    fields: ['phone'],
    reason: 'DUPLICATE_MEMBER_PHONE',
  },
  {
    constraint: 'users_firebase_uid_key',
    fields: ['firebase_uid'],
    reason: 'DUPLICATE_MEMBER_PHONE',
  },
  // The placeholder email is made from the uid: the same account.
  {
    constraint: 'users_email_key',
    fields: ['email'],
    reason: 'DUPLICATE_MEMBER_PHONE',
  },
];

/** What `FirebaseService` says when its credentials are missing. */
const NOT_CONFIGURED = /not configured/i;
const FIREBASE_SOURCE = 'Firebase Admin credentials (FIREBASE_*)';

async function firebaseCall<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (
      error instanceof InternalServerErrorException &&
      NOT_CONFIGURED.test(error.message)
    ) {
      throw new AgentConfigError([FIREBASE_SOURCE]);
    }
    throw error;
  }
}

export class PrismaAgentClientAccount implements AgentClientAccountPort {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly firebase: Pick<
      FirebaseService,
      'findOrCreateUser' | 'createCustomToken'
    >,
  ) {}

  async findMemberByPhone(
    phoneE164: string,
    tx?: AgentTx,
  ): Promise<AgentClientMember | null> {
    // Any row: staff, suspended and soft-deleted members all hold the phone.
    const row = await dbFor(this.prisma, tx).user.findUnique({
      where: { phone: phoneE164 },
      select: { id: true, firebaseUid: true },
    });
    return row ? { memberId: row.id, firebaseUid: row.firebaseUid } : null;
  }

  async findMemberById(
    memberId: string,
    tx?: AgentTx,
  ): Promise<AgentClientMember | null> {
    const row = await dbFor(this.prisma, tx).user.findUnique({
      where: { id: memberId },
      select: { id: true, firebaseUid: true },
    });
    return row ? { memberId: row.id, firebaseUid: row.firebaseUid } : null;
  }

  async ensureFirebaseUser(phoneE164: string): Promise<{ uid: string }> {
    const { uid } = await firebaseCall(() =>
      this.firebase.findOrCreateUser({ phone: phoneE164 }),
    );
    return { uid };
  }

  createMember(
    input: { uid: string; phoneE164: string; profile: ClientProfile },
    tx: AgentTx,
  ): Promise<{ memberId: string }> {
    const db = unwrapTx(tx);
    return withConflictMapping(CLIENT_MEMBER_UNIQUE_RULES, async () => {
      const user = await db.user.create({
        data: {
          firebaseUid: input.uid,
          phone: input.phoneE164,
          email: `${input.uid}@firebase.invalid`,
        },
        select: { id: true },
      });
      const draft = toClientWizardDraft(input.profile);
      await db.registrationStep.create({
        data: {
          userId: user.id,
          draftData: draft.draftData as Prisma.InputJsonValue,
          completedSteps: draft.completedSteps,
          currentStep: draft.currentStep,
        },
      });
      return { memberId: user.id };
    });
  }

  mintSessionToken(uid: string): Promise<string> {
    return firebaseCall(() => this.firebase.createCustomToken(uid));
  }
}
