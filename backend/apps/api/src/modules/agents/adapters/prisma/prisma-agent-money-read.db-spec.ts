/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * money-route adapters against a throwaway LOCAL Postgres.
 *
 * Test data only: the approved fake phones and a reserved, non-routable
 * email domain (example.invalid) for the one email column that is required.
 */
import {
  PrismaAgentCommissionDisplay,
  PrismaAgentDeviceRepository,
} from './prisma-agent-money-read';
import { PrismaAgentRepository } from './prisma-agent.repository';
import { PrismaReferralAttributionRepository } from './prisma-referral-attribution.repository';
import { freshTestDatabase, openTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());
beforeEach(() => freshTestDatabase(prisma));

const display = new PrismaAgentCommissionDisplay(prisma);
const devices = new PrismaAgentDeviceRepository(prisma);
const agents = new PrismaAgentRepository(prisma);
const attributions = new PrismaReferralAttributionRepository(prisma);

const T0 = new Date('2026-10-29T09:00:00.000Z');
const FCM = 'f'.repeat(40);

async function seedAgent(id: string, phone: string) {
  await agents.create({
    id,
    phoneHash: `v1:hash-${id}`,
    phoneE164: phone,
    name: 'Ravi Kumar',
    city: 'Madurai',
    state: 'Tamil Nadu',
    panLast4: null,
    panSealed: null,
    createdAt: T0,
  });
}

/** A member with a profile, a GOLD subscription and one payment. */
async function seedMemberWithPayment(n: number, lastName = 'Sharma') {
  const user = await prisma.user.create({
    data: {
      firebaseUid: `test-firebase-uid-${n}`,
      email: `test-member-${n}@example.invalid`,
    },
  });
  await prisma.userProfile.create({
    data: {
      userId: user.id,
      firstName: 'Priya',
      lastName,
      dob: new Date('1996-05-01T00:00:00.000Z'),
      gender: 'FEMALE',
      religion: 'Hindu',
      currentCity: 'Madurai',
      currentState: 'Tamil Nadu',
    },
  });
  const plan = await prisma.subscriptionPlan.upsert({
    where: { name: 'GOLD' },
    create: {
      name: 'GOLD',
      displayName: 'Gold',
      priceInr: 999,
      durationDays: 90,
    },
    update: {},
  });
  const subscription = await prisma.userSubscription.create({
    data: {
      userId: user.id,
      planId: plan.id,
      startDate: T0,
      endDate: new Date(T0.getTime() + 90 * 86_400_000),
    },
  });
  const payment = await prisma.paymentTransaction.create({
    data: {
      userId: user.id,
      subscriptionId: subscription.id,
      amountInr: 999,
    },
  });
  return { userId: user.id, paymentId: payment.id, planName: plan.displayName };
}

async function seedAttribution(id: string, memberId: string | null, n: number) {
  await attributions.create({
    id,
    memberId,
    agentId: 'agent-1',
    codeId: null,
    source: 'CODE_AT_SIGNUP',
    memberPhoneHash: `v1:member-hash-${n}`,
    attributedAt: T0,
    status: 'ACTIVE',
    windowEndsAt: T0,
    needsReview: false,
  });
}

describe('PrismaAgentCommissionDisplay', () => {
  beforeEach(() => seedAgent('agent-1', '+919000000001'));

  it('gives the short member name and the plan name per commission', async () => {
    const one = await seedMemberWithPayment(1);
    const two = await seedMemberWithPayment(2, '');
    await seedAttribution('attr-1', one.userId, 1);
    await seedAttribution('attr-2', two.userId, 2);
    const shown = await display.describe([
      { id: 'c-1', paymentId: one.paymentId, attributionId: 'attr-1' },
      { id: 'c-2', paymentId: two.paymentId, attributionId: 'attr-2' },
    ]);
    expect(Object.fromEntries(shown)).toEqual({
      'c-1': { referralDisplayName: 'Priya S.', planName: one.planName },
      'c-2': { referralDisplayName: 'Priya', planName: two.planName },
    });
  });

  it('leaves out a commission whose member is gone or whose payment is unknown', async () => {
    const one = await seedMemberWithPayment(1);
    await seedAttribution('attr-1', one.userId, 1);
    await seedAttribution('attr-gone', null, 2);
    const shown = await display.describe([
      { id: 'c-gone', paymentId: one.paymentId, attributionId: 'attr-gone' },
      {
        id: 'c-nopay',
        paymentId: '00000000-0000-4000-8000-000000000000',
        attributionId: 'attr-1',
      },
    ]);
    expect(shown.size).toBe(0);
  });

  it('answers an empty list without a query', async () => {
    expect((await display.describe([])).size).toBe(0);
  });
});

describe('PrismaAgentDeviceRepository', () => {
  beforeEach(async () => {
    await seedAgent('agent-1', '+919000000001');
    await seedAgent('agent-2', '+919000000002');
  });

  it('stores a device, and registering again changes nothing', async () => {
    await devices.register({
      agentId: 'agent-1',
      fcmToken: FCM,
      platform: 'ANDROID',
    });
    await devices.register({
      agentId: 'agent-1',
      fcmToken: FCM,
      platform: 'ANDROID',
    });
    const rows = await prisma.agentDeviceToken.findMany();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      agentId: 'agent-1',
      fcmToken: FCM,
      platform: 'ANDROID',
      isActive: true,
    });
  });

  it('a token held by another agent moves to the caller, and is active again', async () => {
    await devices.register({
      agentId: 'agent-2',
      fcmToken: FCM,
      platform: 'IOS',
    });
    await prisma.agentDeviceToken.update({
      where: { fcmToken: FCM },
      data: { isActive: false },
    });
    await devices.register({
      agentId: 'agent-1',
      fcmToken: FCM,
      platform: 'ANDROID',
    });
    const rows = await prisma.agentDeviceToken.findMany();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      agentId: 'agent-1',
      platform: 'ANDROID',
      isActive: true,
    });
  });
});
