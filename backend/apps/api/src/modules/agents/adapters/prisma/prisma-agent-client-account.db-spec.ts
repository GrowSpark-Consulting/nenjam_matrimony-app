/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * member account an accepted invitation creates, on a throwaway LOCAL
 * Postgres, read back the way the member app reads it (`GET /profiles/draft`
 * goes through `ProfileRepository.getOrCreateRegistrationStep`).
 */
import type { PrismaService } from '@app/database';
import { ProfileRepository } from '../../../profiles/repositories/profile.repository';
import { AgentConflictError } from '../../ports/agent-data-ports';
import { PrismaAgentClientAccount } from './prisma-agent-client-account';
import { PrismaAgentUnitOfWork } from './prisma-agent-unit-of-work';
import { openTestDatabase, freshTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());
beforeEach(() => freshTestDatabase(prisma));

const PHONE = '+919000000001';
const DETAILS = {
  firstName: 'Priya',
  lastName: 'Sundaram',
  gender: 'FEMALE' as const,
  dob: '1998-04-12',
  maritalStatus: 'NEVER_MARRIED' as const,
  profileCreatedFor: 'Daughter' as const,
};

const firebase = {
  findOrCreateUser: () => Promise.resolve({ uid: 'uid-1', created: true }),
  createCustomToken: () => Promise.resolve('custom-token'),
};
const account = () => new PrismaAgentClientAccount(prisma, firebase);
const uow = () => new PrismaAgentUnitOfWork(prisma);

const create = (uid = 'uid-1', phoneE164 = PHONE) =>
  uow().run((tx) =>
    account().createMember({ uid, phoneE164, basicDetails: DETAILS }, tx),
  );

describe('PrismaAgentClientAccount on the real database', () => {
  it('creates the member and her draft with step 1 done; the wizard resumes from it', async () => {
    const { memberId } = await create();
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: memberId },
    });
    expect(user).toMatchObject({
      firebaseUid: 'uid-1',
      phone: PHONE,
      email: 'uid-1@firebase.invalid',
      role: 'USER',
      status: 'PENDING_VERIFICATION',
    });
    const step = await new ProfileRepository(
      prisma as unknown as PrismaService,
    ).getOrCreateRegistrationStep(memberId);
    expect(step).toMatchObject({
      currentStep: 1,
      completedSteps: [1],
      isComplete: false,
      draftData: { basicDetails: DETAILS },
    });
  });

  it('finds members by phone and by id, whatever their role or status', async () => {
    await prisma.user.create({
      data: {
        id: 'staff-1',
        firebaseUid: 'fb-staff',
        email: 'staff@example.invalid',
        phone: '+919000000002',
        role: 'ADMIN',
        deletedAt: new Date(),
      },
    });
    expect(await account().findMemberByPhone('+919000000002')).toEqual({
      memberId: 'staff-1',
      firebaseUid: 'fb-staff',
    });
    expect(await account().findMemberById('staff-1')).toMatchObject({
      memberId: 'staff-1',
    });
    expect(await account().findMemberByPhone(PHONE)).toBeNull();
    expect(await account().findMemberById('nobody')).toBeNull();
  });

  it('a phone or a Firebase account that already has a member row is DUPLICATE_MEMBER_PHONE', async () => {
    await create();
    await expect(create('uid-2', PHONE)).rejects.toEqual(
      new AgentConflictError('DUPLICATE_MEMBER_PHONE'),
    );
    await expect(create('uid-1', '+919000000002')).rejects.toEqual(
      new AgentConflictError('DUPLICATE_MEMBER_PHONE'),
    );
  });

  it('a failed transaction leaves no member and no draft', async () => {
    await expect(
      uow().run(async (tx) => {
        await account().createMember(
          { uid: 'uid-1', phoneE164: PHONE, basicDetails: DETAILS },
          tx,
        );
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(await prisma.user.count()).toBe(0);
    expect(await prisma.registrationStep.count()).toBe(0);
  });
});
