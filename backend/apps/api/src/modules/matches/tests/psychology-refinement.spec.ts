import * as calculator from '../../psychology/scoring/psychology-compatibility.calculator';
import { resetWarnThrottle } from '../../psychology/scoring/psychology-log';
import {
  QUESTION_IDS,
  SCORING_QUESTIONS,
  allAnswered,
  withAnswers,
} from '../../psychology/tests/psychology-fixtures';
import type { PreferenceFilters } from '../filters/partner-preference-where.builder';
import { CompatibilityService } from '../scoring/compatibility.service';
import type { ScorableProfile } from '../scoring/compatibility-signal';
import {
  MATCHING_WEIGHTS,
  PSYCHOLOGY_REFINEMENT,
  totalWeight,
} from '../scoring/matching-weights.config';
import {
  psychologyPairScore,
  psychologyRefinement,
} from '../scoring/psychology/psychology-refinement';
import { RankingService } from '../scoring/ranking.service';
import type { RankedCandidate } from '../scoring/ranking.service';

const svc = new CompatibilityService();
const ranking = new RankingService();

const DAY = 86_400_000;

// A fixed clock: the activity component reads Date.now(), so without this two
// score() calls a millisecond apart could differ and make equality flaky.
const NOW = new Date('2026-06-15T12:00:00.000Z');
beforeAll(() => {
  jest.useFakeTimers({ now: NOW });
});
afterAll(() => {
  jest.useRealTimers();
});

function profile(
  userId: string,
  overrides: Partial<ScorableProfile> = {},
): ScorableProfile {
  return {
    userId,
    dob: new Date('1996-01-01'),
    heightCm: 170,
    religion: 'Hindu',
    caste: null,
    community: null,
    motherTongue: 'Tamil',
    highestEducation: null,
    profession: null,
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    maritalStatus: 'NEVER_MARRIED',
    dietaryHabits: null,
    smokingHabits: null,
    drinkingHabits: null,
    profileCompletePct: 100,
    trustScore: 60,
    updatedAt: new Date(Date.now() - 2 * DAY),
    preference: null,
    ...overrides,
  };
}

/** A seeker who states a few preferences, the ordinary case. */
const PREF: PreferenceFilters = {
  minAge: 25,
  maxAge: 32,
  preferredReligions: ['Hindu'],
  preferredMotherTongues: ['Tamil'],
  preferredStates: ['Tamil Nadu'],
};

const A = allAnswered('A');
const A_D_HARD_AXIS = withAnswers(allAnswered('A'), { 9: 'D' }); // Q9 A|D against A
const MID = withAnswers(allAnswered('C'), { 3: 'B', 8: 'A' });

/** score() with psychology fully enabled, and the same pair without it. */
function both(
  seekerAnswers: Record<string, string> | null | undefined,
  candidateAnswers: Record<string, string> | null | undefined,
  candidatePreference: PreferenceFilters | null = null,
) {
  const seeker = profile('me', { psychologyAnswers: seekerAnswers });
  const candidate = profile('them', {
    psychologyAnswers: candidateAnswers,
    preference: candidatePreference,
  });
  const withPsych = svc.score(seeker, PREF, candidate, SCORING_QUESTIONS);
  const baseline = svc.score(
    profile('me', { preference: null }),
    PREF,
    profile('them', { preference: candidatePreference }),
  );
  return { withPsych, baseline };
}

/** A candidate whose breakdown predates the ranking key (only visible scores). */
function bare(userId: string, overall: number): RankedCandidate {
  return {
    row: { userId },
    score: { overall, mutualFit: null } as unknown as RankedCandidate['score'],
  };
}

describe('the 100-point model is the foundation, and psychology is not in it', () => {
  it('weights sum to exactly 100 again (not 115)', () => {
    expect(totalWeight()).toBe(100);
  });

  it('psychology has no weight and no score component', () => {
    expect(Object.keys(MATCHING_WEIGHTS)).not.toContain('psychology');
    const r = svc.score(profile('me'), PREF, profile('them'));
    expect(r.components).toHaveLength(13);
    expect(r.components.map((c) => c.key)).not.toContain('psychology');
  });

  it('a component of the quality/preference model reads the same with or without quiz data', () => {
    const { withPsych, baseline } = both(A, A);
    expect(withPsych.components).toEqual(baseline.components);
  });
});

describe('psychology never lowers a member for not taking the quiz', () => {
  it.each<
    [
      string,
      Record<string, string> | null | undefined,
      Record<string, string> | null | undefined,
    ]
  >([
    ['neither member took it', null, null],
    ['neither member took it (undefined)', undefined, undefined],
    ['only the seeker took it', A, null],
    ['only the candidate took it', null, A],
  ])(
    '%s: every score and the ranking key equal the no-psychology score',
    (_l, s, c) => {
      const { withPsych, baseline } = both(s, c);

      expect(withPsych.seekerFit).toBe(baseline.seekerFit);
      expect(withPsych.mutualFit).toBe(baseline.mutualFit);
      expect(withPsych.overall).toBe(baseline.overall);
      expect(withPsych.band).toBe(baseline.band);
      expect(withPsych.ranking.psychologyRefinement).toBe(0);
      expect(withPsych.ranking.overall).toBe(baseline.overall);
      expect(withPsych.ranking.mutualFit).toBe(baseline.mutualFit);
    },
  );

  it('holds with a mutual (candidate-side) preference too', () => {
    const { withPsych, baseline } = both(A, null, PREF);
    expect(withPsych.ranking.mutualFit).toBe(baseline.mutualFit);
    expect(withPsych.ranking.overall).toBe(baseline.overall);
    expect(withPsych.ranking.mutualFit).not.toBeNull();
  });

  it('a non-taker is never ranked below an otherwise identical taker whose pair is merely average or worse', () => {
    // Average / weak pairs (no hard-axis conflict) are worth exactly 0, never
    // negative: the taker gets no less than the non-taker would.
    // (All-D would be a Q9 A|D hard-axis conflict; that one case is
    // deliberately negative and is covered separately.)
    const weak = withAnswers(allAnswered('D'), { 9: 'C' });
    for (const answers of [MID, allAnswered('B'), weak]) {
      const { withPsych, baseline } = both(A, answers);
      expect(withPsych.ranking.overall).toBeGreaterThanOrEqual(
        baseline.ranking.overall,
      );
    }
  });

  it('a member who did not take the quiz keeps their full, un-normalised score against a taker', () => {
    // Candidate 'nontaker' vs 'taker' for the same seeker: identical profiles.
    const seeker = profile('me', { psychologyAnswers: A });
    const nonTaker = svc.score(seeker, PREF, profile('n'), SCORING_QUESTIONS);
    const noPsychAtAll = svc.score(profile('me'), PREF, profile('n'));
    expect(nonTaker.seekerFit).toBe(noPsychAtAll.seekerFit);
    expect(nonTaker.overall).toBe(noPsychAtAll.overall);
    expect(nonTaker.ranking.overall).toBe(noPsychAtAll.overall);
  });
});

describe('when both members took the quiz', () => {
  it('leaves every member-visible score exactly as without the quiz (nothing exact leaks)', () => {
    for (const answers of [A, MID, A_D_HARD_AXIS]) {
      const { withPsych, baseline } = both(A, answers, PREF);
      expect(withPsych.seekerFit).toBe(baseline.seekerFit);
      expect(withPsych.mutualFit).toBe(baseline.mutualFit);
      expect(withPsych.overall).toBe(baseline.overall);
      expect(withPsych.band).toBe(baseline.band);
      expect(withPsych.matchedPreferences).toEqual(baseline.matchedPreferences);
      expect(withPsych.unmatchedPreferences).toEqual(
        baseline.unmatchedPreferences,
      );
    }
  });

  it('adds a small bonus for a strong pair, on the ranking key only', () => {
    const { withPsych, baseline } = both(A, A);
    expect(withPsych.ranking.psychologyRefinement).toBeGreaterThan(0);
    expect(withPsych.ranking.overall).toBeCloseTo(
      baseline.overall + withPsych.ranking.psychologyRefinement,
      2,
    );
  });

  it('demotes a hard-axis conflict (the children question dealbreaker)', () => {
    const { withPsych, baseline } = both(A, A_D_HARD_AXIS);
    expect(withPsych.ranking.psychologyRefinement).toBe(
      -PSYCHOLOGY_REFINEMENT.hardAxisPenalty,
    );
    expect(withPsych.ranking.overall).toBe(
      baseline.overall - PSYCHOLOGY_REFINEMENT.hardAxisPenalty,
    );
  });

  it('applies the same refinement to both directions of a mutual score', () => {
    const { withPsych, baseline } = both(A, A, PREF);
    const r = withPsych.ranking.psychologyRefinement;
    expect(withPsych.ranking.mutualFit).toBeCloseTo(
      (baseline.mutualFit as number) + r,
      2,
    );
    expect(withPsych.ranking.overall).toBeCloseTo(baseline.overall + r, 2);
  });

  it('is symmetric: the pair refines the same whichever member is the seeker', () => {
    const ab = psychologyPairScore(A, MID, SCORING_QUESTIONS);
    const ba = psychologyPairScore(MID, A, SCORING_QUESTIONS);
    expect(ba).toEqual(ab);
    expect(psychologyRefinement(ba)).toBe(psychologyRefinement(ab));
  });
});

describe('psychology can refine but never dominate', () => {
  const { neutralScore, maxBonus, hardAxisPenalty } = PSYCHOLOGY_REFINEMENT;

  it('the refinement is bounded: at most +maxBonus, at least -hardAxisPenalty, over every possible pair', () => {
    // Exhaustive over the interesting axes + a large random sweep of the rest.
    const keys = ['A', 'B', 'C', 'D'];
    let min = Infinity;
    let max = -Infinity;
    let negativeWithoutConflict = 0;
    for (let i = 0; i < 20_000; i++) {
      const a: Record<string, string> = {};
      const b: Record<string, string> = {};
      for (const id of QUESTION_IDS) {
        a[id] = keys[Math.floor(Math.random() * 4)];
        b[id] = keys[Math.floor(Math.random() * 4)];
      }
      const pair = psychologyPairScore(a, b, SCORING_QUESTIONS)!;
      const r = psychologyRefinement(pair);
      min = Math.min(min, r);
      max = Math.max(max, r);
      if (r < 0 && !pair.hardAxisConflict) negativeWithoutConflict++;
    }
    expect(max).toBeLessThanOrEqual(maxBonus);
    expect(min).toBeGreaterThanOrEqual(-hardAxisPenalty);
    // Negative ONLY for the declared hard-axis conflict.
    expect(negativeWithoutConflict).toBe(0);
  });

  it('is monotonic: a better pair never refines lower', () => {
    let previous = -Infinity;
    for (let score = 0; score <= 100; score++) {
      const r = psychologyRefinement({ score, hardAxisConflict: false });
      expect(r).toBeGreaterThanOrEqual(previous);
      previous = r;
    }
  });

  it('is exactly 0 at and below the neutral score, and maxBonus at 100', () => {
    for (const score of [0, 30, neutralScore]) {
      expect(psychologyRefinement({ score, hardAxisConflict: false })).toBe(0);
    }
    expect(psychologyRefinement({ score: 100, hardAxisConflict: false })).toBe(
      maxBonus,
    );
  });

  it('sits below the mean of a random pair, so a typical pair is never penalised', () => {
    const keys = ['A', 'B', 'C', 'D'];
    let total = 0;
    const n = 5000;
    for (let i = 0; i < n; i++) {
      const a: Record<string, string> = {};
      const b: Record<string, string> = {};
      for (const id of QUESTION_IDS) {
        a[id] = keys[Math.floor(Math.random() * 4)];
        b[id] = keys[Math.floor(Math.random() * 4)];
      }
      total += psychologyPairScore(a, b, SCORING_QUESTIONS)!.score;
    }
    expect(neutralScore).toBeLessThan(total / n);
  });

  it('a candidate more than (maxBonus + hardAxisPenalty) base points ahead is never overtaken by psychology', () => {
    const gap = maxBonus + hardAxisPenalty + 1;
    const leader = { overall: 80 + gap, refinement: -hardAxisPenalty };
    const chaser = { overall: 80, refinement: maxBonus };
    expect(leader.overall + leader.refinement).toBeGreaterThan(
      chaser.overall + chaser.refinement,
    );
  });

  it('through the real ranker: psychology reorders near-ties, but not a clear leader', () => {
    // Three candidates, all rows equal except quiz data / base fit.
    const seeker = profile('me', { psychologyAnswers: A });
    const close = profile('close', { psychologyAnswers: A });
    const closeNoQuiz = profile('closeNoQuiz'); // same profile, no quiz
    const farAhead = profile('farAhead', {
      profileCompletePct: 100,
      trustScore: 100,
      updatedAt: new Date(),
    });
    const farBehind = profile('farBehind', {
      profileCompletePct: 20,
      trustScore: 0,
      psychologyAnswers: A,
    });

    const scores = svc.scoreMany(
      seeker,
      PREF,
      [close, closeNoQuiz, farAhead, farBehind],
      SCORING_QUESTIONS,
    );
    const rows = ['close', 'closeNoQuiz', 'farAhead', 'farBehind'].map(
      (userId) => ({
        row: { userId, createdAt: new Date('2026-01-01') } as never,
        score: scores.get(userId),
      }),
    );
    const order = ranking
      .rank(rows, 'compatibility', { skip: 0, take: 10 })
      .map((c) => (c.row as { userId: string }).userId);

    // Equal base, one with a strong quiz pair: the quiz taker leads.
    expect(order.indexOf('close')).toBeLessThan(order.indexOf('closeNoQuiz'));
    // A quality/base leader is still ahead of a candidate psychology boosted.
    const overall = (id: string) => scores.get(id)!.overall;
    expect(overall('farAhead')).toBeGreaterThan(overall('farBehind'));
    expect(order.indexOf('farAhead')).toBeLessThan(order.indexOf('farBehind'));
  });
});

describe('ranking uses the refined key; nothing else does', () => {
  function rows(
    entries: Array<{
      id: string;
      overall: number;
      refinement?: number;
      mutual?: number | null;
    }>,
  ) {
    return entries.map((e) => ({
      row: { userId: e.id, createdAt: new Date('2026-01-01') } as never,
      score: {
        seekerFit: e.overall,
        mutualFit: e.mutual ?? null,
        overall: e.overall,
        band: 'x',
        components: [],
        matchedPreferences: [],
        unmatchedPreferences: [],
        algorithmVersion: 'test',
        ranking: {
          overall: e.overall + (e.refinement ?? 0),
          mutualFit: e.mutual == null ? null : e.mutual + (e.refinement ?? 0),
          psychologyRefinement: e.refinement ?? 0,
        },
      },
    }));
  }

  it('orders by visible score + refinement', () => {
    const order = ranking
      .rank(
        rows([
          { id: 'plain', overall: 90 },
          { id: 'boosted', overall: 88, refinement: 4 },
          { id: 'demoted', overall: 95, refinement: -10 },
        ]),
        'compatibility',
        { skip: 0, take: 10 },
      )
      .map((c) => (c.row as { userId: string }).userId);
    // 88+4 = 92 beats 90; 95-10 = 85 is last.
    expect(order).toEqual(['boosted', 'plain', 'demoted']);
  });

  it('for pairs with no refinement the order is exactly the visible-score order, ties broken as before', () => {
    const order = ranking
      .rank(
        rows([
          { id: 'b', overall: 80 },
          { id: 'a', overall: 80 },
          { id: 'c', overall: 85 },
        ]),
        'compatibility',
        { skip: 0, take: 10 },
      )
      .map((c) => (c.row as { userId: string }).userId);
    expect(order).toEqual(['c', 'a', 'b']);
  });

  it('the mutual strategy uses the refined mutual key, falling back to the refined overall', () => {
    const order = ranking
      .rank(
        rows([
          { id: 'noPref', overall: 70, refinement: 6 }, // no mutual: falls back to 76
          { id: 'mutual', overall: 90, mutual: 74 },
        ]),
        'mutual',
        { skip: 0, take: 10 },
      )
      .map((c) => (c.row as { userId: string }).userId);
    expect(order).toEqual(['noPref', 'mutual']);
  });

  it('a breakdown without the ranking key still orders by the visible score', () => {
    const order = ranking
      .rank([bare('x', 10), bare('y', 20)], 'compatibility', {
        skip: 0,
        take: 5,
      })
      .map((c) => (c.row as { userId: string }).userId);
    expect(order).toEqual(['y', 'x']);
  });
});

describe('failure: unavailable, malformed or throwing psychology data', () => {
  beforeEach(() => resetWarnThrottle());
  afterEach(() => jest.restoreAllMocks());

  it.each([
    ['no questions', A, A, undefined],
    ['an empty question list', A, A, []],
    [
      'answers that are not covering the quiz',
      { [QUESTION_IDS[0]]: 'A' },
      A,
      SCORING_QUESTIONS,
    ],
    [
      'answers with an invalid key',
      withAnswers(A, { 4: 'Z' }),
      A,
      SCORING_QUESTIONS,
    ],
  ])(
    '%s: no refinement, and the score is the ordinary one',
    (_l, s, c, questions) => {
      expect(psychologyRefinement(psychologyPairScore(s, c, questions))).toBe(
        0,
      );
    },
  );

  it('a throwing calculator yields no refinement rather than an error, and the ordinary score', () => {
    jest
      .spyOn(calculator, 'calculatePsychologyCompatibility')
      .mockImplementation(() => {
        throw new TypeError('unexpected');
      });

    const seeker = profile('me', { psychologyAnswers: A });
    const candidate = profile('them', { psychologyAnswers: A });
    const failing = svc.score(seeker, PREF, candidate, SCORING_QUESTIONS);
    const plain = svc.score(profile('me'), PREF, profile('them'));

    expect(failing.overall).toBe(plain.overall);
    expect(failing.seekerFit).toBe(plain.seekerFit);
    expect(failing.ranking.overall).toBe(plain.overall);
    expect(failing.ranking.psychologyRefinement).toBe(0);
  });

  it('one failing pair does not disturb the rest of the pool', () => {
    const real = calculator.calculatePsychologyCompatibility;
    let calls = 0;
    jest
      .spyOn(calculator, 'calculatePsychologyCompatibility')
      .mockImplementation((...args) => {
        calls += 1;
        if (calls === 2) throw new Error('bad pair');
        return real(...args);
      });
    const scores = svc.scoreMany(
      profile('me', { psychologyAnswers: A }),
      PREF,
      ['c1', 'c2', 'c3'].map((id) => profile(id, { psychologyAnswers: A })),
      SCORING_QUESTIONS,
    );
    const refinements = ['c1', 'c2', 'c3'].map(
      (id) => scores.get(id)!.ranking.psychologyRefinement,
    );
    expect(refinements[0]).toBeGreaterThan(0);
    expect(refinements[1]).toBe(0);
    expect(refinements[2]).toBeGreaterThan(0);
  });
});
