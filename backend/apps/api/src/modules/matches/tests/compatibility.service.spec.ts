import { CompatibilityService } from '../scoring/compatibility.service';
import type { ScorableProfile } from '../scoring/compatibility.service';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import {
  MATCHING_ALGORITHM_VERSION,
  MATCHING_WEIGHTS,
  MUTUAL_BLEND,
  totalWeight,
  scoreBand,
} from '../scoring/matching-weights.config';
import { PREFERENCE_COMPATIBILITY_SIGNAL } from '../scoring/preference/preference-compatibility.signal';
import { CANDIDATE_QUALITY_SIGNAL } from '../scoring/quality/candidate-quality.signal';
import { buildFeedWhere } from '../filters/partner-preference-where.builder';

const YEAR = 365.25 * 24 * 3600 * 1000;
const dobForAge = (age: number): Date => new Date(Date.now() - age * YEAR);

function profile(over: Partial<ScorableProfile> = {}): ScorableProfile {
  return {
    userId: 'u-candidate',
    dob: dobForAge(28),
    heightCm: 170,
    religion: 'Hindu',
    caste: 'Iyer',
    community: 'Brahmin',
    motherTongue: 'Tamil',
    highestEducation: 'B.E',
    profession: 'Software Engineer',
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    maritalStatus: 'NEVER_MARRIED',
    dietaryHabits: 'Vegetarian',
    smokingHabits: 'Never',
    drinkingHabits: 'Never',
    profileCompletePct: 100,
    trustScore: 100,
    updatedAt: new Date(),
    preference: null,
    ...over,
  };
}

function preference(over: Partial<PreferenceFilters> = {}): PreferenceFilters {
  return {
    minAge: 25,
    maxAge: 32,
    minHeightCm: 160,
    maxHeightCm: 185,
    preferredReligions: ['Hindu'],
    preferredCastes: ['Iyer'],
    preferredMotherTongues: ['Tamil'],
    preferredEducation: ['B.E'],
    preferredOccupations: ['Software Engineer'],
    preferredCities: ['Chennai'],
    preferredStates: ['Tamil Nadu'],
    maritalStatusPref: ['NEVER_MARRIED'],
    ...over,
  };
}

describe('CompatibilityService', () => {
  let svc: CompatibilityService;
  beforeEach(() => {
    svc = new CompatibilityService();
  });

  describe('weight configuration', () => {
    it('sums to exactly 100 so the scale stays meaningful', () => {
      expect(totalWeight()).toBe(100);
    });

    it('maps scores onto display bands', () => {
      expect(scoreBand(95)).toBe('Excellent');
      expect(scoreBand(65)).toBe('Very good');
      expect(scoreBand(45)).toBe('Good');
      expect(scoreBand(10)).toBe('Fair');
    });
  });

  describe('one-directional fit', () => {
    it('scores an exact preference match at 100', () => {
      const seeker = profile({ userId: 'me' });
      const result = svc.score(seeker, preference(), profile());
      expect(result.seekerFit).toBe(100);
      expect(result.band).toBe('Excellent');
    });

    it('scores a partial match between the extremes', () => {
      // Right religion and language, wrong caste, city and profession.
      const candidate = profile({
        caste: 'Gounder',
        community: 'Kongu Vellalar',
        currentCity: 'Madurai',
        profession: 'Teacher',
      });
      const result = svc.score(profile({ userId: 'me' }), preference(), candidate);
      expect(result.seekerFit).toBeGreaterThan(0);
      expect(result.seekerFit).toBeLessThan(100);
    });

    it('scores an incompatible candidate low but never negative', () => {
      const candidate = profile({
        dob: dobForAge(55),
        heightCm: 200,
        religion: 'Christian',
        caste: 'Roman Catholic',
        community: null,
        motherTongue: 'Malayalam',
        highestEducation: 'B.A',
        profession: 'Chef',
        currentCity: 'Kochi',
        currentState: 'Kerala',
        maritalStatus: 'DIVORCED',
        profileCompletePct: 0,
        trustScore: 0,
      });
      const result = svc.score(profile({ userId: 'me' }), preference(), candidate);
      expect(result.seekerFit).toBeGreaterThanOrEqual(0);
      expect(result.seekerFit).toBeLessThan(30);
    });
  });

  describe('unstated preferences', () => {
    it('does not penalise a candidate when no preference is saved at all', () => {
      // Quality signals are all perfect; with no preferences stated the score
      // must reflect that, not collapse toward zero.
      const result = svc.score(profile({ userId: 'me' }), null, profile());
      expect(result.seekerFit).toBe(100);
    });

    it('ignores "Any …" tokens instead of treating them as a requirement', () => {
      const pref = preference({
        preferredCastes: ['Any Caste'],
        preferredReligions: ['Any Religion'],
      });
      const candidate = profile({ caste: 'Gounder', community: null, religion: 'Muslim' });
      const result = svc.score(profile({ userId: 'me' }), pref, candidate);
      // Caste and religion are inapplicable, so the mismatch costs nothing.
      const caste = result.components.find((c) => c.key === 'community');
      const religion = result.components.find((c) => c.key === 'religion');
      expect(caste?.applicable).toBe(false);
      expect(religion?.applicable).toBe(false);
      expect(result.seekerFit).toBe(100);
    });

    it('resolves "Same X" against the seeker, matching the WHERE builder', () => {
      const seeker = profile({ userId: 'me', currentCity: 'Bengaluru' });
      const pref = preference({ preferredCities: ['Same City'], preferredStates: [] });
      const same = svc.score(seeker, pref, profile({ currentCity: 'Bengaluru' }));
      const diff = svc.score(seeker, pref, profile({ currentCity: 'Chennai' }));
      const a = same.components.find((c) => c.key === 'location');
      const b = diff.components.find((c) => c.key === 'location');
      expect(a?.ratio).toBe(1);
      expect(b?.ratio).toBeLessThan(1);
    });

    it('ignores an unmapped grouped UI label, exactly as the filter does', () => {
      // A "/" label that is neither a known category nor a real profile value
      // cannot match anyone. The WHERE builder drops it; scoring must agree or
      // a candidate would be filtered IN and then scored as a mismatch.
      const pref = preference({ preferredOccupations: ['Arts / Media'] });
      const result = svc.score(
        profile({ userId: 'me' }),
        pref,
        profile({ profession: 'Doctor' }),
      );
      const prof = result.components.find((c) => c.key === 'profession');
      expect(prof?.applicable).toBe(false);
    });

    it('expands a known category the way the filter does', () => {
      // "Software / IT" is a category the picker offers; it covers the
      // profile value "Software Engineer". It used to be dropped as a label,
      // so the preference never counted at all.
      const pref = preference({ preferredOccupations: ['Software / IT'] });
      const match = svc.score(
        profile({ userId: 'me' }),
        pref,
        profile({ profession: 'Software Engineer' }),
      );
      const miss = svc.score(
        profile({ userId: 'me' }),
        pref,
        profile({ profession: 'Doctor' }),
      );
      expect(
        match.components.find((c) => c.key === 'profession'),
      ).toMatchObject({ applicable: true, ratio: 1 });
      expect(
        miss.components.find((c) => c.key === 'profession'),
      ).toMatchObject({ applicable: true, ratio: 0 });
    });

    it('scores "B.E / B.Tech+" as this level or higher', () => {
      const pref = preference({ preferredEducation: ['B.E / B.Tech+'] });
      for (const [education, ratio] of [
        ['B.E / B.Tech', 1],
        ['M.Tech / M.E', 1],
        ['Ph.D', 1],
        ['B.Com / M.Com', 0],
      ] as const) {
        const r = svc.score(
          profile({ userId: 'me' }),
          pref,
          profile({ highestEducation: education }),
        );
        expect({
          education,
          ratio: r.components.find((c) => c.key === 'education')?.ratio,
        }).toEqual({ education, ratio });
      }
    });
  });

  describe('graceful degradation', () => {
    it('decays age rather than dropping off a cliff', () => {
      const pref = preference({ minAge: 25, maxAge: 30 });
      const inBand = svc.score(profile({ userId: 'me' }), pref, profile({ dob: dobForAge(29) }));
      const justOver = svc.score(profile({ userId: 'me' }), pref, profile({ dob: dobForAge(31) }));
      const wayOver = svc.score(profile({ userId: 'me' }), pref, profile({ dob: dobForAge(40) }));

      const age = (r: typeof inBand): number =>
        r.components.find((c) => c.key === 'age')?.ratio ?? -1;

      expect(age(inBand)).toBe(1);
      expect(age(justOver)).toBeLessThan(1);
      expect(age(justOver)).toBeGreaterThan(0);
      expect(age(wayOver)).toBe(0);
    });

    it('gives partial credit for the right state but the wrong city', () => {
      const seeker = profile({ userId: 'me', currentState: 'Tamil Nadu' });
      const pref = preference({ preferredCities: ['Chennai'], preferredStates: [] });
      const result = svc.score(seeker, pref, profile({ currentCity: 'Madurai', currentState: 'Tamil Nadu' }));
      const loc = result.components.find((c) => c.key === 'location');
      expect(loc?.ratio).toBe(0.5);
    });
  });

  describe('mutual compatibility', () => {
    it('blends both directions when the candidate has preferences', () => {
      const seeker = profile({ userId: 'me' });
      // Candidate wants exactly the seeker.
      const candidate = profile({ preference: preference() });
      const result = svc.score(seeker, preference(), candidate);
      expect(result.mutualFit).toBe(100);
      expect(result.overall).toBe(100);
    });

    it('scores a one-way match below a two-way match', () => {
      const seeker = profile({ userId: 'me' });
      const twoWay = svc.score(seeker, preference(), profile({ preference: preference() }));
      // Candidate's own preference excludes the seeker on every axis.
      const oneWay = svc.score(
        seeker,
        preference(),
        profile({
          preference: preference({
            minAge: 45,
            maxAge: 55,
            preferredReligions: ['Christian'],
            preferredCastes: ['Roman Catholic'],
            preferredMotherTongues: ['Malayalam'],
            preferredCities: ['Kochi'],
            preferredStates: ['Kerala'],
            preferredEducation: ['MBBS'],
            preferredOccupations: ['Doctor'],
          }),
        }),
      );
      expect(oneWay.overall).toBeLessThan(twoWay.overall);
      expect(oneWay.seekerFit).toBe(twoWay.seekerFit);
    });

    it('falls back to the one-way score when the candidate saved no preference', () => {
      const result = svc.score(profile({ userId: 'me' }), preference(), profile({ preference: null }));
      expect(result.mutualFit).toBeNull();
      expect(result.overall).toBe(result.seekerFit);
    });

    it('weights the seeker direction more heavily than the candidate direction', () => {
      expect(MUTUAL_BLEND.seekerToCandidate).toBeGreaterThan(MUTUAL_BLEND.candidateToSeeker);
      expect(MUTUAL_BLEND.seekerToCandidate + MUTUAL_BLEND.candidateToSeeker).toBeCloseTo(1);
    });
  });

  describe('quality signals', () => {
    it('rewards a complete, verified, recently updated profile', () => {
      const strong = svc.score(profile({ userId: 'me' }), null, profile());
      const weak = svc.score(
        profile({ userId: 'me' }),
        null,
        profile({
          profileCompletePct: 20,
          trustScore: 0,
          updatedAt: new Date(Date.now() - 200 * 24 * 3600 * 1000),
        }),
      );
      expect(strong.seekerFit).toBeGreaterThan(weak.seekerFit);
    });

    it('treats a missing activity timestamp as inapplicable, not as inactive', () => {
      const result = svc.score(profile({ userId: 'me' }), null, profile({ updatedAt: null }));
      const activity = result.components.find((c) => c.key === 'activity');
      expect(activity?.applicable).toBe(false);
    });
  });

  describe('scoreMany', () => {
    it('returns one breakdown per candidate, keyed by user id', () => {
      const rows = [profile({ userId: 'a' }), profile({ userId: 'b' })];
      const map = svc.scoreMany(profile({ userId: 'me' }), preference(), rows);
      expect(map.size).toBe(2);
      expect(map.get('a')?.overall).toBeGreaterThan(0);
      expect(map.get('b')?.overall).toBeGreaterThan(0);
    });
  });

  /**
   * Scoring must never become a way to smuggle a safety rule out of the WHERE
   * clause. These assert the boundary rather than the arithmetic: exclusion
   * lives in buildFeedWhere, and it is still there.
   */
  describe('hard eligibility stays in the WHERE clause', () => {
    const where = buildFeedWhere({
      currentUserId: 'me',
      myGender: 'MALE',
      self: { caste: 'Iyer', currentCity: 'Chennai', currentState: 'TN', motherTongue: 'Tamil' },
      pref: null,
    });
    const json = JSON.stringify(where);

    it('excludes the caller from their own feed', () => {
      expect(json).toContain('"not":"me"');
    });

    it('excludes soft-deleted users', () => {
      expect(json).toContain('deletedAt');
    });

    it('excludes suspended, deactivated and banned accounts', () => {
      expect(json).toContain('SUSPENDED');
      expect(json).toContain('DEACTIVATED');
      expect(json).toContain('BANNED');
    });

    it('excludes incomplete profiles', () => {
      expect(json).toContain('isProfileComplete');
    });

    it('excludes blocked users in both directions', () => {
      expect(json).toContain('blocked');
    });

    it('has no scoring weight capable of reinstating an excluded candidate', () => {
      // Every weight is a positive contribution to an ordering, never a filter.
      for (const w of Object.values(MATCHING_WEIGHTS)) {
        expect(w).toBeGreaterThan(0);
      }
    });
  });

  describe('signal architecture', () => {
    it('pins every weight and the 60/40 blend at their v1 values', () => {
      expect({ ...MATCHING_WEIGHTS }).toEqual({
        age: 14,
        religion: 12,
        community: 11,
        motherTongue: 9,
        location: 9,
        education: 8,
        profession: 7,
        maritalStatus: 6,
        height: 5,
        lifestyle: 4,
        profileCompleteness: 6,
        verification: 6,
        activity: 3,
      });
      expect({ ...MUTUAL_BLEND }).toEqual({
        seekerToCandidate: 0.6,
        candidateToSeeker: 0.4,
      });
    });

    it('blends exactly 60/40: round(0.6 x seekerFit + 0.4 x mutualFit)', () => {
      const seeker = profile({ userId: 'me', religion: 'Christian' });
      const candidate = profile({
        preference: preference({ preferredReligions: ['Hindu'] }),
      });
      const r = svc.score(seeker, preference(), candidate);
      expect(r.mutualFit).not.toBeNull();
      expect(r.seekerFit).not.toBe(r.mutualFit);
      expect(r.overall).toBe(
        Math.round(r.seekerFit * 0.6 + (r.mutualFit as number) * 0.4),
      );
    });

    it('emits all 13 components once each, preference signal first, in a fixed order', () => {
      const r = svc.score(profile({ userId: 'me' }), preference(), profile());
      expect(r.components.map((c) => c.key)).toEqual([
        ...PREFERENCE_COMPATIBILITY_SIGNAL.keys,
        ...CANDIDATE_QUALITY_SIGNAL.keys,
      ]);
      expect(new Set(r.components.map((c) => c.key))).toEqual(
        new Set(Object.keys(MATCHING_WEIGHTS)),
      );
      expect(PREFERENCE_COMPATIBILITY_SIGNAL.kind).toBe('compatibility');
      expect(CANDIDATE_QUALITY_SIGNAL.kind).toBe('quality');
    });

    it('stamps the algorithm version on every result', () => {
      expect(MATCHING_ALGORITHM_VERSION).toBe('v1.2-preference');
      const r = svc.score(profile({ userId: 'me' }), null, profile());
      expect(r.algorithmVersion).toBe('v1.2-preference');
    });
  });

  describe('matched / unmatched preferences', () => {
    it('lists every stated preference as matched for an exact match', () => {
      const r = svc.score(profile({ userId: 'me' }), preference(), profile());
      expect(r.matchedPreferences).toEqual([
        'age',
        'religion',
        'community',
        'motherTongue',
        'location',
        'education',
        'profession',
        'maritalStatus',
        'height',
      ]);
      expect(r.unmatchedPreferences).toEqual([]);
    });

    it('lists missed and partially met preferences as unmatched', () => {
      const r = svc.score(
        profile({ userId: 'me' }),
        // City only, so the right state earns partial (0.5) credit.
        preference({ preferredStates: [] }),
        profile({ religion: 'Christian', currentCity: 'Madurai' }),
      );
      const location = r.components.find((c) => c.key === 'location');
      expect(location?.ratio).toBe(0.5);
      expect(r.unmatchedPreferences).toEqual(['religion', 'location']);
      expect(r.matchedPreferences).not.toContain('religion');
      expect(r.matchedPreferences).not.toContain('location');
    });

    it('lists unstated preferences in neither list', () => {
      const r = svc.score(
        profile({ userId: 'me' }),
        { minAge: 25, maxAge: 32 },
        profile(),
      );
      expect(r.matchedPreferences).toEqual(['age']);
      expect(r.unmatchedPreferences).toEqual([]);
    });

    it('never reports candidate-quality components as preferences', () => {
      const r = svc.score(
        profile({ userId: 'me' }),
        null,
        profile({ profileCompletePct: 10, trustScore: 0 }),
      );
      expect(r.matchedPreferences).toEqual([]);
      expect(r.unmatchedPreferences).toEqual([]);
    });
  });

  describe('scoring reads preferences the way the filter does', () => {
    it('matches a "Never Married" label against the stored NEVER_MARRIED', () => {
      // The picker writes labels; the column holds the enum. The filter always
      // normalised them, so it accepted these candidates — and scoring then
      // marked every one of them a mismatch.
      const r = svc.score(
        profile({ userId: 'me' }),
        preference({ maritalStatusPref: ['Never Married'] }),
        profile({ maritalStatus: 'NEVER_MARRIED' }),
      );
      const marital = r.components.find((c) => c.key === 'maritalStatus');
      expect(marital).toMatchObject({ applicable: true, ratio: 1 });
      expect(r.matchedPreferences).toContain('maritalStatus');
    });

    it('still scores a different marital status as a mismatch', () => {
      const r = svc.score(
        profile({ userId: 'me' }),
        preference({ maritalStatusPref: ['Never Married'] }),
        profile({ maritalStatus: 'DIVORCED' }),
      );
      const marital = r.components.find((c) => c.key === 'maritalStatus');
      expect(marital).toMatchObject({ applicable: true, ratio: 0 });
    });

    it(`treats "Doesn't Matter" as no marital preference at all`, () => {
      const r = svc.score(
        profile({ userId: 'me' }),
        preference({ maritalStatusPref: ["Doesn't Matter"] }),
        profile({ maritalStatus: 'DIVORCED' }),
      );
      const marital = r.components.find((c) => c.key === 'maritalStatus');
      expect(marital?.applicable).toBe(false);
    });

    it(`scores "Same State" against the seeker's STATE, not their city`, () => {
      // Seeker in Chennai; candidate elsewhere in Tamil Nadu. The filter routes
      // "Same State" to the state column and accepts her — scoring used to
      // resolve it to the seeker's city and give only partial credit.
      const r = svc.score(
        profile({ userId: 'me', currentCity: 'Chennai' }),
        preference({ preferredCities: ['Same State'], preferredStates: [] }),
        profile({ currentCity: 'Madurai', currentState: 'Tamil Nadu' }),
      );
      const location = r.components.find((c) => c.key === 'location');
      expect(location).toMatchObject({ applicable: true, ratio: 1 });
    });

    it('still scores a different state as a location mismatch under "Same State"', () => {
      const r = svc.score(
        profile({ userId: 'me', currentState: 'Tamil Nadu' }),
        preference({ preferredCities: ['Same State'], preferredStates: [] }),
        profile({ currentCity: 'Bengaluru', currentState: 'Karnataka' }),
      );
      const location = r.components.find((c) => c.key === 'location');
      expect(location).toMatchObject({ applicable: true, ratio: 0 });
    });

    it('agrees with the filter on every marital label the picker offers', () => {
      // One vocabulary, one interpretation: whatever the WHERE builder turns a
      // label into is what scoring compares against.
      for (const label of ['Never Married', 'Divorced', 'Widowed', 'Awaiting Divorce']) {
        const where = JSON.stringify(
          buildFeedWhere({
            currentUserId: 'me',
            myGender: 'MALE',
            self: null,
            pref: { maritalStatusPref: [label] },
          }),
        );
        const stored = label.toUpperCase().replace(/ /g, '_');
        expect(where).toContain(stored);
        const r = svc.score(
          profile({ userId: 'me' }),
          preference({ maritalStatusPref: [label] }),
          profile({ maritalStatus: stored }),
        );
        expect(r.components.find((c) => c.key === 'maritalStatus')?.ratio).toBe(1);
      }
    });
  });
});
