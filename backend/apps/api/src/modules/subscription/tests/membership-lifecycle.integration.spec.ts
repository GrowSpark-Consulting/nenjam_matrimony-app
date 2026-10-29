import {
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import {
  expireLapsedSubscriptions,
  type PrismaClient,
  type PrismaService,
} from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { MembershipRepository } from '../../entitlements/repositories/membership.repository';
import { UsageRepository } from '../../entitlements/repositories/usage.repository';
import {
  MembershipService,
  shadowFeatureKey,
} from '../../entitlements/services/membership.service';
import { SubscriptionRepository } from '../repositories/subscription.repository';
import { SubscriptionLifecycleService } from '../services/subscription-lifecycle.service';
import { PlanCatalogAdminService } from '../services/plan-catalog-admin.service';
import { CheckoutService } from '../services/checkout.service';
import { RazorpayWebhookService } from '../services/razorpay-webhook.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { PaymentEventDispatcher } from '../events/payment-event-outbox';
import { ReferralEventBus } from '../events/referral-event-bus';

/**
 * The subscription lifecycle against a real Postgres: payments confirmed
 * concurrently, duplicate webhooks, failures, refunds, upgrades/downgrades,
 * expiry, cancellation and catalogue changes — the state transitions whose
 * safety rests on the database's own conditional updates and constraints.
 *
 * Razorpay itself is the only stand-in (order creation); every service,
 * repository and table is real. Run with INTEGRATION_DATABASE_URL pointing at
 * a throwaway schema with every migration applied.
 */
describeIntegration('membership lifecycle', () => {
  jest.setTimeout(60_000);
  let prisma: PrismaClient;
  let membership: MembershipService;
  let lifecycle: SubscriptionLifecycleService;
  let admin: PlanCatalogAdminService;
  let checkout: CheckoutService;
  let webhooks: RazorpayWebhookService;
  let catalog: PlanCatalogService;
  let orderSeq = 0;

  // Admin actors, as real users: the services verify status, an active
  // AdminAccount and a role granting the permission themselves.
  const ADMIN = 'mbr-life-admin'; // subscriptions + membership
  const SUBS_ADMIN = 'mbr-life-subs-admin'; // like the seeded admin
  const SUSPENDED_ADMIN = 'mbr-life-suspended-admin';
  const NOT_ADMIN = 'mbr-life-not-admin';
  const LEGACY_ADMIN = 'mbr-life-legacy-admin'; // like the old seeded placeholder
  const ACTORS = [ADMIN, SUBS_ADMIN, SUSPENDED_ADMIN, NOT_ADMIN, LEGACY_ADMIN];
  const SUBS_ROLE = 'ITEST_MBR_SUBSCRIPTIONS';
  const USERS = [
    'mbr-life-a',
    'mbr-life-b',
    'mbr-life-c',
    'mbr-life-d',
    'mbr-life-e',
  ];
  const [A, B, C, D, E] = USERS;
  const DAY = 24 * 3600 * 1000;

  async function buy(
    userId: string,
    planCode: 'GOLD' | 'PLATINUM',
    months = 3,
  ) {
    return checkout.start(userId, { planCode, months });
  }

  /** Confirms as a correct webhook would: the captured amount is the order's. */
  async function confirm(orderId: string, paymentId = `pay_${orderId}`) {
    const { amountInr } = await prisma.paymentTransaction.findUniqueOrThrow({
      where: { razorpayOrderId: orderId },
    });
    return prisma.$transaction((tx) =>
      lifecycle.confirmPayment(tx, {
        orderId,
        paymentId,
        amountInPaise: amountInr,
        currency: 'INR',
        actorId: null,
        via: 'WEBHOOK',
      }),
    );
  }

  /** A role holding exactly [keys], created for this suite. */
  async function ensureRole(key: string, keys: string[]) {
    const role = await prisma.role.upsert({
      where: { key },
      create: { key, name: key },
      update: {},
    });
    const permissions = await prisma.permission.findMany({
      where: { key: { in: keys } },
    });
    expect(permissions).toHaveLength(keys.length);
    await prisma.rolePermission.createMany({
      data: permissions.map((p) => ({ roleId: role.id, permissionId: p.id })),
      skipDuplicates: true,
    });
    return role;
  }

  async function createActor(
    id: string,
    over: {
      role?: 'ADMIN' | 'USER';
      status?: 'ACTIVE' | 'SUSPENDED';
      /** Role keys held through an active AdminAccount. */
      roles?: string[];
      /** An AdminAccount that was never provisioned: inactive, with only the
       *  legacy JSON grants the old seeder wrote. */
      legacyJsonOnly?: boolean;
    },
  ) {
    await prisma.user.create({
      data: {
        id,
        firebaseUid: `fb-${id}`,
        email: `${id}@example.com`,
        role: over.role ?? 'ADMIN',
        status: over.status ?? 'ACTIVE',
        ...(over.legacyJsonOnly && {
          adminAccount: {
            create: {
              permissions: {
                subscriptions: ['read', 'write', 'cancel'],
                membership: ['plans.write', 'prices.write'],
              },
            },
          },
        }),
        ...(over.roles && {
          adminAccount: {
            create: {
              isActive: true,
              roles: {
                create: (
                  await prisma.role.findMany({
                    where: { key: { in: over.roles } },
                  })
                ).map((r) => ({ roleId: r.id })),
              },
            },
          },
        }),
      },
    });
  }

  async function planOf(userId: string) {
    return (await membership.resolve(userId)).plan?.code;
  }

  beforeAll(async () => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    prisma = await connectIsolatedPrisma();
    const db = prisma as unknown as PrismaService;
    catalog = new PlanCatalogService(db);
    const subscriptions = new SubscriptionRepository(db);
    membership = new MembershipService(
      db,
      catalog,
      new MembershipRepository(db),
      new UsageRepository(db),
      { membership: { enforcementMode: 'enforce' } } as never,
    );
    lifecycle = new SubscriptionLifecycleService(db, subscriptions, catalog);
    admin = new PlanCatalogAdminService(db, catalog, subscriptions);
    const razorpay = {
      publicKeyId: () => 'rzp_test_key',
      isLiveMode: () => false,
      createOrder: (input: { amountInPaise: number; currency: string }) =>
        Promise.resolve({
          id: `order_itest_${Date.now()}_${++orderSeq}`,
          amount: input.amountInPaise,
          currency: input.currency,
        }),
    };
    const hasher = new IdentifierHashService({
      identifierHash: { peppers: `v1:${'k'.repeat(32)}` },
    } as never);
    // No subscriber here: events stay in the outbox for the tests to read.
    const dispatcher = new PaymentEventDispatcher(db, new ReferralEventBus());
    checkout = new CheckoutService(
      db,
      catalog,
      razorpay as never,
      lifecycle,
      subscriptions,
      new PlatformSettingsService(db),
      hasher,
      dispatcher,
    );
    webhooks = new RazorpayWebhookService(db, lifecycle, dispatcher, hasher);

    await prisma.user.deleteMany({ where: { id: { in: ACTORS } } });
    await ensureRole(SUBS_ROLE, [
      'subscription.grant',
      'subscription.extend',
      'subscription.cancel',
    ]);
    await createActor(ADMIN, { roles: ['SUPER_ADMIN'] });
    await createActor(SUBS_ADMIN, { roles: [SUBS_ROLE] });
    await createActor(SUSPENDED_ADMIN, {
      status: 'SUSPENDED',
      roles: ['SUPER_ADMIN'],
    });
    await createActor(NOT_ADMIN, { role: 'USER' });
    await createActor(LEGACY_ADMIN, { legacyJsonOnly: true });

    // Put Gold and Platinum on sale (the shipped catalogue is unpriced).
    for (const [planCode, months, price] of [
      ['GOLD', 3, 399_900],
      ['GOLD', 6, 699_900],
      ['PLATINUM', 3, 799_900],
    ] as const) {
      await admin.setDuration({
        planCode,
        months,
        priceInPaise: price,
        isActive: true,
        actorId: ADMIN,
        reason: 'integration test pricing',
      });
    }
  });

  beforeEach(async () => {
    await prisma.paymentEventOutbox.deleteMany({});
    await prisma.paymentTransaction.deleteMany({
      where: { userId: { in: USERS } },
    });
    await prisma.user.deleteMany({ where: { id: { in: USERS } } });
    for (const id of USERS) {
      await prisma.user.create({
        data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.com` },
      });
    }
  });

  afterAll(async () => {
    await prisma?.paymentTransaction.deleteMany({
      where: { userId: { in: USERS } },
    });
    await prisma?.user.deleteMany({
      where: { id: { in: [...USERS, ...ACTORS] } },
    });
    await prisma?.role.deleteMany({ where: { key: SUBS_ROLE } });
    await prisma?.$disconnect();
  });

  it('grants nothing while a checkout is PENDING, then activates exactly once under racing confirmations', async () => {
    const order = await buy(A, 'GOLD');
    expect(await planOf(A)).toBe('FREE');

    const outcomes = await Promise.all(
      Array.from({ length: 6 }, () => confirm(order.orderId, 'pay_race')),
    );
    expect(outcomes.filter((o) => o === 'ACTIVATED')).toHaveLength(1);
    expect(outcomes.filter((o) => o === 'ALREADY_APPLIED')).toHaveLength(5);

    expect(await planOf(A)).toBe('GOLD');
    expect(
      await prisma.subscriptionEvent.count({
        where: { userId: A, type: 'ACTIVATED' },
      }),
    ).toBe(1);
    const payment = await prisma.paymentTransaction.findFirst({
      where: { userId: A },
    });
    expect(payment).toMatchObject({
      status: 'SUCCESS',
      razorpayPaymentId: 'pay_race',
      amountInr: 399_900,
    });
  });

  it('applies a redelivered webhook once, even when the deliveries race', async () => {
    const order = await buy(B, 'GOLD');
    const body = {
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: 'pay_wh',
            order_id: order.orderId,
            amount: 399_900,
            currency: 'INR',
          },
        },
      },
    };
    const raw = Buffer.from(JSON.stringify(body));
    const eventId = `evt_${order.orderId}`;
    const results = await Promise.allSettled(
      Array.from({ length: 4 }, () => webhooks.handle(eventId, body, raw)),
    );
    const statuses = results.map((r) =>
      r.status === 'fulfilled' ? r.value.status : 'ERROR',
    );
    // One applies it; the rest see the id taken (DUPLICATE) — or, if they
    // collided mid-insert, fail and would be retried as a DUPLICATE.
    expect(statuses.filter((s) => s === 'PROCESSED')).toHaveLength(1);
    expect(await planOf(B)).toBe('GOLD');
    expect(
      await prisma.paymentWebhookEvent.count({
        where: { provider: 'RAZORPAY', eventId },
      }),
    ).toBe(1);
    expect(await webhooks.handle(eventId, body, raw)).toEqual({
      status: 'DUPLICATE',
    });
    expect(
      await prisma.subscriptionEvent.count({
        where: { userId: B, type: 'ACTIVATED' },
      }),
    ).toBe(1);
  });

  it('never activates on an amount mismatch — not even via the client verify path afterwards', async () => {
    const order = await buy(C, 'GOLD');
    const body = {
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: 'pay_bad',
            order_id: order.orderId,
            amount: 100,
            currency: 'INR',
          },
        },
      },
    };
    const raw = Buffer.from(JSON.stringify(body));
    expect(
      await webhooks.handle(`evt_bad_${order.orderId}`, body, raw),
    ).toEqual({
      status: 'PROCESSED',
      detail: 'AMOUNT_MISMATCH',
    });
    expect(
      await prisma.$transaction((tx) =>
        lifecycle.confirmPayment(tx, {
          orderId: order.orderId,
          paymentId: 'pay_bad',
          // Even a later confirmation carrying the RIGHT amount can't revive
          // a purchase flagged for a mismatch.
          amountInPaise: order.amountInPaise,
          currency: 'INR',
          actorId: C,
          via: 'CHECKOUT_VERIFY',
        }),
      ),
    ).toBe('ALREADY_APPLIED');
    expect(await planOf(C)).toBe('FREE');
    expect(
      await prisma.paymentTransaction.findFirst({ where: { userId: C } }),
    ).toMatchObject({
      status: 'FAILED',
      failureReason: 'AMOUNT_MISMATCH',
    });
  });

  it('records a failed payment without granting anything, and still activates a successful retry', async () => {
    const order = await buy(D, 'GOLD');
    await prisma.$transaction((tx) =>
      lifecycle.recordPaymentFailure(tx, {
        orderId: order.orderId,
        paymentId: 'pay_1',
        reason: 'Card declined',
      }),
    );
    expect(await planOf(D)).toBe('FREE');
    expect(await confirm(order.orderId, 'pay_2')).toBe('ACTIVATED');
    expect(await planOf(D)).toBe('GOLD');
  });

  it('starts an upgrade now and resumes the lower plan after it; queues a downgrade behind the higher plan', async () => {
    const gold = await buy(E, 'GOLD', 6);
    await confirm(gold.orderId);
    const platinum = await buy(E, 'PLATINUM', 3);
    await confirm(platinum.orderId);
    expect(await planOf(E)).toBe('PLATINUM');

    const [goldRow, platinumRow] = await Promise.all([
      prisma.userSubscription.findUnique({
        where: { id: gold.subscriptionId },
      }),
      prisma.userSubscription.findUnique({
        where: { id: platinum.subscriptionId },
      }),
    ]);
    // The upgrade did not shorten Gold: still ACTIVE, still ~180 days.
    expect(goldRow?.status).toBe('ACTIVE');
    // So after Platinum (~90 days) ends, Gold is what remains.
    const afterPlatinum = new Date(platinumRow!.endDate.getTime() + DAY);
    expect((await membership.resolve(E, afterPlatinum)).plan?.code).toBe(
      'GOLD',
    );

    // A Gold renewal bought now queues behind the Gold already held.
    const renewal = await buy(E, 'GOLD', 3);
    await confirm(renewal.orderId);
    const renewalRow = await prisma.userSubscription.findUnique({
      where: { id: renewal.subscriptionId },
    });
    expect(renewalRow!.startDate.getTime()).toBe(goldRow!.endDate.getTime());
  });

  it('ends access on a full refund, keeps it on a partial one', async () => {
    const order = await buy(A, 'GOLD');
    await confirm(order.orderId, 'pay_refund');
    const refund = (amount: number, id: string) =>
      prisma.$transaction((tx) =>
        lifecycle.recordRefund(tx, {
          paymentId: 'pay_refund',
          refundId: id,
          amountInPaise: amount,
        }),
      );
    expect(await refund(100_000, 'rfnd_1')).toBe('PARTIAL');
    expect(await planOf(A)).toBe('GOLD');
    expect(await refund(299_900, 'rfnd_2')).toBe('FULL');
    expect(await planOf(A)).toBe('FREE');
    expect(
      await prisma.userSubscription.findUnique({
        where: { id: order.subscriptionId },
      }),
    ).toMatchObject({
      status: 'CANCELLED',
      cancellationReason: 'REFUNDED',
    });
  });

  it('cancelling stops renewal but keeps access to the end date', async () => {
    const order = await buy(B, 'GOLD');
    await confirm(order.orderId);
    const { accessUntil } = await lifecycle.cancelAtPeriodEnd(B);
    expect(await planOf(B)).toBe('GOLD');
    const row = await prisma.userSubscription.findUnique({
      where: { id: order.subscriptionId },
    });
    expect(row).toMatchObject({
      status: 'ACTIVE',
      autoRenew: false,
      cancellationReason: 'MEMBER_REQUEST',
    });
    expect(accessUntil).toEqual(row!.endDate);
  });

  it('expires a lapsed subscription, recording the event, and leaves the member Free', async () => {
    const granted = await lifecycle.grant({
      userId: C,
      planCode: 'GOLD',
      days: 30,
      actorId: ADMIN,
      reason: 'test',
    });
    await prisma.userSubscription.update({
      where: { id: granted.subscriptionId },
      data: {
        startDate: new Date(Date.now() - 40 * DAY),
        endDate: new Date(Date.now() - DAY),
      },
    });
    // Access already stopped at the end date, before any sweep ran.
    expect(await planOf(C)).toBe('FREE');
    expect(
      await expireLapsedSubscriptions(prisma, new Date()),
    ).toBeGreaterThanOrEqual(1);
    expect(
      await prisma.userSubscription.findUnique({
        where: { id: granted.subscriptionId },
      }),
    ).toMatchObject({
      status: 'EXPIRED',
    });
    expect(
      await prisma.subscriptionEvent.count({
        where: { subscriptionId: granted.subscriptionId, type: 'EXPIRED' },
      }),
    ).toBe(1);
  });

  it('audits admin grants and refuses a grant without a reason', async () => {
    await expect(
      lifecycle.grant({
        userId: D,
        planCode: 'PLATINUM',
        days: 7,
        actorId: ADMIN,
        reason: '',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    const { subscriptionId } = await lifecycle.grant({
      userId: D,
      planCode: 'PLATINUM',
      days: 7,
      actorId: ADMIN,
      reason: 'support compensation',
    });
    expect(await planOf(D)).toBe('PLATINUM');
    expect(
      await prisma.auditLog.count({
        where: {
          action: 'membership.subscription.grant',
          entityId: subscriptionId,
          actorId: ADMIN,
        },
      }),
    ).toBe(1);
  });

  describe('changing the catalogue', () => {
    async function currentGold() {
      const { plans } = await catalog.refresh();
      const gold = plans.find((p) => p.code === 'GOLD')!;
      return catalog.versionEffectiveAt(gold, new Date())!.entitlements;
    }
    const interestsOf = async (userId: string) =>
      (await membership.resolve(userId)).entitlements?.['interests.send'];

    it('raises Gold interests 100 -> 150 for existing subscribers without a deploy', async () => {
      const order = await buy(A, 'GOLD');
      await confirm(order.orderId);
      const before = await currentGold();

      const result = await admin.publishVersion({
        planCode: 'GOLD',
        entitlements: { ...before, 'interests.send': { limit: 150 } },
        changeNote: 'More interests for Gold',
        actorId: ADMIN,
        applyToExistingSubscribers: true,
      });
      expect(result.reductionsVsCurrent).toEqual([]);
      expect(result.appliedToExisting).toBeGreaterThanOrEqual(1);
      expect(await interestsOf(A)).toEqual({ limit: 150 });
      expect(
        await prisma.subscriptionEvent.count({
          where: { userId: A, type: 'ENTITLEMENTS_UPGRADED' },
        }),
      ).toBe(1);
    });

    it('applies a reduction to new purchases only — never to what someone already bought', async () => {
      const existing = await buy(B, 'GOLD');
      await confirm(existing.orderId);
      const before = await interestsOf(B);
      const gold = await currentGold();

      const result = await admin.publishVersion({
        planCode: 'GOLD',
        entitlements: { ...gold, 'interests.send': { limit: 80 } },
        changeNote: 'Fewer interests for new Gold buyers',
        actorId: ADMIN,
        applyToExistingSubscribers: true,
      });
      expect(result.reductionsVsCurrent).toEqual(['interests.send']);
      expect(result.appliedToExisting).toBe(0);
      expect(await interestsOf(B)).toEqual(before);

      const newcomer = await buy(C, 'GOLD');
      await confirm(newcomer.orderId);
      expect(await interestsOf(C)).toEqual({ limit: 80 });

      // The purchase price snapshot is untouched by any of this.
      expect(
        await prisma.userSubscription.findUnique({
          where: { id: existing.subscriptionId },
        }),
      ).toMatchObject({ priceInPaise: 399_900 });
    });

    it('refuses to paywall verified-only browsing, on any plan', async () => {
      const { plans } = await catalog.refresh();
      const free = catalog.versionEffectiveAt(
        plans.find((p) => p.code === 'FREE')!,
        new Date(),
      )!;
      await expect(
        admin.publishVersion({
          planCode: 'FREE',
          entitlements: { ...free.entitlements, 'search.verified_only': false },
          changeNote: 'should be refused',
          actorId: ADMIN,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('never deactivates Free, and never sells an unpriced duration', async () => {
      await expect(
        admin.setPlanActive({
          planCode: 'FREE',
          isActive: false,
          actorId: ADMIN,
          reason: 'nope',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        admin.setDuration({
          planCode: 'PLATINUM',
          months: 12,
          isActive: true,
          actorId: ADMIN,
          reason: 'no price',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      // ...and the database itself refuses it too.
      await expect(
        prisma.subscriptionPlanDuration.updateMany({
          where: { plan: { name: 'PLATINUM' }, months: 12 },
          data: { isActive: true },
        }),
      ).rejects.toThrow();
    });

    it('keeps existing subscriptions running when their plan is deactivated', async () => {
      const order = await buy(D, 'PLATINUM');
      await confirm(order.orderId);
      await admin.setPlanActive({
        planCode: 'PLATINUM',
        isActive: false,
        actorId: ADMIN,
        reason: 'pause sales',
      });
      try {
        expect(await planOf(D)).toBe('PLATINUM');
        await expect(buy(E, 'PLATINUM')).rejects.toBeInstanceOf(
          BadRequestException,
        );
      } finally {
        await admin.setPlanActive({
          planCode: 'PLATINUM',
          isActive: true,
          actorId: ADMIN,
          reason: 'resume sales',
        });
      }
      expect(
        await prisma.auditLog.count({
          where: { action: 'membership.plan.status.set', actorId: ADMIN },
        }),
      ).toBeGreaterThanOrEqual(2);
    });
  });

  describe('administrative operations', () => {
    const grantBy = (actorId: string) =>
      lifecycle.grant({
        userId: E,
        planCode: 'GOLD',
        days: 7,
        actorId,
        reason: 'support compensation',
      });

    it.each([
      ['a member who is not an admin', NOT_ADMIN],
      ['a suspended admin', SUSPENDED_ADMIN],
      ['an unprovisioned admin holding only legacy JSON grants', LEGACY_ADMIN],
      ['an id that is no user at all', 'mbr-life-nobody'],
    ])('refuses %s, writing nothing', async (_label, actorId) => {
      const auditBefore = await prisma.auditLog.count();
      await expect(grantBy(actorId)).rejects.toBeInstanceOf(ForbiddenException);
      expect(
        await prisma.userSubscription.count({ where: { userId: E } }),
      ).toBe(0);
      expect(await prisma.auditLog.count()).toBe(auditBefore);
    });

    it('rolls the change back when its audit row cannot be written', async () => {
      // The same client, except that inside a transaction the audit insert
      // fails — as a full disk or a broken constraint would.
      const failingAudit = new Proxy(prisma, {
        get(target, prop, receiver) {
          if (prop !== '$transaction')
            return Reflect.get(target, prop, receiver) as unknown;
          return (fn: (tx: unknown) => Promise<unknown>) =>
            target.$transaction((tx) =>
              fn(
                new Proxy(tx, {
                  get(inner, key, r) {
                    if (key === 'auditLog') {
                      return {
                        create: () => Promise.reject(new Error('audit down')),
                      };
                    }
                    return Reflect.get(inner, key, r) as unknown;
                  },
                }),
              ),
            );
        },
      }) as unknown as PrismaService;
      const lifecycleWithFailingAudit = new SubscriptionLifecycleService(
        failingAudit,
        new SubscriptionRepository(failingAudit),
        catalog,
      );

      await expect(
        lifecycleWithFailingAudit.grant({
          userId: E,
          planCode: 'GOLD',
          days: 7,
          actorId: ADMIN,
          reason: 'support compensation',
        }),
      ).rejects.toThrow('audit down');
      expect(
        await prisma.userSubscription.count({ where: { userId: E } }),
      ).toBe(0);
      expect(
        await prisma.subscriptionEvent.count({ where: { userId: E } }),
      ).toBe(0);
      expect(await planOf(E)).toBe('FREE');
    });

    it('lets an admin whose role grants only subscription.* manage subscriptions but not prices', async () => {
      await expect(grantBy(SUBS_ADMIN)).resolves.toHaveProperty(
        'subscriptionId',
      );
      await expect(
        admin.setDuration({
          planCode: 'GOLD',
          months: 3,
          priceInPaise: 1,
          actorId: SUBS_ADMIN,
          reason: 'should be refused',
        }),
      ).rejects.toBeInstanceOf(ForbiddenException);
      // ...and the price did not move.
      const { plans } = await catalog.refresh();
      const gold3 = plans
        .find((p) => p.code === 'GOLD')!
        .durations.find((d) => d.months === 3);
      expect(gold3?.priceInPaise).toBe(399_900);
    });

    it('requires a reason for every catalogue change, display included', async () => {
      await expect(
        admin.updatePlanDisplay({
          planCode: 'GOLD',
          description: 'x',
          actorId: ADMIN,
          reason: '',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('pushes a renewal queued behind an extended plan back by the same days', async () => {
      const first = await buy(A, 'GOLD');
      await confirm(first.orderId);
      const renewal = await buy(A, 'GOLD');
      await confirm(renewal.orderId);
      const before = await prisma.userSubscription.findUniqueOrThrow({
        where: { id: renewal.subscriptionId },
      });

      const { shiftedQueued } = await lifecycle.extend({
        subscriptionId: first.subscriptionId,
        days: 10,
        actorId: ADMIN,
        reason: 'outage compensation',
      });
      expect(shiftedQueued).toBe(1);
      const [extended, after] = await Promise.all([
        prisma.userSubscription.findUniqueOrThrow({
          where: { id: first.subscriptionId },
        }),
        prisma.userSubscription.findUniqueOrThrow({
          where: { id: renewal.subscriptionId },
        }),
      ]);
      // No overlap: the renewal still starts exactly when the extended plan ends.
      expect(after.startDate.getTime()).toBe(extended.endDate.getTime());
      expect(after.endDate.getTime() - before.endDate.getTime()).toBe(10 * DAY);
    });
  });

  describe('out-of-order and replayed payment events', () => {
    const refundBody = (
      orderId: string,
      paymentId: string,
      amount: number,
    ) => ({
      event: 'refund.processed',
      payload: {
        refund: {
          entity: { id: `rfnd_${orderId}`, payment_id: paymentId, amount },
        },
        payment: { entity: { id: paymentId, order_id: orderId } },
      },
    });

    it('never activates a purchase whose refund overtook its capture', async () => {
      const order = await buy(B, 'GOLD');
      const refund = refundBody(order.orderId, 'pay_ooo', order.amountInPaise);
      expect(
        await webhooks.handle(
          `evt_r_${order.orderId}`,
          refund,
          Buffer.from(JSON.stringify(refund)),
        ),
      ).toEqual({ status: 'PROCESSED', detail: 'FULL' });

      // The capture arrives late.
      expect(await confirm(order.orderId, 'pay_ooo')).toBe('REFUNDED');
      expect(await planOf(B)).toBe('FREE');
      expect(
        await prisma.userSubscription.findUniqueOrThrow({
          where: { id: order.subscriptionId },
        }),
      ).toMatchObject({ status: 'CANCELLED', cancellationReason: 'REFUNDED' });
    });

    it('refunds once when a signed refund is replayed under a fresh event id', async () => {
      const order = await buy(C, 'GOLD');
      await confirm(order.orderId, 'pay_replay');
      const partial = refundBody(order.orderId, 'pay_replay', 100_000);
      const raw = Buffer.from(JSON.stringify(partial));
      await webhooks.handle(`evt_a_${order.orderId}`, partial, raw);
      expect(
        await webhooks.handle(`evt_forged_${order.orderId}`, partial, raw),
      ).toEqual({ status: 'DUPLICATE' });
      expect(
        await prisma.paymentTransaction.findUniqueOrThrow({
          where: { razorpayOrderId: order.orderId },
        }),
      ).toMatchObject({ refundedAmount: 100_000, status: 'SUCCESS' });
      expect(await planOf(C)).toBe('GOLD');
    });
  });

  describe('subscriptions from before plan versions', () => {
    it('keeps legacy SILVER and GOLD buyers unrestricted, their records untouched', async () => {
      const silver = await prisma.subscriptionPlan.upsert({
        where: { name: 'SILVER' },
        update: {},
        create: {
          name: 'SILVER',
          displayName: 'Silver Plan',
          priceInr: 49_900,
          durationDays: 30,
          isActive: false,
        },
      });
      const gold = await prisma.subscriptionPlan.findUniqueOrThrow({
        where: { name: 'GOLD' },
      });
      const start = new Date(Date.now() - DAY);
      const end = new Date(Date.now() + 30 * DAY);
      for (const [userId, planId] of [
        [D, silver.id],
        [E, gold.id],
      ] as const) {
        const sub = await prisma.userSubscription.create({
          data: {
            userId,
            planId,
            status: 'ACTIVE',
            startDate: start,
            endDate: end,
          },
        });
        await prisma.paymentTransaction.create({
          data: {
            userId,
            subscriptionId: sub.id,
            amountInr: 99_900,
            status: 'SUCCESS',
            paidAt: start,
          },
        });
      }

      for (const userId of [D, E]) {
        const m = await membership.resolve(userId);
        expect(m).toMatchObject({ source: 'LEGACY', entitlements: null });
        // Never metered, never gated — under enforce.
        await prisma.$transaction((tx) =>
          membership.consume('interests.send', { userId, tx, membership: m }),
        );
        await expect(
          membership.requireFeature(m, 'chat.initiate'),
        ).resolves.toBeUndefined();
      }
      // The history (subscription + payment) is exactly as written.
      expect(
        await prisma.paymentTransaction.count({
          where: { userId: { in: [D, E] } },
        }),
      ).toBe(2);
      expect(
        await prisma.membershipUsageCounter.count({
          where: { userId: { in: [D, E] } },
        }),
      ).toBe(0);
    });
  });

  it('never turns shadow-mode usage into an allowance at the switch to enforce', async () => {
    const db = prisma as unknown as PrismaService;
    const shadow = new MembershipService(
      db,
      catalog,
      new MembershipRepository(db),
      new UsageRepository(db),
      { membership: { enforcementMode: 'shadow' } } as never,
    );
    // 7 interest sends while limits are only being observed (Free = 5).
    for (let i = 0; i < 7; i++) {
      await prisma.$transaction((tx) =>
        shadow.consume('interests.send', { userId: A, tx }),
      );
    }
    // Shadow records off the request path; wait for it to land.
    const shadowKey = shadowFeatureKey('interests.send');
    const shadowUsed = async () =>
      (
        await prisma.membershipUsageCounter.findFirst({
          where: { userId: A, feature: shadowKey },
        })
      )?.used;
    for (let i = 0; i < 100 && (await shadowUsed()) !== 7; i++) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    expect(await shadowUsed()).toBe(7);
    // Enforcement then starts the member on a full allowance of 5.
    for (let i = 0; i < 5; i++) {
      await prisma.$transaction((tx) =>
        membership.consume('interests.send', { userId: A, tx }),
      );
    }
    await expect(
      prisma.$transaction((tx) =>
        membership.consume('interests.send', { userId: A, tx }),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('stores only a hash of each webhook payload, never the payload itself', async () => {
    const body = {
      event: 'payment.authorized',
      payload: { payment: { entity: { email: 'payer@x.in' } } },
    };
    const raw = Buffer.from(JSON.stringify(body));
    await webhooks.handle('evt_pii_check', body, raw);
    const row = await prisma.paymentWebhookEvent.findUnique({
      where: {
        provider_eventId: { provider: 'RAZORPAY', eventId: 'evt_pii_check' },
      },
    });
    expect(row?.payloadSha256).toBe(
      createHash('sha256').update(raw).digest('hex'),
    );
    expect(JSON.stringify(row)).not.toContain('payer@x.in');
    await prisma.paymentWebhookEvent.delete({ where: { id: row!.id } });
  });

  describe('payment events for the agent program', () => {
    const outbox = () =>
      prisma.paymentEventOutbox.findMany({ orderBy: { createdAt: 'asc' } });
    const setGst = (rate: number) =>
      prisma.platformSetting.update({
        where: { key: 'payment.gst_rate_bps' },
        data: { value: rate },
      });
    const refund = (paymentId: string, refundId: string, amount: number) =>
      prisma.$transaction((tx) =>
        lifecycle.recordRefund(tx, {
          paymentId,
          refundId,
          amountInPaise: amount,
        }),
      );

    afterEach(() => setGst(0));

    it('writes PaymentSucceeded once, with the pricing stored at checkout', async () => {
      const order = await buy(A, 'GOLD');
      await confirm(order.orderId, 'pay_ev1');
      await confirm(order.orderId, 'pay_ev1'); // a replay changes nothing
      const payment = await prisma.paymentTransaction.findUniqueOrThrow({
        where: { razorpayOrderId: order.orderId },
      });
      const rows = await outbox();
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({
        type: 'payment.succeeded',
        dedupeKey: `payment.succeeded:${payment.id}`,
        deliveredAt: null,
      });
      expect(rows[0].payload).toEqual({
        type: 'payment.succeeded',
        version: 1,
        paymentId: payment.id,
        livemode: false,
        memberId: A,
        subscriptionId: order.subscriptionId,
        planDurationId: expect.any(String) as string,
        paidBy: 'MEMBER',
        isFirstPaidPlan: true,
        listAmountPaise: 399_900,
        discountPaise: 0,
        discountSource: 'NONE',
        heldReferralCodeId: null,
        taxableAmountPaise: 399_900,
        taxRateBps: 0,
        taxPaise: 0,
        amountPaidPaise: 399_900,
        currency: 'INR',
        paymentSourceHash: null,
        paidAt: expect.any(String) as string,
      });
    });

    it('counts only one payment as the first paid plan, even when two confirm at once', async () => {
      const gold = await buy(B, 'GOLD');
      const platinum = await buy(B, 'PLATINUM');
      await Promise.all([
        confirm(gold.orderId, 'pay_first_1'),
        confirm(platinum.orderId, 'pay_first_2'),
      ]);
      const flags = await prisma.paymentTransaction.findMany({
        where: { userId: B },
        select: { isFirstPaidPlan: true },
      });
      expect(flags.filter((f) => f.isFirstPaidPlan)).toHaveLength(1);
      const events = (await outbox()).map(
        (r) => r.payload as { isFirstPaidPlan: boolean },
      );
      expect(events.filter((e) => e.isFirstPaidPlan)).toHaveLength(1);
    });

    it('stores a hash of the payer’s UPI id from the webhook, never the id', async () => {
      const order = await buy(A, 'GOLD');
      const body = {
        event: 'payment.captured',
        payload: {
          payment: {
            entity: {
              id: 'pay_upi',
              order_id: order.orderId,
              amount: 399_900,
              currency: 'INR',
              vpa: 'priya@okicici',
            },
          },
        },
      };
      await webhooks.handle(
        `evt_upi_${order.orderId}`,
        body,
        Buffer.from(JSON.stringify(body)),
      );
      const payment = await prisma.paymentTransaction.findUniqueOrThrow({
        where: { razorpayOrderId: order.orderId },
      });
      expect(payment.paymentSourceHash).toMatch(/^v1:[0-9a-f]{64}$/);
      expect(JSON.stringify(payment)).not.toContain('priya');
      expect(JSON.stringify(await outbox())).not.toContain('priya');
    });

    it('adds GST on top, and gives each refund its share of it', async () => {
      await setGst(1800);
      const order = await buy(A, 'GOLD');
      // 399900 + 18% (71982) = 471882
      expect(order.amountInPaise).toBe(471_882);
      expect(order.pricing).toMatchObject({
        taxableAmountPaise: 399_900,
        taxPaise: 71_982,
        totalPaise: 471_882,
      });
      await confirm(order.orderId, 'pay_gst');
      await refund('pay_gst', 'rfnd_gst_1', 235_941);
      await refund('pay_gst', 'rfnd_gst_2', 235_941);
      const [succeeded, first, second] = (await outbox()).map(
        (r) => r.payload as Record<string, unknown>,
      );
      expect(succeeded).toMatchObject({
        taxableAmountPaise: 399_900,
        taxRateBps: 1800,
        taxPaise: 71_982,
        amountPaidPaise: 471_882,
      });
      expect(first).toMatchObject({
        type: 'payment.refunded',
        refundId: 'rfnd_gst_1',
        refundedPaise: 235_941,
        refundedTaxPaise: 35_991,
        totalRefundedPaise: 235_941,
        fullyRefunded: false,
        livemode: false,
      });
      expect(second).toMatchObject({
        refundId: 'rfnd_gst_2',
        refundedTaxPaise: 35_991,
        totalRefundedPaise: 471_882,
        fullyRefunded: true,
      });
      expect(
        (first.refundedTaxPaise as number) +
          (second.refundedTaxPaise as number),
      ).toBe(71_982);
    });

    it('writes no refund event for a refund that overtook the capture', async () => {
      const order = await buy(A, 'GOLD');
      await prisma.$transaction((tx) =>
        lifecycle.recordRefund(tx, {
          paymentId: 'pay_early',
          orderId: order.orderId,
          refundId: 'rfnd_early',
          amountInPaise: 399_900,
        }),
      );
      expect(await outbox()).toHaveLength(0);
    });

    it('delivers after commit, waits while nobody subscribes, and retries a rejected event', async () => {
      const bus = new ReferralEventBus();
      const dispatcher = new PaymentEventDispatcher(
        prisma as unknown as PrismaService,
        bus,
      );
      const order = await buy(A, 'GOLD');
      await confirm(order.orderId, 'pay_dispatch');

      expect(await dispatcher.dispatchPending()).toEqual({
        delivered: 0,
        failed: 0,
      });

      const seen: string[] = [];
      let down = true;
      bus.subscribe((event) => {
        if (down) {
          down = false;
          return Promise.reject(new Error('handler down'));
        }
        seen.push(event.type);
        return Promise.resolve();
      });
      expect(await dispatcher.dispatchPending()).toEqual({
        delivered: 0,
        failed: 1,
      });
      expect((await outbox())[0]).toMatchObject({
        attempts: 1,
        lastError: 'handler down',
        deliveredAt: null,
      });

      expect(await dispatcher.dispatchPending()).toEqual({
        delivered: 1,
        failed: 0,
      });
      expect(seen).toEqual(['payment.succeeded']);
      expect((await outbox())[0].deliveredAt).toBeInstanceOf(Date);
      expect(await dispatcher.dispatchPending()).toEqual({
        delivered: 0,
        failed: 0,
      });
    });

    it('refuses to store a pricing breakdown that does not add up (database CHECK)', async () => {
      const order = await buy(A, 'GOLD');
      await expect(
        prisma.paymentTransaction.update({
          where: { razorpayOrderId: order.orderId },
          data: { taxPaise: 1 },
        }),
      ).rejects.toThrow();
    });
  });
});
