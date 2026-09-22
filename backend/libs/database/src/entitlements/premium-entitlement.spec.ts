import {
  activePremiumSubscriptionWhere,
  hiddenFromDiscoveryWhere,
} from './premium-entitlement';

const NOW = new Date('2026-09-22T12:00:00.000Z');
const DAY = 24 * 3600 * 1000;

interface Sub {
  status: 'ACTIVE' | 'EXPIRED' | 'CANCELLED' | 'PENDING';
  startDate: Date;
  endDate: Date;
  plan: { name: 'FREE' | 'SILVER' | 'GOLD' };
}

/**
 * Evaluates the filter against a concrete row, interpreting exactly the
 * operators it uses — so the cases below read as "this subscription is / is
 * not premium" rather than as assertions about object shape.
 */
function grantsPremium(sub: Sub): boolean {
  const where = activePremiumSubscriptionWhere(NOW) as {
    status: string;
    startDate: { lte: Date };
    endDate: { gt: Date };
    plan: { name: { not: string } };
  };
  return (
    sub.status === where.status &&
    sub.startDate.getTime() <= where.startDate.lte.getTime() &&
    sub.endDate.getTime() > where.endDate.gt.getTime() &&
    sub.plan.name !== where.plan.name.not
  );
}

const active: Sub = {
  status: 'ACTIVE',
  startDate: new Date(NOW.getTime() - 10 * DAY),
  endDate: new Date(NOW.getTime() + 20 * DAY),
  plan: { name: 'GOLD' },
};

describe('activePremiumSubscriptionWhere', () => {
  it('an ACTIVE, started, unexpired paid subscription is premium', () => {
    expect(grantsPremium(active)).toBe(true);
    expect(grantsPremium({ ...active, plan: { name: 'SILVER' } })).toBe(true);
  });

  it.each(['EXPIRED', 'CANCELLED', 'PENDING'] as const)(
    'a %s subscription is not premium, even inside its dates',
    (status) => {
      expect(grantsPremium({ ...active, status })).toBe(false);
    },
  );

  it('an ACTIVE subscription past its end date is not premium (nobody flipped it to EXPIRED)', () => {
    expect(
      grantsPremium({ ...active, endDate: new Date(NOW.getTime() - 1) }),
    ).toBe(false);
  });

  it('ends exactly at endDate', () => {
    expect(grantsPremium({ ...active, endDate: NOW })).toBe(false);
  });

  it('an ACTIVE subscription that has not started yet is not premium', () => {
    expect(
      grantsPremium({ ...active, startDate: new Date(NOW.getTime() + DAY) }),
    ).toBe(false);
  });

  it('an ACTIVE subscription to the FREE plan is not premium', () => {
    expect(grantsPremium({ ...active, plan: { name: 'FREE' } })).toBe(false);
  });

  it('is exactly these four conditions', () => {
    expect(activePremiumSubscriptionWhere(NOW)).toEqual({
      status: 'ACTIVE',
      startDate: { lte: NOW },
      endDate: { gt: NOW },
      plan: { name: { not: 'FREE' } },
    });
  });
});

describe('hiddenFromDiscoveryWhere', () => {
  it('requires BOTH the hide flag and an active premium subscription', () => {
    expect(hiddenFromDiscoveryWhere(NOW)).toEqual({
      profileVisibleToPremiumOnly: true,
      subscriptions: { some: activePremiumSubscriptionWhere(NOW) },
    });
  });
});
