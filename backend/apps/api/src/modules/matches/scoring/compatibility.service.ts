import { Injectable } from '@nestjs/common';
import {
  isLiteral,
  resolveValues,
  type PreferenceFilters,
  type SelfAttributes,
} from '../filters/partner-preference-where.builder';
import {
  ACTIVITY_DECAY_DAYS,
  MATCHING_WEIGHTS,
  MUTUAL_BLEND,
  scoreBand,
  type ScoreKey,
} from './matching-weights.config';

/**
 * The attributes of one person that scoring reads. Deliberately a plain shape
 * rather than a Prisma row: it keeps this service a pure function of its
 * inputs, so it needs no database, no mocks, and can be unit-tested against
 * hand-written objects.
 */
export interface ScorableProfile {
  userId: string;
  dob: Date | null;
  heightCm: number | null;
  religion: string | null;
  caste: string | null;
  community: string | null;
  motherTongue: string | null;
  highestEducation: string | null;
  profession: string | null;
  currentCity: string | null;
  currentState: string | null;
  maritalStatus: string | null;
  dietaryHabits: string | null;
  smokingHabits: string | null;
  drinkingHabits: string | null;
  profileCompletePct: number | null;
  /** User.trustScore, 0-100. */
  trustScore: number | null;
  /** Proxy for activity — see ACTIVITY_NOTE in the weights config. */
  updatedAt: Date | null;
  /** The candidate's own saved preference, needed for the mutual direction. */
  preference: PreferenceFilters | null;
}

/** One dimension's contribution, kept so the score can be explained. */
export interface ScoreComponent {
  key: ScoreKey;
  /** 0-1 before weighting. */
  ratio: number;
  weight: number;
  /** ratio × weight. */
  points: number;
  /** False when neither side stated anything — excluded from the total. */
  applicable: boolean;
}

export interface CompatibilityBreakdown {
  /** 0-100, seeker's preferences against the candidate. */
  seekerFit: number;
  /** 0-100, candidate's preferences against the seeker. Null when the
   *  candidate has saved no preference at all. */
  mutualFit: number | null;
  /** 0-100 blended headline number. */
  overall: number;
  band: string;
  components: ScoreComponent[];
}

const MS_PER_DAY = 86_400_000;

/**
 * Turns two profiles into a 0-100 compatibility score.
 *
 * Three rules shape the whole design:
 *
 *  1. Nothing here filters. Hard eligibility — blocks, bans, deletions,
 *     gender, incomplete profiles, declined interests — stays in
 *     eligibility.builder. A candidate that reaches this service has
 *     already been proven eligible; scoring only decides ORDER. Moving a
 *     safety rule in here would make it silently bypassable by a weight change.
 *
 *  2. An unstated preference is not a failure. If the seeker never set a
 *     religion preference, religion is marked inapplicable and its weight is
 *     removed from the denominator rather than scored as zero. Otherwise every
 *     member who skipped half the preference form would score ~40% against
 *     everyone, and the ranking would measure form-filling rather than fit.
 *
 *  3. Preference vocabulary is interpreted in exactly one place. `resolveValues`
 *     and `isLiteral` are imported from the WHERE builder — the same functions
 *     the filter uses. "Any Caste" is meaningless in both, "Same City" resolves
 *     to the seeker's own city in both, and a grouped UI label like
 *     "Software / IT" is non-literal in both. A second interpretation here
 *     would eventually disagree with the filter, and a candidate would be
 *     filtered in but scored as a mismatch.
 */
@Injectable()
export class CompatibilityService {
  /** Full breakdown for one pair. Pure — no I/O, safe to call in a loop. */
  score(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidate: ScorableProfile,
  ): CompatibilityBreakdown {
    const components = this.components(seeker, seekerPreference, candidate);
    const seekerFit = this.total(components);

    // The reverse direction reuses the identical component logic with the
    // roles swapped, so "does she meet my preferences" and "do I meet hers"
    // can never drift apart.
    const mutualFit = candidate.preference
      ? this.total(this.components(candidate, candidate.preference, seeker))
      : null;

    const overall =
      mutualFit === null
        ? seekerFit
        : Math.round(
            seekerFit * MUTUAL_BLEND.seekerToCandidate +
              mutualFit * MUTUAL_BLEND.candidateToSeeker,
          );

    return { seekerFit, mutualFit, overall, band: scoreBand(overall), components };
  }

  /** Scores a page of candidates against one seeker. */
  scoreMany(
    seeker: ScorableProfile,
    seekerPreference: PreferenceFilters | null,
    candidates: ScorableProfile[],
  ): Map<string, CompatibilityBreakdown> {
    const out = new Map<string, CompatibilityBreakdown>();
    for (const c of candidates) {
      out.set(c.userId, this.score(seeker, seekerPreference, c));
    }
    return out;
  }

  // ── internals ──────────────────────────────────────────────────────────

  /**
   * Weighted mean over applicable components only. Dividing by the applicable
   * weight rather than by 100 is what implements rule 2 above: a seeker who
   * stated three preferences is scored out of those three.
   */
  private total(components: ScoreComponent[]): number {
    let earned = 0;
    let possible = 0;
    for (const c of components) {
      if (!c.applicable) continue;
      earned += c.points;
      possible += c.weight;
    }
    if (possible === 0) return 0;
    return Math.round((earned / possible) * 100);
  }

  private components(
    seeker: ScorableProfile,
    pref: PreferenceFilters | null,
    candidate: ScorableProfile,
  ): ScoreComponent[] {
    const self: SelfAttributes = {
      caste: seeker.caste,
      currentCity: seeker.currentCity,
      currentState: seeker.currentState,
      motherTongue: seeker.motherTongue,
    };

    return [
      this.ageComponent(pref, candidate),
      this.listComponent('religion', pref?.preferredReligions, candidate.religion, null),
      this.communityComponent(pref, candidate, self),
      this.listComponent('motherTongue', pref?.preferredMotherTongues, candidate.motherTongue, self.motherTongue ?? null),
      this.locationComponent(pref, candidate, self),
      this.listComponent('education', pref?.preferredEducation, candidate.highestEducation, null),
      this.listComponent('profession', pref?.preferredOccupations, candidate.profession, null),
      this.listComponent('maritalStatus', pref?.maritalStatusPref, candidate.maritalStatus, null),
      this.heightComponent(pref, candidate),
      this.lifestyleComponent(pref, candidate),
      this.completenessComponent(candidate),
      this.verificationComponent(candidate),
      this.activityComponent(candidate),
    ];
  }

  private make(key: ScoreKey, ratio: number, applicable: boolean): ScoreComponent {
    const weight = MATCHING_WEIGHTS[key];
    const clamped = Math.max(0, Math.min(1, ratio));
    return {
      key,
      ratio: applicable ? clamped : 0,
      weight,
      points: applicable ? clamped * weight : 0,
      applicable,
    };
  }

  /**
   * Inside the stated band scores 1. Outside it decays rather than dropping to
   * zero, because a candidate one year over a stated maximum is a far better
   * suggestion than one ten years over, and a cliff edge would rank them the
   * same.
   */
  private ageComponent(pref: PreferenceFilters | null, candidate: ScorableProfile): ScoreComponent {
    const min = pref?.minAge ?? null;
    const max = pref?.maxAge ?? null;
    const age = this.ageOf(candidate.dob);
    if (age === null || (min === null && max === null)) {
      return this.make('age', 0, false);
    }
    const lo = min ?? 0;
    const hi = max ?? 200;
    if (age >= lo && age <= hi) return this.make('age', 1, true);
    const overshoot = age < lo ? lo - age : age - hi;
    // 5 years outside the band = no credit.
    return this.make('age', 1 - overshoot / 5, true);
  }

  private heightComponent(pref: PreferenceFilters | null, candidate: ScorableProfile): ScoreComponent {
    const min = pref?.minHeightCm ?? null;
    const max = pref?.maxHeightCm ?? null;
    const h = candidate.heightCm;
    if (h === null || (min === null && max === null)) {
      return this.make('height', 0, false);
    }
    const lo = min ?? 0;
    const hi = max ?? 300;
    if (h >= lo && h <= hi) return this.make('height', 1, true);
    const overshoot = h < lo ? lo - h : h - hi;
    // 10 cm outside the band = no credit.
    return this.make('height', 1 - overshoot / 10, true);
  }

  /**
   * Membership against a preference list, using the WHERE builder's own
   * resolution so "Any …" is ignored and "Same X" resolves identically.
   * An empty resolved list means nothing matchable was stated.
   */
  private listComponent(
    key: ScoreKey,
    raw: unknown,
    candidateValue: string | null,
    ownValue: string | null,
  ): ScoreComponent {
    const wanted = resolveValues(raw, ownValue);
    if (wanted.length === 0 || !candidateValue) return this.make(key, 0, false);
    const hit = wanted.some(
      (w) => w.trim().toLowerCase() === candidateValue.trim().toLowerCase(),
    );
    return this.make(key, hit ? 1 : 0, true);
  }

  /** Caste preference, checked against caste then community. */
  private communityComponent(
    pref: PreferenceFilters | null,
    candidate: ScorableProfile,
    self: SelfAttributes,
  ): ScoreComponent {
    const wanted = resolveValues(pref?.preferredCastes, self.caste);
    if (wanted.length === 0) return this.make('community', 0, false);
    const values = [candidate.caste, candidate.community].filter(
      (v): v is string => typeof v === 'string' && v.trim().length > 0,
    );
    if (values.length === 0) return this.make('community', 0, false);
    const hit = wanted.some((w) =>
      values.some((v) => v.trim().toLowerCase() === w.trim().toLowerCase()),
    );
    return this.make('community', hit ? 1 : 0, true);
  }

  /** City is a full match; same state is partial credit, not zero. */
  private locationComponent(
    pref: PreferenceFilters | null,
    candidate: ScorableProfile,
    self: SelfAttributes,
  ): ScoreComponent {
    const cities = resolveValues(pref?.preferredCities, self.currentCity);
    const states = resolveValues(pref?.preferredStates, self.currentState);
    if (cities.length === 0 && states.length === 0) {
      return this.make('location', 0, false);
    }
    const eq = (a: string | null, b: string): boolean =>
      typeof a === 'string' && a.trim().toLowerCase() === b.trim().toLowerCase();

    if (cities.some((c) => eq(candidate.currentCity, c))) {
      return this.make('location', 1, true);
    }
    if (states.some((s) => eq(candidate.currentState, s))) {
      return this.make('location', 1, true);
    }
    // Right state, wrong city — meaningfully closer than a different state.
    if (cities.length > 0 && eq(candidate.currentState ?? null, self.currentState ?? '')) {
      return this.make('location', 0.5, true);
    }
    return this.make('location', 0, true);
  }

  /**
   * Diet, smoking and drinking, read from extendedPreferences — the JSON blob
   * the standalone Partner Preferences page writes. Only keys that resolve to
   * a literal value count, so a UI placeholder never becomes a requirement.
   */
  private lifestyleComponent(
    pref: PreferenceFilters | null,
    candidate: ScorableProfile,
  ): ScoreComponent {
    const ext = this.asRecord(pref?.extendedPreferences);
    const pairs: Array<[unknown, string | null]> = [
      [ext.dietPref ?? ext.diet, candidate.dietaryHabits],
      [ext.smokingPref ?? ext.smoking, candidate.smokingHabits],
      [ext.drinkingPref ?? ext.drinking, candidate.drinkingHabits],
    ];

    let stated = 0;
    let matched = 0;
    for (const [want, have] of pairs) {
      if (typeof want !== 'string' || !isLiteral(want) || !have) continue;
      stated++;
      if (want.trim().toLowerCase() === have.trim().toLowerCase()) matched++;
    }
    if (stated === 0) return this.make('lifestyle', 0, false);
    return this.make('lifestyle', matched / stated, true);
  }

  /** Always applicable — a candidate-quality signal, not a preference. */
  private completenessComponent(candidate: ScorableProfile): ScoreComponent {
    return this.make('profileCompleteness', (candidate.profileCompletePct ?? 0) / 100, true);
  }

  private verificationComponent(candidate: ScorableProfile): ScoreComponent {
    return this.make('verification', (candidate.trustScore ?? 0) / 100, true);
  }

  /** Linear decay to zero over ACTIVITY_DECAY_DAYS. Proxy data — see the note. */
  private activityComponent(candidate: ScorableProfile): ScoreComponent {
    if (!candidate.updatedAt) return this.make('activity', 0, false);
    const days = (Date.now() - candidate.updatedAt.getTime()) / MS_PER_DAY;
    return this.make('activity', 1 - days / ACTIVITY_DECAY_DAYS, true);
  }

  private ageOf(dob: Date | null): number | null {
    if (!dob) return null;
    const ms = Date.now() - dob.getTime();
    if (ms <= 0) return null;
    return Math.floor(ms / (365.25 * MS_PER_DAY));
  }

  private asRecord(value: unknown): Record<string, unknown> {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }
}
