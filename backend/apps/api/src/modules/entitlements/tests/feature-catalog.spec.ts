import {
  FEATURE_KEYS,
  FEATURES,
  NEVER_GATED_SAFETY_CAPABILITIES,
  defaultValueOf,
  effectiveLimit,
  grants,
  parseEntitlements,
  reductionsBetween,
  validateEntitlementsForPublish,
  type EntitlementMap,
} from '../catalog/feature-catalog';
import { shippedEntitlements } from './catalog-fixtures';

const shipped = shippedEntitlements();
const parsed = {
  FREE: parseEntitlements(shipped.FREE).map,
  GOLD: parseEntitlements(shipped.GOLD).map,
  PLATINUM: parseEntitlements(shipped.PLATINUM).map,
};

describe('the shipped catalogue (migration 20261027120100_membership_catalog)', () => {
  it.each(['FREE', 'GOLD', 'PLATINUM'] as const)(
    '%s is complete and valid against the feature registry',
    (plan) => {
      expect(validateEntitlementsForPublish(shipped[plan])).toEqual([]);
      expect(Object.keys(shipped[plan]).sort()).toEqual(
        [...FEATURE_KEYS].sort(),
      );
    },
  );

  // One row per PDF line item that has a number or a yes/no difference.
  it.each([
    ['profile.photos', { limit: 5 }, { limit: 15 }, { limit: 20 }],
    ['interests.send', { limit: 5 }, { limit: 100 }, { limit: 300 }],
    [
      'discovery.daily_recommendations',
      { limit: 5 },
      { limit: 20 },
      { limit: null },
    ],
    [
      'discovery.profile_views',
      { limit: 30 },
      { limit: null },
      { limit: null },
    ],
    ['search.saved_searches', { limit: 1 }, { limit: 5 }, { limit: null }],
    ['shortlist.profiles', { limit: 10 }, { limit: null }, { limit: null }],
    [
      'contacts.unlocks',
      { limit: 0 },
      { limit: 60, perMonths: 3 },
      { limit: 200 },
    ],
    ['horoscope.astrologer_minutes', { limit: 0 }, { limit: 0 }, { limit: 15 }],
    ['visibility.boost_days', { limit: 0 }, { limit: 7 }, { limit: 15 }],
    ['profile.makeover_sessions', { limit: 0 }, { limit: 0 }, { limit: 1 }],
    ['chat.initiate', false, true, true],
    ['chat.reply', true, true, true],
    ['chat.read_receipts', false, true, true],
    ['chat.accept_from_free_members', false, false, true],
    ['calls.voice', false, true, true],
    ['calls.video', false, false, true],
    ['interests.personal_note', false, true, true],
    ['search.power_filters', false, true, true],
    ['search.community_filters', true, true, true],
    ['discovery.mutual_matches', false, true, true],
    ['horoscope.basic_score', true, true, true],
    ['horoscope.full_jathagam', false, true, true],
    ['horoscope.detailed_report', false, true, true],
    ['profile.video_intro', false, true, true],
    ['visibility.featured', false, false, true],
    ['privacy.incognito', false, false, true],
    ['profile.badge', 'NONE', 'GOLD', 'PLATINUM'],
    ['verification.id_review', 'STANDARD', 'STANDARD', 'PRIORITY'],
    ['visibility.search_priority', 'STANDARD', 'PRIORITY', 'HIGHEST'],
    ['insights.profile_viewers', 'PREVIEW', 'FULL', 'FULL_WITH_TRENDS'],
    [
      'insights.profile_viewers_visible',
      { limit: 3 },
      { limit: null },
      { limit: null },
    ],
    ['insights.shortlisted_by', 'COUNT', 'FULL', 'FULL'],
    ['insights.performance_stats', 'NONE', 'BASIC', 'DETAILED'],
    ['support.tier', 'STANDARD', 'PRIORITY', 'DEDICATED'],
  ])(
    '%s matches the PDF: Free %j / Gold %j / Platinum %j',
    (feature, free, gold, platinum) => {
      const key = feature as keyof EntitlementMap;
      expect(parsed.FREE[key]).toEqual(free);
      expect(parsed.GOLD[key]).toEqual(gold);
      expect(parsed.PLATINUM[key]).toEqual(platinum);
    },
  );

  it('lets Free members browse verified profiles only (product correction to the PDF)', () => {
    expect(parsed.FREE['search.verified_only']).toBe(true);
    expect(parsed.GOLD['search.verified_only']).toBe(true);
    expect(parsed.PLATINUM['search.verified_only']).toBe(true);
  });

  it('never makes Platinum grant less than Gold, or Gold less than Free', () => {
    expect(reductionsBetween(parsed.FREE, parsed.GOLD)).toEqual([]);
    expect(reductionsBetween(parsed.GOLD, parsed.PLATINUM)).toEqual([]);
  });
});

describe('validateEntitlementsForPublish', () => {
  const valid = () => ({ ...shipped.FREE });

  it('refuses any plan that turns verified-only browsing off', () => {
    expect(
      validateEntitlementsForPublish({
        ...valid(),
        'search.verified_only': false,
      }),
    ).toContain('search.verified_only must be enabled on every plan');
  });

  it.each(['interests.respond', 'chat.reply', 'search.basic_filters'])(
    'refuses any plan that takes away the free right %s',
    (feature) => {
      expect(
        validateEntitlementsForPublish({ ...valid(), [feature]: false }),
      ).toEqual([`${feature} must be enabled on every plan`]);
    },
  );

  it('refuses unknown and missing features', () => {
    const missing: Record<string, unknown> = valid();
    delete missing['chat.initiate'];
    expect(validateEntitlementsForPublish(missing)).toContain(
      'chat.initiate is missing',
    );
    expect(
      validateEntitlementsForPublish({ ...valid(), 'made.up': true }),
    ).toContain('made.up is not a known feature');
  });

  it('refuses malformed values', () => {
    const problems = validateEntitlementsForPublish({
      ...valid(),
      'interests.send': { limit: -1 },
      'profile.photos': 5,
      'profile.badge': 'DIAMOND',
      'calls.voice': 'yes',
      'shortlist.profiles': { limit: 10, perMonths: 3 },
      'discovery.profile_views': { limit: 30, fairUse: 100 },
    });
    expect(problems).toEqual(
      expect.arrayContaining([
        'interests.send.limit must be a whole number >= 0, or null for unlimited',
        'profile.photos must be { limit }',
        'profile.badge must be one of NONE, GOLD, PLATINUM',
        'calls.voice must be true or false',
        'shortlist.profiles.perMonths is not allowed',
        'discovery.profile_views.fairUse only applies when limit is null (unlimited)',
      ]),
    );
  });

  it('accepts a fair-use cap on an unlimited quota', () => {
    expect(
      validateEntitlementsForPublish({
        ...shipped.PLATINUM,
        'discovery.profile_views': { limit: null, fairUse: 500 },
      }),
    ).toEqual([]);
  });
});

describe('parseEntitlements (lenient load)', () => {
  it('falls back to the safe default for missing and broken values, and reports them', () => {
    const { map, problems } = parseEntitlements({
      ...shipped.GOLD,
      'chat.initiate': 'maybe',
      'calls.video': undefined,
    });
    expect(map['chat.initiate']).toBe(false);
    expect(problems).toEqual(
      expect.arrayContaining(['chat.initiate must be true or false']),
    );
  });

  it('never lets a broken row take away a free right', () => {
    const { map } = parseEntitlements({});
    expect(map['search.verified_only']).toBe(true);
    expect(map['chat.reply']).toBe(true);
    expect(map['interests.respond']).toBe(true);
    // ...and never grants a paid one.
    expect(map['chat.initiate']).toBe(false);
    expect(map['contacts.unlocks']).toEqual({ limit: 0 });
  });
});

describe('defaultValueOf', () => {
  it('is the most restrictive value for paid features', () => {
    expect(defaultValueOf('calls.video')).toBe(false);
    expect(defaultValueOf('support.tier')).toBe('STANDARD');
    expect(defaultValueOf('interests.send')).toEqual({ limit: 0 });
  });
});

describe('effectiveLimit', () => {
  it('scales a per-plan pool with the plan length (Gold contacts: 60 per 3 months)', () => {
    const gold = parsed.GOLD['contacts.unlocks'];
    expect(effectiveLimit(gold, { subscriptionMonths: 3 })).toEqual({
      limit: 60,
      fairUse: false,
    });
    expect(effectiveLimit(gold, { subscriptionMonths: 6 })).toEqual({
      limit: 120,
      fairUse: false,
    });
  });

  it('does not scale an unscaled pool (Platinum: 200 per plan)', () => {
    expect(
      effectiveLimit(parsed.PLATINUM['contacts.unlocks'], {
        subscriptionMonths: 12,
      }),
    ).toEqual({ limit: 200, fairUse: false });
  });

  it('turns an unlimited value with a fair-use cap into that cap', () => {
    expect(effectiveLimit({ limit: null, fairUse: 500 })).toEqual({
      limit: 500,
      fairUse: true,
    });
    expect(effectiveLimit({ limit: null })).toEqual({
      limit: null,
      fairUse: false,
    });
  });
});

describe('reductionsBetween (the gate for applying a change to existing buyers)', () => {
  const gold = parsed.GOLD;
  const withInterests = (limit: number | null): EntitlementMap => ({
    ...gold,
    'interests.send': { limit },
  });

  it('treats a raised allowance (Gold interests 100 -> 150) as no reduction', () => {
    expect(reductionsBetween(gold, withInterests(150))).toEqual([]);
  });

  it('flags a lowered allowance (100 -> 80) and unlimited -> numbered', () => {
    expect(reductionsBetween(gold, withInterests(80))).toEqual([
      'interests.send',
    ]);
    expect(
      reductionsBetween(gold, {
        ...gold,
        'shortlist.profiles': { limit: 500 },
      }),
    ).toEqual(['shortlist.profiles']);
  });

  it('flags a feature switched off, a lower level, and a new fair-use cap', () => {
    expect(
      reductionsBetween(gold, {
        ...gold,
        'calls.voice': false,
        'support.tier': 'STANDARD',
        'discovery.profile_views': { limit: null, fairUse: 300 },
      }).sort(),
    ).toEqual(['calls.voice', 'discovery.profile_views', 'support.tier']);
  });
});

describe('the registry itself', () => {
  it('has no safety capability in it — safety can never be gated by config', () => {
    for (const capability of NEVER_GATED_SAFETY_CAPABILITIES) {
      expect(
        FEATURE_KEYS.filter((key) => key.endsWith(`.${capability}`)),
      ).toEqual([]);
    }
    // The only PRIVACY-section feature is the paid extra; block, report,
    // hide, photo/contact privacy and masking are not configurable at all.
    expect(
      FEATURE_KEYS.filter((key) => FEATURES[key].section === 'PRIVACY'),
    ).toEqual(['privacy.incognito']);
    // ID verification itself is free; plans only change review speed.
    expect(FEATURES['verification.id_review'].kind).toBe('level');
  });

  it('gives every metered feature a period and every feature a label', () => {
    for (const key of FEATURE_KEYS) {
      const def = FEATURES[key];
      expect(def.label.length).toBeGreaterThan(3);
      if (def.kind === 'quota') expect(def.period).toBeDefined();
    }
  });

  it('reports what a plan grants', () => {
    expect(grants('chat.initiate', true)).toBe(true);
    expect(grants('interests.send', { limit: 0 })).toBe(false);
    expect(grants('interests.send', { limit: null })).toBe(true);
    expect(grants('support.tier', 'STANDARD')).toBe(false);
  });
});
