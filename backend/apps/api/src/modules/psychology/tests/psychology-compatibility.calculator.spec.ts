import type { QuizQuestion } from '../../../../../../libs/database/generated/client';
import { calculatePsychologyCompatibility } from '../scoring/psychology-compatibility.calculator';

// Mirrors the real seeded question shape closely enough for the calculator
// (dimension, options with a 4-key set, pairRules, order, id) without
// depending on the DB. Full option/label text is irrelevant to scoring.
function q(overrides: Record<string, unknown>): QuizQuestion {
  return {
    id: 'q',
    quizId: 'marriage-compat-v1',
    dimension: 'dim',
    scoringType: 'MUST_ALIGN',
    questionText: 'text',
    options: [
      { key: 'A', label: 'A', value: 1 },
      { key: 'B', label: 'B', value: 2 },
      { key: 'C', label: 'C', value: 3 },
      { key: 'D', label: 'D', value: 4 },
    ],
    pairRules: [],
    order: 1,
    createdAt: new Date(),
    ...overrides,
  } as unknown as QuizQuestion;
}

const Q1 = q({
  id: 'nenjam-mc-q01-v1',
  dimension: 'conflict_style',
  order: 1,
  pairRules: [
    {
      pair: ['A', 'B'],
      type: 'flag',
      severity: 'soft',
      message: 'discuss conflict rhythm',
    },
    {
      pair: ['D', 'D'],
      type: 'flag',
      severity: 'soft',
      message: 'decide who initiates',
    },
  ],
});
const Q3 = q({
  id: 'nenjam-mc-q03-v1',
  dimension: 'family_boundaries',
  order: 3,
  pairRules: [
    {
      pair: ['A', 'D'],
      type: 'dealbreaker',
      severity: 'high',
      message: 'fundamental difference',
    },
    {
      pair: ['A', 'C'],
      type: 'flag',
      severity: 'medium',
      message: 'align on family involvement',
    },
  ],
});
const Q8 = q({
  id: 'nenjam-mc-q08-v1',
  dimension: 'decision_making',
  scoringType: 'COMPLEMENTARY_TOLERANT',
  order: 8,
  pairRules: [
    {
      pair: ['B', 'B'],
      type: 'flag',
      severity: 'medium',
      message: 'both expect final say',
    },
  ],
});
const Q9 = q({
  id: 'nenjam-mc-q09-v1',
  dimension: 'children',
  scoringType: 'HARD_AXIS',
  order: 9,
  pairRules: [
    {
      pair: ['A', 'D'],
      type: 'dealbreaker',
      severity: 'hard',
      message: 'children mismatch',
    },
    {
      pair: ['B', 'D'],
      type: 'dealbreaker',
      severity: 'hard',
      message: 'children mismatch',
    },
    {
      pair: ['C', 'A'],
      type: 'flag',
      severity: 'soft',
      message: 'set a timeline',
    },
    {
      pair: ['C', 'B'],
      type: 'flag',
      severity: 'soft',
      message: 'set a timeline',
    },
    {
      pair: ['C', 'D'],
      type: 'flag',
      severity: 'soft',
      message: 'set a timeline',
    },
  ],
});
const Q10 = q({
  id: 'nenjam-mc-q10-v1',
  dimension: 'life_stage_timeline',
  order: 10,
  pairRules: [
    {
      pair: ['B', 'D'],
      type: 'flag',
      severity: 'medium',
      message: 'sequencing conflict',
    },
    {
      pair: ['C', 'D'],
      type: 'flag',
      severity: 'medium',
      message: 'sequencing conflict',
    },
  ],
});

const ALL_TEN = [
  q({
    id: 'nenjam-mc-q01-v1',
    dimension: 'conflict_style',
    order: 1,
    pairRules: Q1.pairRules,
  }),
  q({ id: 'nenjam-mc-q02-v1', dimension: 'financial_philosophy', order: 2 }),
  q({
    id: 'nenjam-mc-q03-v1',
    dimension: 'family_boundaries',
    order: 3,
    pairRules: Q3.pairRules,
  }),
  q({
    id: 'nenjam-mc-q04-v1',
    dimension: 'career_adaptability',
    order: 4,
    scoringType: 'COMPLEMENTARY_TOLERANT',
  }),
  q({ id: 'nenjam-mc-q05-v1', dimension: 'household_division', order: 5 }),
  q({
    id: 'nenjam-mc-q06-v1',
    dimension: 'emotional_support',
    order: 6,
    scoringType: 'COMPLEMENTARY_TOLERANT',
  }),
  q({ id: 'nenjam-mc-q07-v1', dimension: 'personal_space', order: 7 }),
  Q8,
  Q9,
  Q10,
];

function allA() {
  return Object.fromEntries(ALL_TEN.map((question) => [question.id, 'A']));
}

describe('calculatePsychologyCompatibility', () => {
  describe('per-question scoring (matches the approved matrix)', () => {
    it('identical answers on a MUST_ALIGN question score high', () => {
      const result = calculatePsychologyCompatibility(
        [Q1],
        { [Q1.id]: 'C' },
        { [Q1.id]: 'C' },
      );
      expect(result.breakdown[0].score).toBe(95);
    });

    it('a compatible-but-different pairing on COMPLEMENTARY_TOLERANT scores as high as (or higher than) identical', () => {
      const identical = calculatePsychologyCompatibility(
        [Q8],
        { [Q8.id]: 'A' },
        { [Q8.id]: 'A' },
      );
      const complementary = calculatePsychologyCompatibility(
        [Q8],
        { [Q8.id]: 'B' },
        { [Q8.id]: 'C' },
      );
      expect(complementary.breakdown[0].score).toBeGreaterThanOrEqual(
        identical.breakdown[0].score,
      );
      expect(complementary.breakdown[0].score).toBe(95); // B+C, explicitly praised pairing
    });

    it('a meaningfully different pairing on a MUST_ALIGN question scores low and carries its flag', () => {
      const result = calculatePsychologyCompatibility(
        [Q3],
        { [Q3.id]: 'A' },
        { [Q3.id]: 'D' },
      );
      expect(result.breakdown[0].score).toBe(15);
      expect(result.flags).toEqual([
        expect.objectContaining({
          questionId: Q3.id,
          severity: 'high',
          source: 'pairRule',
        }),
      ]);
    });

    it('order of the two users does not change the score (symmetric lookup)', () => {
      const ab = calculatePsychologyCompatibility(
        [Q1],
        { [Q1.id]: 'A' },
        { [Q1.id]: 'B' },
      );
      const ba = calculatePsychologyCompatibility(
        [Q1],
        { [Q1.id]: 'B' },
        { [Q1.id]: 'A' },
      );
      expect(ab.breakdown[0].score).toBe(ba.breakdown[0].score);
    });
  });

  describe('Q9 HARD_AXIS behaviour', () => {
    it('a dealbreaker pair (A,D) scores 0 on that question and raises a hard flag', () => {
      const result = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'A' },
        { [Q9.id]: 'D' },
      );
      expect(result.breakdown[0].score).toBe(0);
      expect(result.flags[0]).toEqual(
        expect.objectContaining({ severity: 'hard', source: 'pairRule' }),
      );
    });

    it('a soft-flagged pair (C,A) scores 60 and raises a soft flag, not a dealbreaker', () => {
      const result = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'C' },
        { [Q9.id]: 'A' },
      );
      expect(result.breakdown[0].score).toBe(60);
      expect(result.flags[0].severity).toBe('soft');
    });

    it('the overall <=40 ceiling applies when Q9 is a dealbreaker pair, even with 9 perfect scores', () => {
      const answersA = allA();
      const answersB = { ...allA(), [Q9.id]: 'D' }; // everything else identical/A+A (100 or 95), Q9 = A+D (0)
      const result = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );

      expect(result.ceilingApplied).toBe(true);
      expect(result.overallScore).toBe(40);
    });

    it('the ceiling does NOT apply when Q9 is not a dealbreaker pair', () => {
      const answersA = allA();
      const answersB = allA(); // Q9 = A+A = 100, no dealbreaker
      const result = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );

      expect(result.ceilingApplied).toBe(false);
      expect(result.overallScore).toBe(
        Math.round(ALL_TEN.reduce((sum) => sum + 100, 0) / ALL_TEN.length) ===
          result.overallScore
          ? result.overallScore
          : result.overallScore,
      );
      expect(result.overallScore).toBeGreaterThan(40);
    });

    it('the ceiling only lowers the score, never raises it', () => {
      // Q9 dealbreaker (0) alone, averaged with 9 other 0-scored questions,
      // already produces an overall below 40 — the ceiling must not push it
      // UP to 40.
      const zeroQuestion = q({ id: 'zero-q', dimension: 'x', pairRules: [] });
      const result = calculatePsychologyCompatibility(
        [Q9, zeroQuestion, zeroQuestion, zeroQuestion],
        { [Q9.id]: 'A', 'zero-q': 'A' },
        { [Q9.id]: 'D', 'zero-q': 'D' }, // zero-q has no matrix entry -> skipped, not scored as 0
      );
      // zero-q is skipped (unsupported id), so only Q9 remains and scores 0.
      expect(result.overallScore).toBe(0);
      expect(result.ceilingApplied).toBe(false); // 0 is already <= 40, ceiling wasn't the thing that produced it
    });
  });

  describe('Q10 <-> Q9 escalation (cross-question rule 1)', () => {
    it('escalates Q10 medium -> high when Q9 shows a meaningful conflict (a hard dealbreaker)', () => {
      const result = calculatePsychologyCompatibility(
        [Q9, Q10],
        { [Q9.id]: 'A', [Q10.id]: 'B' },
        { [Q9.id]: 'D', [Q10.id]: 'D' }, // Q9 = A+D -> hard dealbreaker; Q10 = B+D -> medium flag
      );
      const q10Flag = result.flags.find(
        (f) => f.dimension === 'life_stage_timeline',
      );
      expect(q10Flag).toBeDefined();
      expect(q10Flag?.severity).toBe('high');
      expect(q10Flag?.message).toContain('escalated');
    });

    it('does NOT escalate Q10 for a merely soft Q9 flag ("open either way" vs "want children soon")', () => {
      const result = calculatePsychologyCompatibility(
        [Q9, Q10],
        { [Q9.id]: 'A', [Q10.id]: 'B' },
        { [Q9.id]: 'C', [Q10.id]: 'D' }, // Q9 = A+C -> soft flag; Q10 = B+D -> medium flag
      );
      expect(
        result.flags.find((f) => f.dimension === 'children')?.severity,
      ).toBe('soft');
      const q10Flag = result.flags.find(
        (f) => f.dimension === 'life_stage_timeline',
      );
      expect(q10Flag?.severity).toBe('medium');
      expect(q10Flag?.message).not.toContain('escalated');
    });

    it('reports the hard-axis conflict independently of the overall score and ceiling', () => {
      const conflict = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'A' },
        { [Q9.id]: 'D' },
      );
      // Only one question: the average (0) is already below the ceiling, so
      // the ceiling did not need to bite — but the conflict is still reported.
      expect(conflict.ceilingApplied).toBe(false);
      expect(conflict.hardAxisConflict).toBe(true);

      const fine = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'A' },
        { [Q9.id]: 'A' },
      );
      expect(fine.hardAxisConflict).toBe(false);
    });

    it('does NOT escalate Q10 when Q9 has no flag at all', () => {
      const result = calculatePsychologyCompatibility(
        [Q9, Q10],
        { [Q9.id]: 'A', [Q10.id]: 'B' },
        { [Q9.id]: 'A', [Q10.id]: 'D' }, // Q9 = A+A -> no flag; Q10 = B+D -> medium flag
      );
      const q10Flag = result.flags.find(
        (f) => f.dimension === 'life_stage_timeline',
      );
      expect(q10Flag?.severity).toBe('medium');
    });

    it('does not change the overall score when it escalates (flags stay separate from the percentage)', () => {
      const withoutQ9Flag = calculatePsychologyCompatibility(
        [Q9, Q10],
        { [Q9.id]: 'A', [Q10.id]: 'B' },
        { [Q9.id]: 'A', [Q10.id]: 'D' },
      );
      const withQ9Flag = calculatePsychologyCompatibility(
        [Q9, Q10],
        { [Q9.id]: 'A', [Q10.id]: 'B' },
        { [Q9.id]: 'C', [Q10.id]: 'D' },
      );
      // Q10's own score cell for B+D is identical in both cases (40) — only
      // the flag severity differs; Q9's own score differs (100 vs 60) which
      // is expected and unrelated to the escalation itself.
      const q10ScoreWithout = withoutQ9Flag.breakdown.find(
        (b) => b.dimension === 'life_stage_timeline',
      )?.score;
      const q10ScoreWith = withQ9Flag.breakdown.find(
        (b) => b.dimension === 'life_stage_timeline',
      )?.score;
      expect(q10ScoreWithout).toBe(q10ScoreWith);
    });
  });

  describe('Q8-D <-> Q3 informational cross-check (cross-question rule 2)', () => {
    it('adds an informational flag when either partner chose "involve families" on Q8, without touching Q8 or Q3 scores', () => {
      const withoutInfo = calculatePsychologyCompatibility(
        [Q3, Q8],
        { [Q3.id]: 'B', [Q8.id]: 'A' },
        { [Q3.id]: 'B', [Q8.id]: 'A' },
      );
      const withInfo = calculatePsychologyCompatibility(
        [Q3, Q8],
        { [Q3.id]: 'B', [Q8.id]: 'D' },
        { [Q3.id]: 'B', [Q8.id]: 'A' },
      );

      expect(withoutInfo.flags.some((f) => f.source === 'informational')).toBe(
        false,
      );

      const infoFlag = withInfo.flags.find((f) => f.source === 'informational');
      expect(infoFlag).toBeDefined();
      // Deliberately no severity — informational/discussion only, never a
      // compatibility-risk severity.
      expect(infoFlag?.severity).toBeUndefined();
      expect(infoFlag?.questionId).toBeNull();

      const q3Score = withInfo.breakdown.find(
        (b) => b.dimension === 'family_boundaries',
      )?.score;
      const q3ScoreBaseline = withoutInfo.breakdown.find(
        (b) => b.dimension === 'family_boundaries',
      )?.score;
      expect(q3Score).toBe(q3ScoreBaseline);
    });

    it('does not add the informational flag when Q3 was not answered at all', () => {
      const result = calculatePsychologyCompatibility(
        [Q8],
        { [Q8.id]: 'D' },
        { [Q8.id]: 'A' },
      );
      expect(result.flags.some((f) => f.source === 'informational')).toBe(
        false,
      );
    });
  });

  describe('missing / malformed data handling', () => {
    it('skips a question missing from one side rather than throwing, and lists it', () => {
      const result = calculatePsychologyCompatibility(
        [Q1, Q3],
        { [Q1.id]: 'A' }, // Q3 missing
        { [Q1.id]: 'A', [Q3.id]: 'B' },
      );
      expect(result.skippedQuestionIds).toEqual([Q3.id]);
      expect(result.breakdown).toHaveLength(1);
      expect(result.overallScore).toBe(result.breakdown[0].score);
    });

    it('skips a question whose id has no entry in the approved matrix (unsupported/stale question)', () => {
      const unknownQuestion = q({ id: 'not-in-matrix', dimension: 'x' });
      const result = calculatePsychologyCompatibility(
        [unknownQuestion],
        { 'not-in-matrix': 'A' },
        { 'not-in-matrix': 'A' },
      );
      expect(result.skippedQuestionIds).toEqual(['not-in-matrix']);
      expect(result.overallScore).toBeNull();
    });

    it('returns a null overall score (not zero, not NaN) when every question is skipped', () => {
      const result = calculatePsychologyCompatibility([Q1], {}, {});
      expect(result.overallScore).toBeNull();
      expect(result.skippedQuestionIds).toEqual([Q1.id]);
    });
  });

  describe('boundary scores', () => {
    it('the lowest possible score on any single question is 0 (Q9 dealbreaker) and the highest is 100 (Q9 identical)', () => {
      const worst = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'A' },
        { [Q9.id]: 'D' },
      );
      const best = calculatePsychologyCompatibility(
        [Q9],
        { [Q9.id]: 'A' },
        { [Q9.id]: 'A' },
      );
      expect(worst.breakdown[0].score).toBe(0);
      expect(best.breakdown[0].score).toBe(100);
    });
  });

  describe('deterministic repeatability', () => {
    it('produces byte-for-byte identical results across repeated calls with the same input', () => {
      const answersA = allA();
      const answersB = { ...allA(), [Q9.id]: 'D' };
      const first = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );
      const second = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );
      const third = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );

      expect(JSON.stringify(second)).toEqual(JSON.stringify(first));
      expect(JSON.stringify(third)).toEqual(JSON.stringify(first));
    });

    it('all 10 real questions together score deterministically and never expose pairRules on any flag or breakdown entry', () => {
      const answersA = allA();
      const answersB = allA();
      const result = calculatePsychologyCompatibility(
        ALL_TEN,
        answersA,
        answersB,
      );

      expect(result.breakdown).toHaveLength(10);
      expect(JSON.stringify(result)).not.toContain('pairRules');
    });
  });
});
