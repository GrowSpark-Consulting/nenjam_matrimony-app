import { buildTierPlan, FallbackConfig } from './tier-plan';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';

const config: FallbackConfig = {
  enabled: true,
  ageRelaxStep1: 2,
  ageRelaxStep2: 5,
  maxTier: 10,
};

const fullPref: PreferenceFilters = {
  minAge: 25,
  maxAge: 30,
  minHeightCm: 150,
  maxHeightCm: 175,
  preferredReligions: ['Hindu'],
  preferredCastes: ['Same Caste'],
  preferredMotherTongues: ['Same Mother Tongue'],
  preferredEducation: ['B.E / B.Tech+'],
  preferredOccupations: ['Software / IT'],
  preferredCities: ['Same City'],
  preferredStates: [],
  maritalStatusPref: ['Never Married'],
  minIncomeLakhs: 5,
};

describe('buildTierPlan', () => {
  it('Tier 1 is the original preference, untouched, with no relaxed filters', () => {
    const plan = buildTierPlan(fullPref, config);
    expect(plan[0]).toMatchObject({ tier: 1, pref: fullPref, relaxedFilters: [] });
  });

  it('no saved preference at all -> single Tier 1 (nothing to relax)', () => {
    const plan = buildTierPlan(null, config);
    expect(plan).toHaveLength(1);
    expect(plan[0]).toMatchObject({ tier: 1, pref: null });
  });

  it('Tier 2 relaxes only age, by ageRelaxStep1, leaving everything else untouched', () => {
    const plan = buildTierPlan(fullPref, config);
    const tier2 = plan.find((t) => t.tier === 2)!;
    expect(tier2.pref?.minAge).toBe(23); // 25 - 2
    expect(tier2.pref?.maxAge).toBe(32); // 30 + 2
    expect(tier2.pref?.preferredCastes).toEqual(fullPref.preferredCastes);
    expect(tier2.pref?.preferredCities).toEqual(fullPref.preferredCities);
    expect(tier2.relaxedFilters).toEqual(['Age']);
  });

  it('age relaxation never drops below the platform minimum age (18)', () => {
    const plan = buildTierPlan({ ...fullPref, minAge: 19 }, config);
    const tier2 = plan.find((t) => t.tier === 2)!;
    expect(tier2.pref?.minAge).toBe(18); // 19 - 2 = 17, clamped to 18
  });

  it('Tier 3 ignores City but keeps State (drops literal/"Same City" tokens, keeps "Same State")', () => {
    const pref = { ...fullPref, preferredCities: ['Same City', 'Same State', 'Chennai'] };
    const plan = buildTierPlan(pref, config);
    const tier3 = plan.find((t) => t.tier === 3)!;
    expect(tier3.pref?.preferredCities).toEqual(['Same State']);
    expect(tier3.relaxedFilters).toEqual(['Age', 'City']);
  });

  it('Tier 4 drops Caste but keeps Religion', () => {
    const plan = buildTierPlan(fullPref, config);
    const tier4 = plan.find((t) => t.tier === 4)!;
    expect(tier4.pref?.preferredCastes).toEqual([]);
    expect(tier4.pref?.preferredReligions).toEqual(fullPref.preferredReligions);
    expect(tier4.relaxedFilters).toEqual(['Age', 'City', 'Caste']);
  });

  it('Tiers 5-8 drop Mother Tongue, Education, Profession, Income in order, cumulatively', () => {
    const plan = buildTierPlan(fullPref, config);
    expect(plan.find((t) => t.tier === 5)!.pref?.preferredMotherTongues).toEqual([]);
    expect(plan.find((t) => t.tier === 6)!.pref?.preferredEducation).toEqual([]);
    expect(plan.find((t) => t.tier === 7)!.pref?.preferredOccupations).toEqual([]);
    expect(plan.find((t) => t.tier === 8)!.pref?.minIncomeLakhs).toBeNull();
    expect(plan.find((t) => t.tier === 8)!.relaxedFilters).toEqual([
      'Age', 'City', 'Caste', 'Mother Tongue', 'Education', 'Profession', 'Income',
    ]);
  });

  it('Tier 9 widens age again using ageRelaxStep2, relative to the ORIGINAL preference (not stacked on Tier 2)', () => {
    const plan = buildTierPlan(fullPref, config);
    const tier9 = plan.find((t) => t.tier === 9)!;
    expect(tier9.pref?.minAge).toBe(20); // 25 - 5, not 23 - 5
    expect(tier9.pref?.maxAge).toBe(35); // 30 + 5, not 32 + 5
    // Everything relaxed through tier 8 stays relaxed.
    expect(tier9.pref?.preferredCastes).toEqual([]);
    expect(tier9.pref?.minIncomeLakhs).toBeNull();
  });

  it('Tier 10 drops every preference (pref: null) — gender-only', () => {
    const plan = buildTierPlan(fullPref, config);
    const tier10 = plan[plan.length - 1];
    expect(tier10.tier).toBe(10);
    expect(tier10.pref).toBeNull();
  });

  it('respects MAX_FALLBACK_TIER — never generates tiers beyond the configured ceiling', () => {
    const plan = buildTierPlan(fullPref, { ...config, maxTier: 3 });
    expect(plan.map((t) => t.tier)).toEqual([1, 2, 3]);
  });

  it('is deterministic — same inputs always produce the same plan', () => {
    const a = buildTierPlan(fullPref, config);
    const b = buildTierPlan(fullPref, config);
    expect(a).toEqual(b);
  });
});
