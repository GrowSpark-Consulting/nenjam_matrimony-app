import {
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import type { MembershipDenialBody } from '../domain/membership-denial';
import {
  MembershipRepository,
  type SubscriptionInForce,
} from '../repositories/membership.repository';
import {
  catalogRows,
  inForce,
  membershipWithPlans,
  shippedEntitlements,
} from './catalog-fixtures';

const NOW = new Date('2026-10-27T06:00:00.000Z'); // 11:30 IST

/** A stand-in transaction client; `marker` lets a test tell two apart. */
function fakeTx(marker?: string): Prisma.TransactionClient {
  return (marker ? { marker } : {}) as never;
}

function denialOf(error: unknown): MembershipDenialBody {
  expect(error).toBeInstanceOf(ForbiddenException);
  return (error as ForbiddenException).getResponse() as MembershipDenialBody;
}

async function caught(promise: Promise<unknown>): Promise<unknown> {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  throw new Error('expected a rejection');
}

describe('MembershipService.resolve', () => {
  it('treats a member with no subscription record as Free — never blocked', async () => {
    const { service } = membershipWithPlans('enforce');
    const membership = await service.resolve('nobody', NOW);
    expect(membership.source).toBe('FREE');
    expect(membership.plan?.code).toBe('FREE');
    expect(membership.subscription).toBeNull();
    expect(membership.entitlements?.['interests.send']).toEqual({ limit: 5 });
  });

  it('asks only for subscriptions in force, so an expired one falls back to Free', async () => {
    // The repository's rule: ACTIVE and startDate <= now < endDate — an
    // expired, cancelled, pending or not-yet-started row never matches.
    const findMany = jest.fn().mockResolvedValue([]);
    const repository = new MembershipRepository({
      userSubscription: { findMany },
    } as never);
    await repository.findInForce('lapsed', NOW);
    const [[query]] = findMany.mock.calls as [[{ where: unknown }]];
    expect(query.where).toEqual({
      userId: 'lapsed',
      status: 'ACTIVE',
      startDate: { lte: NOW },
      endDate: { gt: NOW },
    });

    const { service } = membershipWithPlans('enforce'); // nobody in force
    expect((await service.resolve('lapsed', NOW)).plan?.code).toBe('FREE');
  });

  it.each([
    ['GOLD', 100],
    ['PLATINUM', 300],
  ] as const)(
    'resolves a %s subscriber to %s interests a month',
    async (plan, limit) => {
      const { service } = membershipWithPlans('enforce', {
        m: [inForce(plan)],
      });
      const membership = await service.resolve('m', NOW);
      expect(membership.source).toBe('SUBSCRIPTION');
      expect(membership.plan?.code).toBe(plan);
      expect(membership.entitlements?.['interests.send']).toEqual({ limit });
    },
  );

  it('lets the highest plan win when an upgrade overlaps the plan it upgraded', async () => {
    const { service } = membershipWithPlans('enforce', {
      m: [
        inForce('GOLD', { endDate: new Date('2027-06-01T00:00:00.000Z') }),
        inForce('PLATINUM', { endDate: new Date('2027-01-01T00:00:00.000Z') }),
      ],
    });
    expect((await service.resolve('m', NOW)).plan?.code).toBe('PLATINUM');
  });

  it('keeps a subscriber on the version they bought, not a later one', async () => {
    const gold = shippedEntitlements().GOLD;
    const rows = catalogRows({
      purchasable: true,
      extraVersions: [
        {
          plan: 'GOLD',
          id: 'ver-GOLD-2',
          version: 2,
          effectiveFrom: new Date('2026-10-01T00:00:00.000Z'),
          entitlements: { ...gold, 'interests.send': { limit: 80 } },
        },
      ],
    });
    const { service } = membershipWithPlans(
      'enforce',
      {
        bought_v1: [inForce('GOLD', { planVersionId: 'ver-GOLD-1' })],
        bought_v2: [inForce('GOLD', { planVersionId: 'ver-GOLD-2' })],
      },
      { rows },
    );
    expect(
      (await service.resolve('bought_v1', NOW)).entitlements?.[
        'interests.send'
      ],
    ).toEqual({
      limit: 100,
    });
    expect(
      (await service.resolve('bought_v2', NOW)).entitlements?.[
        'interests.send'
      ],
    ).toEqual({
      limit: 80,
    });
  });

  it('fails OPEN when the Free plan is missing from the catalogue', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const rows = catalogRows().filter((row) => row.name !== 'FREE');
    const { service } = membershipWithPlans('enforce', {}, { rows });
    const membership = await service.resolve('m', NOW);
    expect(membership.source).toBe('UNAVAILABLE');
    expect(service.isEnabled(membership, 'chat.initiate')).toBe(true);
    await expect(
      service.consume('interests.send', { userId: 'm', now: NOW }),
    ).resolves.toBeUndefined();
  });

  it('fails OPEN when the database errors', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const { service, membershipRepository } = membershipWithPlans('enforce');
    membershipRepository.findInForce.mockRejectedValueOnce(
      new Error('connection reset'),
    );
    expect((await service.resolve('m', NOW)).source).toBe('UNAVAILABLE');
  });

  it('never resolves a paid subscriber it cannot interpret down to Free', async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const { service } = membershipWithPlans('enforce', {
      m: [inForce('GOLD', { planVersionId: 'deleted-version' })],
    });
    expect((await service.resolve('m', NOW)).source).toBe('UNAVAILABLE');
  });

  it.each(['GOLD', 'PLATINUM'] as const)(
    'never reinterprets a pre-versioning %s subscription under today’s terms — no limits instead',
    async (plan) => {
      jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
      const { service, usage } = membershipWithPlans('enforce', {
        m: [inForce(plan, { planVersionId: null })],
      });
      const membership = await service.resolve('m', NOW);
      expect(membership).toMatchObject({
        source: 'LEGACY',
        plan: { code: plan },
        planVersion: null,
        entitlements: null,
      });
      // Old GOLD was sold with unlimited interests: nothing is metered.
      for (let i = 0; i < 400; i++) {
        await service.consume('interests.send', {
          userId: 'm',
          tx: fakeTx(),
          membership,
          now: NOW,
        });
      }
      expect(usage.consume).not.toHaveBeenCalled();
      expect(service.isEnabled(membership, 'chat.initiate')).toBe(true);
    },
  );

  it('lets a legacy subscription win over a newer, versioned one', async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const { service } = membershipWithPlans('enforce', {
      m: [inForce('PLATINUM'), inForce('GOLD', { planVersionId: null })],
    });
    expect((await service.resolve('m', NOW)).source).toBe('LEGACY');
  });
});

describe('verified-only browsing', () => {
  it.each(['FREE', 'GOLD', 'PLATINUM'] as const)(
    'is available to %s members',
    async (plan) => {
      const members: Record<string, SubscriptionInForce[]> =
        plan === 'FREE' ? {} : { m: [inForce(plan)] };
      const { service } = membershipWithPlans('enforce', members);
      const membership = await service.resolve('m', NOW);
      expect(service.isEnabled(membership, 'search.verified_only')).toBe(true);
      await expect(
        service.requireFeature(membership, 'search.verified_only'),
      ).resolves.toBeUndefined();
    },
  );
});

describe('MembershipService.requireFeature', () => {
  afterEach(() => jest.restoreAllMocks());

  it('denies a Free member a paid feature with a structured 403 under enforce', async () => {
    const { service } = membershipWithPlans('enforce');
    const free = await service.resolve('m', NOW);
    const body = denialOf(
      await caught(service.requireFeature(free, 'chat.initiate')),
    );
    expect(body).toMatchObject({
      statusCode: 403,
      code: 'MEMBERSHIP_FEATURE_UNAVAILABLE',
      feature: 'chat.initiate',
      plan: 'FREE',
      upgradeTo: 'GOLD',
    });
    expect(body.message).toBe(
      "Starting a conversation isn't included in your Free plan. Upgrade to Gold to unlock it.",
    );
  });

  it('points at the cheapest plan that grants it (video calls need Platinum)', async () => {
    const { service } = membershipWithPlans('enforce', {
      m: [inForce('GOLD')],
    });
    const gold = await service.resolve('m', NOW);
    expect(
      denialOf(await caught(service.requireFeature(gold, 'calls.video')))
        .upgradeTo,
    ).toBe('PLATINUM');
  });

  it('never suggests an upgrade that cannot be bought', async () => {
    const { service } = membershipWithPlans(
      'enforce',
      {},
      { purchasable: false },
    );
    const free = await service.resolve('m', NOW);
    const body = denialOf(
      await caught(service.requireFeature(free, 'chat.initiate')),
    );
    expect(body.upgradeTo).toBeNull();
    expect(body.message).toBe(
      "Starting a conversation isn't included in your Free plan.",
    );
  });

  it('only logs under shadow, and does nothing at all under off', async () => {
    const log = jest
      .spyOn(Logger.prototype, 'log')
      .mockImplementation(() => undefined);
    const shadow = membershipWithPlans('shadow').service;
    await expect(
      shadow.requireFeature(await shadow.resolve('m', NOW), 'chat.initiate'),
    ).resolves.toBeUndefined();
    expect(log).toHaveBeenCalledWith(
      expect.stringContaining('would deny chat.initiate'),
    );

    const off = membershipWithPlans('off').service;
    await expect(
      off.requireFeature(await off.resolve('m', NOW), 'chat.initiate'),
    ).resolves.toBeUndefined();
  });
});

describe('MembershipService.consume', () => {
  afterEach(() => jest.restoreAllMocks());

  it('admits exactly the Free monthly allowance, then a 403 that says when it resets', async () => {
    const { service } = membershipWithPlans('enforce');
    const tx = fakeTx();
    for (let i = 0; i < 5; i++) {
      await service.consume('interests.send', { userId: 'm', tx, now: NOW });
    }
    const body = denialOf(
      await caught(
        service.consume('interests.send', { userId: 'm', tx, now: NOW }),
      ),
    );
    expect(body).toMatchObject({
      code: 'MEMBERSHIP_LIMIT_REACHED',
      feature: 'interests.send',
      limit: 5,
      used: 5,
      plan: 'FREE',
      upgradeTo: 'GOLD',
      resetsAt: '2026-10-31T18:30:00.000Z', // midnight IST on 1 November
    });
    expect(body.message).toBe(
      "You've used all 5 interests included in your Free plan this month. Upgrade to Gold to get more.",
    );
  });

  it("charges inside the caller's transaction, never its own, under enforce", async () => {
    const { service, usage, prisma } = membershipWithPlans('enforce');
    const tx = fakeTx('caller');
    await service.consume('interests.send', { userId: 'm', tx, now: NOW });
    expect(usage.consume).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({
        feature: 'interests.send',
        periodKey: 'M:2026-10',
        ceiling: 5,
      }),
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('meters an unlimited plan without a ceiling', async () => {
    const { service, usage } = membershipWithPlans('enforce', {
      m: [inForce('PLATINUM')],
    });
    await service.consume('discovery.daily_recommendations', {
      userId: 'm',
      tx: fakeTx(),
      now: NOW,
    });
    expect(usage.consume).toHaveBeenCalledWith(
      {},
      expect.objectContaining({ ceiling: null, periodKey: 'D:2026-10-27' }),
    );
  });

  it('charges a per-item feature once per item (the same profile twice costs one)', async () => {
    const { service, usage } = membershipWithPlans('enforce', {
      m: [inForce('GOLD')],
    });
    for (const profile of ['p1', 'p1', 'p2']) {
      await service.consume('contacts.unlocks', {
        userId: 'm',
        tx: fakeTx(),
        itemKey: profile,
        now: NOW,
      });
    }
    expect(usage.counters.get('m|contacts.unlocks|S:sub-GOLD')).toBe(2);
  });

  it('draws a per-plan pool scaled to the plan length (Gold 6 months = 120 contacts)', async () => {
    const { service, usage } = membershipWithPlans('enforce', {
      m: [inForce('GOLD', { months: 6 })],
    });
    await service.consume('contacts.unlocks', {
      userId: 'm',
      tx: fakeTx(),
      itemKey: 'p',
      now: NOW,
    });
    expect(usage.consume).toHaveBeenCalledWith(
      {},
      expect.objectContaining({ ceiling: 120 }),
    );
  });

  it('under shadow, records off the request path and never throws — even past the limit', async () => {
    const log = jest
      .spyOn(Logger.prototype, 'log')
      .mockImplementation(() => undefined);
    const { service, usage, prisma } = membershipWithPlans('shadow');
    for (let i = 0; i < 7; i++) {
      await expect(
        service.consume('interests.send', {
          userId: 'm',
          tx: fakeTx('caller'),
          now: NOW,
        }),
      ).resolves.toBeUndefined();
    }
    await new Promise((resolve) => setImmediate(resolve));
    // Its own transactions, not the caller's.
    expect(prisma.$transaction).toHaveBeenCalled();
    // Real demand is still counted past the limit, and the overshoot logged.
    expect(usage.counters.get('m|shadow:interests.send|M:2026-10')).toBe(7);
    // ...in shadow's own counter — the allowance enforcement reads is
    // untouched, so switching to `enforce` starts everyone fresh.
    expect(usage.counters.get('m|interests.send|M:2026-10')).toBeUndefined();
    expect(log).toHaveBeenCalledWith(
      expect.stringContaining('would deny interests.send'),
    );
  });

  it('does nothing at all under off', async () => {
    const { service, usage, membershipRepository } = membershipWithPlans('off');
    await service.consume('interests.send', {
      userId: 'm',
      tx: fakeTx(),
      now: NOW,
    });
    expect(usage.consume).not.toHaveBeenCalled();
    expect(membershipRepository.findInForce).not.toHaveBeenCalled();
  });
});

describe('MembershipService.enforceCap', () => {
  afterEach(() => jest.restoreAllMocks());
  const legacyLimit = {
    limit: 6,
    message: 'Cannot upload more than 6 photos.',
  };

  it('keeps the legacy cap, and only it, when not enforcing', async () => {
    for (const mode of ['off', 'shadow'] as const) {
      jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
      const { service } = membershipWithPlans(mode);
      // 5 photos: over Free's plan limit (5), under the legacy 6 — allowed.
      await expect(
        service.enforceCap('profile.photos', {
          userId: 'm',
          count: () => Promise.resolve(5),
          legacyLimit,
        }),
      ).resolves.toBeUndefined();
      await expect(
        service.enforceCap('profile.photos', {
          userId: 'm',
          count: () => Promise.resolve(6),
          legacyLimit,
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    }
  });

  it('counts nothing under off when there is no legacy cap', async () => {
    const { service } = membershipWithPlans('off');
    const count = jest.fn();
    await service.enforceCap('shortlist.profiles', { userId: 'm', count });
    expect(count).not.toHaveBeenCalled();
  });

  it.each([
    ['FREE', 5],
    ['GOLD', 15],
    ['PLATINUM', 20],
  ] as const)(
    'applies the %s photo cap of %i under enforce, ignoring the legacy one',
    async (plan, cap) => {
      const members: Record<string, SubscriptionInForce[]> =
        plan === 'FREE' ? {} : { m: [inForce(plan)] };
      const { service } = membershipWithPlans('enforce', members);
      await expect(
        service.enforceCap('profile.photos', {
          userId: 'm',
          count: () => Promise.resolve(cap - 1),
          legacyLimit,
        }),
      ).resolves.toBeUndefined();
      const body = denialOf(
        await caught(
          service.enforceCap('profile.photos', {
            userId: 'm',
            count: () => Promise.resolve(cap),
            legacyLimit,
          }),
        ),
      );
      expect(body).toMatchObject({
        code: 'MEMBERSHIP_LIMIT_REACHED',
        limit: cap,
        used: cap,
      });
    },
  );

  it('locks then counts inside the transaction it is given', async () => {
    const { service, usage } = membershipWithPlans('enforce');
    const tx = fakeTx('tx');
    const count = jest.fn().mockResolvedValue(3);
    await service.enforceCap('shortlist.profiles', { userId: 'm', tx, count });
    expect(usage.lockCap).toHaveBeenCalledWith(tx, 'm', 'shortlist.profiles');
    expect(count).toHaveBeenCalledWith(tx);
    expect(usage.lockCap.mock.invocationCallOrder[0]).toBeLessThan(
      count.mock.invocationCallOrder[0],
    );
  });

  it('neither locks nor counts for an unlimited cap', async () => {
    const { service, usage } = membershipWithPlans('enforce', {
      m: [inForce('GOLD')],
    });
    const count = jest.fn();
    await service.enforceCap('shortlist.profiles', {
      userId: 'm',
      tx: fakeTx(),
      count,
    });
    expect(count).not.toHaveBeenCalled();
    expect(usage.lockCap).not.toHaveBeenCalled();
  });
});

describe('caps when a member has no plan terms (LEGACY / UNAVAILABLE)', () => {
  afterEach(() => jest.restoreAllMocks());
  const legacyLimit = {
    limit: 6,
    message: 'Cannot upload more than 6 photos.',
  };

  it('falls back to the pre-membership photo cap under enforce — not to "no cap"', async () => {
    jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const { service } = membershipWithPlans('enforce', {
      m: [inForce('GOLD', { planVersionId: null })],
    });
    await expect(
      service.enforceCap('profile.photos', {
        userId: 'm',
        count: () => Promise.resolve(5),
        legacyLimit,
      }),
    ).resolves.toBeUndefined();
    await expect(
      service.enforceCap('profile.photos', {
        userId: 'm',
        count: () => Promise.resolve(6),
        legacyLimit,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('MembershipService.effectiveCap (what /membership/me reports)', () => {
  it.each([
    ['off', 'FREE', 6],
    ['shadow', 'FREE', 6],
    ['enforce', 'FREE', 5],
    ['enforce', 'GOLD', 15],
    ['enforce', 'PLATINUM', 20],
  ] as const)(
    'reports the photo cap actually applied: %s mode, %s plan -> %i',
    async (mode, plan, cap) => {
      const members: Record<string, SubscriptionInForce[]> =
        plan === 'FREE' ? {} : { m: [inForce(plan)] };
      const { service } = membershipWithPlans(mode, members);
      const membership = await service.resolve('m', NOW);
      expect(service.effectiveCap(membership, 'profile.photos')).toBe(cap);
    },
  );

  it('reports no shortlist cap until limits are enforced, then Free’s 10', async () => {
    const shadow = membershipWithPlans('shadow').service;
    expect(
      shadow.effectiveCap(await shadow.resolve('m', NOW), 'shortlist.profiles'),
    ).toBeNull();
    const enforce = membershipWithPlans('enforce').service;
    expect(
      enforce.effectiveCap(
        await enforce.resolve('m', NOW),
        'shortlist.profiles',
      ),
    ).toBe(10);
  });
});

describe('MembershipService.summarize', () => {
  it('reports usage against every metered allowance, with reset times', async () => {
    const { service } = membershipWithPlans('enforce');
    await service.consume('interests.send', {
      userId: 'm',
      tx: fakeTx(),
      now: NOW,
    });
    const { usage } = await service.summarize('m', NOW);
    expect(usage.find((u) => u.feature === 'interests.send')).toEqual({
      feature: 'interests.send',
      period: 'MONTH',
      used: 1,
      limit: 5,
      remaining: 4,
      fairUse: false,
      resetsAt: new Date('2026-10-31T18:30:00.000Z'),
    });
    expect(
      usage.find((u) => u.feature === 'discovery.profile_views'),
    ).toMatchObject({
      used: 0,
      limit: 30,
      period: 'DAY',
    });
  });
});
