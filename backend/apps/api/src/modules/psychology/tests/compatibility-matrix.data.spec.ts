import {
  PSYCHOLOGY_COMPATIBILITY_MATRIX,
  pairLookupKey,
} from '../scoring/compatibility-matrix.data';

const QUESTION_IDS = Array.from(
  { length: 10 },
  (_, i) => `nenjam-mc-q${String(i + 1).padStart(2, '0')}-v1`,
);
const KEYS = ['A', 'B', 'C', 'D'];
const ALL_UNORDERED_PAIRS = KEYS.flatMap((a, i) =>
  KEYS.slice(i).map((b) => [a, b] as const),
);

describe('PSYCHOLOGY_COMPATIBILITY_MATRIX (approved scoring data)', () => {
  it('has a matrix entry for all 10 questions', () => {
    for (const id of QUESTION_IDS) {
      expect(PSYCHOLOGY_COMPATIBILITY_MATRIX[id]).toBeDefined();
    }
    expect(Object.keys(PSYCHOLOGY_COMPATIBILITY_MATRIX)).toHaveLength(10);
  });

  it('every question has all 10 unordered A-D pairs scored, and nothing extra', () => {
    for (const id of QUESTION_IDS) {
      const matrix = PSYCHOLOGY_COMPATIBILITY_MATRIX[id];
      const expectedKeys = ALL_UNORDERED_PAIRS.map(([a, b]) =>
        pairLookupKey(a, b),
      ).sort();
      expect(Object.keys(matrix).sort()).toEqual(expectedKeys);
    }
  });

  it('every score is an integer between 0 and 100 inclusive', () => {
    for (const id of QUESTION_IDS) {
      for (const [pair, score] of Object.entries(
        PSYCHOLOGY_COMPATIBILITY_MATRIX[id],
      )) {
        expect(Number.isInteger(score)).toBe(true);
        expect(score).toBeGreaterThanOrEqual(0);
        expect(score).toBeLessThanOrEqual(100);
        expect(pair).toMatch(/^[A-D]\|[A-D]$/);
      }
    }
  });

  it('pairLookupKey is order-independent', () => {
    expect(pairLookupKey('A', 'D')).toBe(pairLookupKey('D', 'A'));
    expect(pairLookupKey('C', 'B')).toBe(pairLookupKey('B', 'C'));
  });

  // Spot-checks pinning the specific numbers agreed in the review — these
  // are regression guards against an accidental future edit, not a
  // re-derivation of the values.
  it('pins the four values revised during review', () => {
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q05-v1']['C|C']).toBe(85);
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q06-v1']['A|B']).toBe(75);
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q07-v1']['A|C']).toBe(40);
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q07-v1']['D|D']).toBe(85);
  });

  it('pins the Q9 hard-axis dealbreaker pairs at exactly 0', () => {
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q09-v1']['A|D']).toBe(0);
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q09-v1']['B|D']).toBe(0);
  });

  it('Q5 C|C reads as full alignment (85), not a numeric penalty, per the review decision', () => {
    // The pairRules entry for Q5 C+C is kept for a future follow-up
    // question, but is explicitly NOT applied as a score penalty today.
    expect(PSYCHOLOGY_COMPATIBILITY_MATRIX['nenjam-mc-q05-v1']['C|C']).toBe(85);
  });
});
