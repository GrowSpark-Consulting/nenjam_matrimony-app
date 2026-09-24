import {
  buildEligibilityConditions,
  buildEligibilityWhere,
  INELIGIBLE_ACCOUNT_STATUSES,
} from './eligibility.builder';
import { buildFeedWhere } from './partner-preference-where.builder';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { hiddenFromDiscoveryWhere } from '@app/database';
import { FROZEN_NOW, freezeClock } from '../tests/freeze-clock';

type Where = Prisma.UserProfileWhereInput;

// The hidden-profile rule embeds the current time (subscription expiry).
freezeClock();

const ME = 'user-42';
const conditions = (myGender: 'MALE' | 'FEMALE' | null = 'MALE'): Where[] =>
  buildEligibilityConditions({ currentUserId: ME, myGender });

/** The single `user.is` block carrying every account-level rule. */
function accountRules(c: Where[]): Record<string, unknown> {
  const clause = c.find((x) => 'user' in x) as {
    user: { is: Record<string, unknown> };
  };
  return clause.user.is;
}

describe('buildEligibilityConditions', () => {
  it('excludes the caller themselves', () => {
    expect(conditions()).toContainEqual({ userId: { not: ME } });
  });

  it('excludes incomplete profiles', () => {
    expect(conditions()).toContainEqual({ isProfileComplete: true });
  });

  it('excludes soft-deleted accounts', () => {
    expect(accountRules(conditions()).deletedAt).toBeNull();
  });

  it('excludes suspended, deactivated and banned accounts, but not PENDING_VERIFICATION', () => {
    const status = accountRules(conditions()).status as { notIn: string[] };
    expect(status).toEqual({ notIn: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] });
    expect(status.notIn).not.toContain('PENDING_VERIFICATION');
    expect(status.notIn).not.toContain('ACTIVE');
    expect([...INELIGIBLE_ACCOUNT_STATUSES]).toEqual(status.notIn);
  });

  it('excludes a block in either direction', () => {
    const not = accountRules(conditions()).NOT as Where[];
    expect(not).toContainEqual({ blocksMade: { some: { blockedUserId: ME } } });
    expect(not).toContainEqual({ blocksReceived: { some: { blockerId: ME } } });
  });

  it('excludes a declined interest in either direction', () => {
    const not = accountRules(conditions()).NOT as Where[];
    // I sent it, they declined.
    expect(not).toContainEqual({
      receivedInterests: { some: { senderId: ME, status: 'DECLINED' } },
    });
    // They sent it, I declined.
    expect(not).toContainEqual({
      sentInterests: { some: { receiverId: ME, status: 'DECLINED' } },
    });
  });

  describe('Hide My Profile', () => {
    const hiddenRule = () =>
      (accountRules(conditions()).NOT as Where[]).find(
        (x) => 'profileVisibleToPremiumOnly' in x,
      ) as Record<string, unknown>;

    it('excludes any member with the flag on while free hiding is enabled', () => {
      // ALLOW_FREE_PRIVACY_CONTROLS: no premium subscription required.
      expect(hiddenRule()).toEqual({ profileVisibleToPremiumOnly: true });
    });

    it('is the shared hiddenFromDiscoveryWhere rule, not a local copy', () => {
      expect(hiddenRule()).toEqual(hiddenFromDiscoveryWhere(FROZEN_NOW));
    });

    it('lives in the single account-rule block (evaluated inside the same query)', () => {
      expect(conditions().filter((x) => 'user' in x)).toHaveLength(1);
      expect(hiddenRule()).toBeDefined();
    });

    it('evaluates expiry against the supplied instant', () => {
      const at = new Date('2030-01-01T00:00:00.000Z');
      const c = buildEligibilityConditions({
        currentUserId: ME,
        myGender: 'MALE',
        now: at,
      });
      expect(accountRules(c).NOT as Where[]).toContainEqual(
        hiddenFromDiscoveryWhere(at),
      );
    });
  });

  it('does not exclude pending or accepted interests — only a decline removes someone', () => {
    const json = JSON.stringify(conditions());
    expect(json).not.toContain('PENDING');
    expect(json).not.toContain('ACCEPTED');
  });

  it('keeps every account rule in ONE user relation filter', () => {
    expect(conditions().filter((x) => 'user' in x)).toHaveLength(1);
  });

  it('matches the opposite gender only', () => {
    expect(conditions('MALE')).toContainEqual({ gender: 'FEMALE' });
    expect(conditions('FEMALE')).toContainEqual({ gender: 'MALE' });
  });

  it("fails closed when the caller's own gender is unknown", () => {
    expect(conditions(null)).toContainEqual({ gender: { in: [] } });
    expect(JSON.stringify(conditions(null))).not.toContain('"gender":"MALE"');
    expect(JSON.stringify(conditions(null))).not.toContain('"gender":"FEMALE"');
  });

  it('is exactly four conditions', () => {
    expect(conditions()).toHaveLength(4);
  });

  it('buildEligibilityWhere wraps the same conditions in AND', () => {
    expect(
      buildEligibilityWhere({ currentUserId: ME, myGender: 'MALE' }),
    ).toEqual({
      AND: conditions('MALE'),
    });
  });
});

describe('every surface shares the same eligibility', () => {
  const eligibility = conditions('MALE');

  it('the feed WHERE (Discover, every fallback tier, Search) starts with it verbatim', () => {
    const withoutPref = buildFeedWhere({
      currentUserId: ME,
      myGender: 'MALE',
      self: null,
      pref: null,
    });
    const withPref = buildFeedWhere({
      currentUserId: ME,
      myGender: 'MALE',
      self: null,
      pref: { preferredReligions: ['Hindu'], minAge: 25 },
    });
    expect((withoutPref.AND as Where[]).slice(0, 4)).toEqual(eligibility);
    expect((withPref.AND as Where[]).slice(0, 4)).toEqual(eligibility);
  });

  it('a preference can add conditions but never removes an eligibility rule', () => {
    const where = buildFeedWhere({
      currentUserId: ME,
      myGender: 'MALE',
      self: {
        caste: 'Iyer',
        currentCity: 'Chennai',
        currentState: 'Tamil Nadu',
      },
      pref: {
        preferredCastes: ['Same Caste'],
        preferredCities: ['Same State'],
        maritalStatusPref: ['Never Married'],
        extendedPreferences: { diet: 'Vegetarian' },
      },
    });
    for (const rule of eligibility) {
      expect(where.AND as Where[]).toContainEqual(rule);
    }
  });
});
