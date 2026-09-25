import { calculatePsychologyCompatibility } from '../scoring/psychology-compatibility.calculator';
import type { ScoringQuestion } from '../scoring/psychology-compatibility.types';
import {
  QUESTION_IDS,
  SCORING_QUESTIONS,
  SEEDED_QUESTIONS,
  allAnswered,
  withAnswers,
} from './psychology-fixtures';

/** The real seeded questions, including their real pairRules. */
const REAL = SEEDED_QUESTIONS.map((q) => ({
  id: q.id,
  order: q.order,
  dimension: q.dimension,
  scoringType: q.scoringType,
  pairRules: q.pairRules,
}));
const [Q1] = REAL;
const Q9 = REAL[8];
const Q10 = REAL[9];

function question(
  base: ScoringQuestion,
  overrides: Partial<ScoringQuestion>,
): ScoringQuestion {
  return { ...base, ...overrides };
}

describe('calculatePsychologyCompatibility — hardening against malformed stored data', () => {
  it.each([
    ['null', null],
    ['undefined', undefined],
    ['an array', ['A']],
    ['a string', 'ABC'],
  ])(
    'reads answers that are %s as "unanswered" instead of throwing',
    (_label, bad) => {
      const asA = calculatePsychologyCompatibility(
        REAL,
        bad as never,
        allAnswered('A'),
      );
      const asB = calculatePsychologyCompatibility(
        REAL,
        allAnswered('A'),
        bad as never,
      );
      for (const r of [asA, asB]) {
        expect(r.overallScore).toBeNull();
        expect(r.complete).toBe(false);
        expect(r.skippedQuestionIds).toHaveLength(REAL.length);
      }
    },
  );

  it('treats non-string answer values as unanswered', () => {
    const r = calculatePsychologyCompatibility(
      [Q1],
      { [Q1.id]: 7 },
      { [Q1.id]: 'A' },
    );
    expect(r.skippedQuestionIds).toEqual([Q1.id]);
  });

  it('does not resolve inherited names such as "constructor" as ids, answers or matrix cells', () => {
    const weird = question(Q1, { id: 'constructor' });
    const r = calculatePsychologyCompatibility(
      [weird],
      { constructor: 'A' },
      { constructor: 'A' },
    );
    expect(r.skippedQuestionIds).toEqual(['constructor']);

    const r2 = calculatePsychologyCompatibility(
      [Q1],
      { [Q1.id]: 'constructor' },
      { [Q1.id]: 'A' },
    );
    expect(r2.skippedQuestionIds).toEqual([Q1.id]);
  });

  it.each([
    [
      'entries missing .pair',
      [{ severity: 'soft', type: 'flag', message: 'm' }],
    ],
    ['a non-array', { a: 1 }],
    ['null', null],
    ['entries that are not objects', ['x', 5, null]],
  ])(
    'ignores pairRules that are %s and still scores the question',
    (_label, bad) => {
      const broken = question(Q1, { pairRules: bad });
      const r = calculatePsychologyCompatibility(
        [broken],
        { [Q1.id]: 'A' },
        { [Q1.id]: 'B' },
      );
      expect(r.breakdown).toHaveLength(1);
      expect(r.flags).toEqual([]);
      expect(r.complete).toBe(true);
    },
  );

  it('keeps the good rules when only some are malformed', () => {
    const mixed = question(Q1, {
      pairRules: [
        { severity: 'soft' },
        { pair: ['A', 'B'], type: 'flag', severity: 'soft', message: 'ok' },
      ],
    });
    const r = calculatePsychologyCompatibility(
      [mixed],
      { [Q1.id]: 'A' },
      { [Q1.id]: 'B' },
    );
    expect(r.flags.map((f) => f.message)).toEqual(['ok']);
  });
});

describe('calculatePsychologyCompatibility — complete', () => {
  it('is true only when every supplied question was scored', () => {
    const r = calculatePsychologyCompatibility(
      REAL,
      allAnswered('A'),
      allAnswered('C'),
    );
    expect(r.complete).toBe(true);
    expect(r.breakdown).toHaveLength(10);
  });

  it('is false when any question is skipped, and for no questions at all', () => {
    const partial = allAnswered('A');
    delete partial[QUESTION_IDS[4]];
    expect(
      calculatePsychologyCompatibility(REAL, partial, allAnswered('A'))
        .complete,
    ).toBe(false);
    expect(calculatePsychologyCompatibility([], {}, {}).complete).toBe(false);
  });

  it('is false for an answer key outside the matrix', () => {
    expect(
      calculatePsychologyCompatibility(
        REAL,
        allAnswered('A'),
        withAnswers(allAnswered('A'), { 3: 'Z' }),
      ).complete,
    ).toBe(false);
  });
});

describe('calculatePsychologyCompatibility — hard-axis ceiling is driven by scoringType', () => {
  it("still applies when the hard-axis question's dimension is renamed", () => {
    const renamed = question(Q9, { dimension: 'kids_renamed' });
    const r = calculatePsychologyCompatibility(
      [Q1, renamed],
      { [Q1.id]: 'A', [Q9.id]: 'A' },
      { [Q1.id]: 'A', [Q9.id]: 'D' },
    );
    expect(r.ceilingApplied).toBe(true);
    expect(r.overallScore).toBe(40);
  });

  it('does not apply to a question that is not HARD_AXIS, even if its dimension is "children"', () => {
    const notHard = question(Q9, { scoringType: 'MUST_ALIGN' });
    const r = calculatePsychologyCompatibility(
      [Q1, notHard],
      { [Q1.id]: 'A', [Q9.id]: 'A' },
      { [Q1.id]: 'A', [Q9.id]: 'D' },
    );
    expect(r.ceilingApplied).toBe(false);
  });

  it('applies to the real seeded quiz: Q9 A|D on otherwise perfect agreement is capped at 40', () => {
    const r = calculatePsychologyCompatibility(
      REAL,
      allAnswered('A'),
      withAnswers(allAnswered('A'), { 9: 'D' }),
    );
    expect(r.ceilingApplied).toBe(true);
    expect(r.overallScore).toBe(40);
  });
});

describe('calculatePsychologyCompatibility — escalation only raises severity', () => {
  it('never lowers a Q10 flag that is already above "high"', () => {
    const q10Hard = question(Q10, {
      pairRules: [
        {
          pair: ['B', 'D'],
          type: 'dealbreaker',
          severity: 'hard',
          message: 'x',
        },
      ],
    });
    const r = calculatePsychologyCompatibility(
      [Q9, q10Hard],
      { [Q9.id]: 'A', [Q10.id]: 'B' },
      { [Q9.id]: 'D', [Q10.id]: 'D' },
    );
    const flag = r.flags.find((f) => f.dimension === 'life_stage_timeline')!;
    expect(flag.severity).toBe('hard');
  });

  it('raises a medium Q10 flag to high when the hard-axis question also flagged', () => {
    const r = calculatePsychologyCompatibility(
      [Q9, Q10],
      { [Q9.id]: 'A', [Q10.id]: 'B' },
      { [Q9.id]: 'D', [Q10.id]: 'D' },
    );
    const flag = r.flags.find((f) => f.dimension === 'life_stage_timeline')!;
    expect(flag.severity).toBe('high');
    expect(flag.message).toMatch(/escalated/);
  });
});

describe('calculatePsychologyCompatibility — includeFlags: false', () => {
  it('returns the same score, ceiling and completeness with no flags', () => {
    const a = withAnswers(allAnswered('A'), { 10: 'B' });
    const b = withAnswers(allAnswered('B'), { 9: 'D', 10: 'D' });
    const withFlags = calculatePsychologyCompatibility(REAL, a, b);
    const without = calculatePsychologyCompatibility(REAL, a, b, {
      includeFlags: false,
    });

    expect(withFlags.flags.length).toBeGreaterThan(0);
    expect(without.flags).toEqual([]);
    expect(without.overallScore).toBe(withFlags.overallScore);
    expect(without.ceilingApplied).toBe(withFlags.ceilingApplied);
    expect(without.complete).toBe(withFlags.complete);
  });

  it('never reads pairRules', () => {
    const trap = { ...SCORING_QUESTIONS[0] } as ScoringQuestion;
    Object.defineProperty(trap, 'pairRules', {
      get() {
        throw new Error('pairRules was read');
      },
    });
    expect(() =>
      calculatePsychologyCompatibility(
        [trap],
        { [trap.id]: 'A' },
        { [trap.id]: 'A' },
        { includeFlags: false },
      ),
    ).not.toThrow();
  });
});

describe('calculatePsychologyCompatibility — determinism', () => {
  it('is independent of the order questions are supplied in', () => {
    const a = withAnswers(allAnswered('A'), { 2: 'C', 7: 'D' });
    const b = withAnswers(allAnswered('C'), { 4: 'B', 9: 'D' });
    const forward = calculatePsychologyCompatibility(REAL, a, b);
    const reversed = calculatePsychologyCompatibility(
      [...REAL].reverse(),
      a,
      b,
    );
    expect(JSON.stringify(reversed)).toEqual(JSON.stringify(forward));
  });

  it('gives the same result whichever user is A and which is B', () => {
    const a = withAnswers(allAnswered('A'), { 2: 'C', 7: 'D' });
    const b = withAnswers(allAnswered('C'), { 4: 'B', 9: 'D' });
    const ab = calculatePsychologyCompatibility(REAL, a, b);
    const ba = calculatePsychologyCompatibility(REAL, b, a);
    expect(ba.overallScore).toBe(ab.overallScore);
    expect(ba.ceilingApplied).toBe(ab.ceilingApplied);
  });
});
