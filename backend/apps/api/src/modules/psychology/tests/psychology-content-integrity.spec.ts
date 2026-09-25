import { createHash } from 'node:crypto';
import {
  PSYCHOLOGY_COMPATIBILITY_MATRIX,
  pairLookupKey,
} from '../scoring/compatibility-matrix.data';
import {
  ESCALATION_TARGET_DIMENSION,
  FAMILY_BOUNDARIES_DIMENSION,
  FAMILY_INVOLVEMENT_DECISION_DIMENSION,
} from '../scoring/psychology-compatibility.calculator';
import { QUIZ_ID, SEEDED_QUESTIONS } from './psychology-fixtures';

/**
 * Guards the seeded questionnaire against silent drift.
 *
 * The scoring matrix is keyed by question id, and stored answers are keyed by
 * option key, but the seeder upserts questions in place. Nothing at runtime can
 * tell that an edit changed what a question MEANS. These tests make such an
 * edit fail CI, so it has to be a deliberate, reviewed change — a new question
 * id (and matrix entry) or a new quiz id — not a quiet re-score of everyone.
 */
describe('seeded questionnaire content integrity', () => {
  it('has exactly the questions the approved matrix covers, one for one', () => {
    expect(SEEDED_QUESTIONS.map((q) => q.id).sort()).toEqual(
      Object.keys(PSYCHOLOGY_COMPATIBILITY_MATRIX).sort(),
    );
  });

  it('has unique ids, dimensions and orders', () => {
    for (const field of ['id', 'dimension', 'order'] as const) {
      const values = SEEDED_QUESTIONS.map((q) => q[field]);
      expect(new Set(values).size).toBe(values.length);
    }
  });

  it('offers option keys A-D on every question, and the matrix covers every pair', () => {
    for (const q of SEEDED_QUESTIONS) {
      expect(q.options.map((o) => o.key)).toEqual(['A', 'B', 'C', 'D']);
      const cells = PSYCHOLOGY_COMPATIBILITY_MATRIX[q.id];
      for (const a of ['A', 'B', 'C', 'D']) {
        for (const b of ['A', 'B', 'C', 'D']) {
          expect(cells[pairLookupKey(a, b)]).toEqual(expect.any(Number));
        }
      }
    }
  });

  it('every pair rule names real option keys and is well-formed', () => {
    for (const q of SEEDED_QUESTIONS) {
      for (const rule of q.pairRules) {
        expect(rule.pair).toHaveLength(2);
        for (const key of rule.pair) {
          expect(['A', 'B', 'C', 'D']).toContain(key);
        }
        expect(['flag', 'dealbreaker']).toContain(rule.type);
        expect(['soft', 'medium', 'high', 'hard']).toContain(rule.severity);
        expect(rule.message.length).toBeGreaterThan(0);
      }
    }
  });

  it('has exactly one HARD_AXIS question, and its 0-scored pairs are exactly its "hard" rules', () => {
    const hardAxis = SEEDED_QUESTIONS.filter(
      (q) => q.scoringType === 'HARD_AXIS',
    );
    expect(hardAxis).toHaveLength(1);
    const [q9] = hardAxis;

    const zeroCells = Object.entries(PSYCHOLOGY_COMPATIBILITY_MATRIX[q9.id])
      .filter(([, score]) => score === 0)
      .map(([cell]) => cell)
      .sort();
    const hardRules = q9.pairRules
      .filter((r) => r.severity === 'hard')
      .map((r) => pairLookupKey(r.pair[0], r.pair[1]))
      .sort();
    // The calculator applies the ceiling on "score === 0"; the flag labelling
    // pairs "hard" comes from pairRules. They are two sources for one idea, so
    // they must agree.
    expect(zeroCells).toEqual(hardRules);
    expect(zeroCells.length).toBeGreaterThan(0);
  });

  it('no other question scores 0 or carries a "hard" rule', () => {
    for (const q of SEEDED_QUESTIONS.filter(
      (x) => x.scoringType !== 'HARD_AXIS',
    )) {
      expect(
        Object.values(PSYCHOLOGY_COMPATIBILITY_MATRIX[q.id]).every(
          (s) => s > 0,
        ),
      ).toBe(true);
      expect(q.pairRules.some((r) => r.severity === 'hard')).toBe(false);
    }
  });

  it('still contains the dimensions the calculator hardcodes for its cross-question rules', () => {
    const dimensions = SEEDED_QUESTIONS.map((q) => q.dimension);
    expect(dimensions).toContain(ESCALATION_TARGET_DIMENSION);
    expect(dimensions).toContain(FAMILY_INVOLVEMENT_DECISION_DIMENSION);
    expect(dimensions).toContain(FAMILY_BOUNDARIES_DIMENSION);
  });

  it('pins the scoring-relevant content (ids, dimensions, scoring types, option keys/values, rules)', () => {
    // Deliberately excludes wording (labels, messages), which may change in
    // place. If this fails, you changed what a question asks or offers:
    // create a NEW question id (plus matrix entry) or a new quiz id instead of
    // editing in place — see the immutability note on QUESTIONS in
    // quiz.seeder.ts — and only then update this hash.
    const scoringContent = SEEDED_QUESTIONS.map((q) => ({
      id: q.id,
      order: q.order,
      dimension: q.dimension,
      scoringType: q.scoringType,
      options: q.options.map((o) => [o.key, o.value]),
      rules: q.pairRules.map((r) => [
        [...r.pair].sort().join('|'),
        r.type,
        r.severity,
      ]),
    }));
    const hash = createHash('sha256')
      .update(JSON.stringify(scoringContent))
      .digest('hex')
      .slice(0, 16);
    expect(QUIZ_ID).toBe('marriage-compat-v1');
    expect(hash).toBe('9f8e7cc6b5892a45');
  });
});
