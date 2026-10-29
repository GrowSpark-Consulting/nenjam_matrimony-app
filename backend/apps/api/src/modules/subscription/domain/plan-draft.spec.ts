import {
  FEATURE_KEYS,
  defaultValueOf,
  type EntitlementMap,
} from '../../entitlements/catalog/feature-catalog';
import type {
  CatalogDuration,
  CatalogPlan,
  CatalogVersion,
} from '../../entitlements/domain/membership.types';
import { canonical, parseDraftDurations, reviewDraft } from './plan-draft';

const baseEntitlements = Object.fromEntries(
  FEATURE_KEYS.map((key) => [key, defaultValueOf(key)]),
) as EntitlementMap;

const duration = (over: Partial<CatalogDuration> = {}): CatalogDuration => ({
  id: 'dur-3',
  months: 3,
  durationDays: 90,
  bonusDays: 0,
  priceInPaise: null,
  currency: 'INR',
  isActive: false,
  displayOrder: 3,
  ...over,
});

const version: CatalogVersion = {
  id: 'ver-1',
  planId: 'plan-gold',
  version: 1,
  effectiveFrom: new Date('2026-10-01'),
  entitlements: baseEntitlements,
  problems: [],
};

const gold: CatalogPlan = {
  id: 'plan-gold',
  code: 'GOLD',
  name: 'Gold',
  description: null,
  tier: 1,
  displayOrder: 1,
  isActive: true,
  durations: [duration()],
  versions: [version],
};

const asDraft = (d: CatalogDuration) => ({
  months: d.months,
  durationDays: d.durationDays,
  bonusDays: d.bonusDays,
  priceInPaise: d.priceInPaise,
  isActive: d.isActive,
});

describe('plan drafts', () => {
  describe('parseDraftDurations', () => {
    it('accepts a valid price list, sorted by months', () => {
      const { durations, problems } = parseDraftDurations(
        'GOLD',
        [
          {
            months: 6,
            durationDays: 180,
            bonusDays: 14,
            priceInPaise: 699900,
            isActive: true,
          },
          {
            months: 3,
            durationDays: 90,
            bonusDays: 0,
            priceInPaise: null,
            isActive: false,
          },
        ],
        [duration()],
      );
      expect(problems).toEqual([]);
      expect(durations.map((d) => d.months)).toEqual([3, 6]);
    });

    it.each([
      [
        {
          months: 0,
          durationDays: 1,
          bonusDays: 0,
          priceInPaise: null,
          isActive: false,
        },
        'months must be',
      ],
      [
        {
          months: 3,
          durationDays: 90,
          bonusDays: 0,
          priceInPaise: 0,
          isActive: false,
        },
        'priceInPaise must be',
      ],
      [
        {
          months: 3,
          durationDays: 90,
          bonusDays: 0,
          priceInPaise: 99.5,
          isActive: false,
        },
        'priceInPaise must be',
      ],
      [
        {
          months: 3,
          durationDays: 90,
          bonusDays: -1,
          priceInPaise: null,
          isActive: false,
        },
        'bonusDays must be',
      ],
      [
        {
          months: 3,
          durationDays: 90,
          bonusDays: 0,
          priceInPaise: null,
          isActive: true,
        },
        'must be priced',
      ],
      [
        {
          months: 3,
          durationDays: 90,
          bonusDays: 0,
          priceInPaise: 100,
          isActive: 'yes',
        },
        'isActive must be',
      ],
    ])('refuses %j', (item, problem) => {
      const { problems } = parseDraftDurations('GOLD', [item], [duration()]);
      expect(problems.join(' ')).toContain(problem);
    });

    it('refuses duplicates, removals and any duration on Free', () => {
      const item = asDraft(duration());
      expect(
        parseDraftDurations('GOLD', [item, item], [duration()]).problems.join(
          ' ',
        ),
      ).toContain('listed twice');
      expect(
        parseDraftDurations('GOLD', [], [duration()]).problems.join(' '),
      ).toContain("can't be removed");
      expect(
        parseDraftDurations('FREE', [item], []).problems.join(' '),
      ).toContain('Free plan has no price');
      expect(parseDraftDurations('GOLD', 'nope', []).problems).toEqual([
        'durations must be a list.',
      ]);
    });
  });

  describe('reviewDraft', () => {
    it('finds nothing to publish when the draft equals the plan', () => {
      const review = reviewDraft(gold, version, {
        entitlements: baseEntitlements,
        durations: [asDraft(duration())],
      });
      expect(review.hasChanges).toBe(false);
      expect(review.publishable).toBe(false);
      expect(review.entitlementProblems).toEqual([]);
    });

    it('reports a price change, and is publishable', () => {
      const review = reviewDraft(gold, version, {
        entitlements: baseEntitlements,
        durations: [
          { ...asDraft(duration()), priceInPaise: 399900, isActive: true },
        ],
      });
      expect(review.changedFeatures).toEqual([]);
      expect(review.durationChanges).toEqual([
        {
          months: 3,
          before: asDraft(duration()),
          after: {
            ...asDraft(duration()),
            priceInPaise: 399900,
            isActive: true,
          },
        },
      ]);
      expect(review.publishable).toBe(true);
    });

    it('reports changed and reduced features', () => {
      const key = FEATURE_KEYS.find(
        (k) => typeof baseEntitlements[k] === 'boolean',
      )!;
      const flipped = { ...baseEntitlements, [key]: !baseEntitlements[key] };
      const review = reviewDraft(gold, version, {
        entitlements: flipped,
        durations: [asDraft(duration())],
      });
      expect(review.changedFeatures).toEqual([key]);
      expect(review.hasChanges).toBe(true);
    });

    it('is not publishable with an unknown or missing feature', () => {
      const { [FEATURE_KEYS[0]]: _dropped, ...missing } = baseEntitlements;
      void _dropped;
      const review = reviewDraft(gold, version, {
        entitlements: { ...missing, 'made.up': true },
        durations: [
          { ...asDraft(duration()), priceInPaise: 1, isActive: true },
        ],
      });
      expect(review.entitlementProblems.join(' ')).toContain('made.up');
      expect(review.entitlementProblems.join(' ')).toContain(FEATURE_KEYS[0]);
      expect(review.publishable).toBe(false);
    });
  });

  it('compares values regardless of key order', () => {
    expect(canonical({ limit: 5, perMonths: 3 })).toBe(
      canonical({ perMonths: 3, limit: 5 }),
    );
  });
});
