/**
 * The approved per-question, per-option-pair scoring matrix for the Marriage
 * Compatibility Quiz (quiz id `marriage-compat-v1`, questions
 * `nenjam-mc-q01-v1` .. `nenjam-mc-q10-v1`).
 *
 * These numbers are a product decision reached through an explicit
 * question-by-question review (2026-09-23) — NOT derived from a distance
 * formula and NOT recomputed from `QuizQuestion.pairRules` (pairRules only
 * carries a *severity label* for a subset of pairs, never a score; the full
 * 4x4 numeric matrix for every pair had to be authored separately and
 * approved cell-by-cell). Flags (message + severity) are still read live
 * from `QuizQuestion.pairRules` at scoring time in
 * `psychology-compatibility.calculator.ts` — this file supplies ONLY the
 * numeric score, so the two never need to be kept in sync by hand.
 *
 * Each question's 10 unordered pairs (AA, AB, AC, AD, BB, BC, BD, CC, CD,
 * DD) are keyed as `"<sortedKey1>|<sortedKey2>"` via `pairLookupKey()`
 * below, so score lookup is order-independent (A+B and B+A resolve the same
 * cell). If this quiz's questions/options ever change, this file must be
 * re-reviewed and re-approved — it is not auto-derived from the schema.
 */

export function pairLookupKey(keyA: string, keyB: string): string {
  return [keyA, keyB].sort().join('|');
}

// prettier-ignore
export const PSYCHOLOGY_COMPATIBILITY_MATRIX: Readonly<
  Record<string, Readonly<Record<string, number>>>
> = {
  // Q1 — Conflict Resolution Style (MUST_ALIGN). A=pursue B=withdraw C=compromise D=defer
  'nenjam-mc-q01-v1': {
    'A|A': 95, 'A|B': 60, 'A|C': 88, 'A|D': 75,
    'B|B': 65, 'B|C': 85, 'B|D': 72,
    'C|C': 95, 'C|D': 85,
    'D|D': 60,
  },
  // Q2 — Financial Philosophy (MUST_ALIGN). A=full merge B=bridge C=separate D=one-leads
  'nenjam-mc-q02-v1': {
    'A|A': 95, 'A|B': 85, 'A|C': 40, 'A|D': 70,
    'B|B': 90, 'B|C': 85, 'B|D': 70,
    'C|C': 95, 'C|D': 70,
    'D|D': 60,
  },
  // Q3 — Family & In-Law Boundaries (MUST_ALIGN). A=very involved B=major-events C=respectful-distance D=minimal
  'nenjam-mc-q03-v1': {
    'A|A': 95, 'A|B': 75, 'A|C': 40, 'A|D': 15,
    'B|B': 95, 'B|C': 85, 'B|D': 55,
    'C|C': 95, 'C|D': 85,
    'D|D': 95,
  },
  // Q4 — Career Ambition & Adaptability (COMPLEMENTARY_TOLERANT). A=my-career-priority B=weigh-together C=stability-priority D=scale-back
  'nenjam-mc-q04-v1': {
    'A|A': 40, 'A|B': 90, 'A|C': 85, 'A|D': 88,
    'B|B': 85, 'B|C': 88, 'B|D': 88,
    'C|C': 75, 'C|D': 80,
    'D|D': 75,
  },
  // Q5 — Household Responsibility Division (MUST_ALIGN). A=50/50 B=whoever's-better C=traditional D=outsource
  'nenjam-mc-q05-v1': {
    'A|A': 95, 'A|B': 70, 'A|C': 40, 'A|D': 70,
    'B|B': 85, 'B|C': 70, 'B|D': 75,
    'C|C': 85, 'C|D': 70,
    'D|D': 85,
  },
  // Q6 — Emotional Support Under Stress (COMPLEMENTARY_TOLERANT). A=just-listen B=practical-help C=space-then-support D=physical-closeness
  'nenjam-mc-q06-v1': {
    'A|A': 90, 'A|B': 75, 'A|C': 60, 'A|D': 85,
    'B|B': 85, 'B|C': 60, 'B|D': 80,
    'C|C': 85, 'C|D': 60,
    'D|D': 90,
  },
  // Q7 — Personal Space & Independence (MUST_ALIGN). A=high-independence B=balance C=high-togetherness D=depends
  'nenjam-mc-q07-v1': {
    'A|A': 60, 'A|B': 88, 'A|C': 40, 'A|D': 70,
    'B|B': 88, 'B|C': 85, 'B|D': 80,
    'C|C': 60, 'C|D': 70,
    'D|D': 85,
  },
  // Q8 — Decision-Making Power Dynamic (COMPLEMENTARY_TOLERANT). A=share-together B=I-lead C=I-follow D=involve-families
  'nenjam-mc-q08-v1': {
    'A|A': 95, 'A|B': 90, 'A|C': 90, 'A|D': 85,
    'B|B': 40, 'B|C': 95, 'B|D': 65,
    'C|C': 70, 'C|D': 65,
    'D|D': 65,
  },
  // Q9 — Children & Parenting Expectations (HARD_AXIS). A=soon+co-parent B=soon+traditional C=open D=don't-want/later
  'nenjam-mc-q09-v1': {
    'A|A': 100, 'A|B': 85, 'A|C': 60, 'A|D': 0,
    'B|B': 100, 'B|C': 60, 'B|D': 0,
    'C|C': 90, 'C|D': 60,
    'D|D': 100,
  },
  // Q10 — Life-Stage Timeline (MUST_ALIGN). A=settle-quickly B=build-career-first C=travel-first D=start-family-soon
  'nenjam-mc-q10-v1': {
    'A|A': 95, 'A|B': 65, 'A|C': 65, 'A|D': 90,
    'B|B': 85, 'B|C': 85, 'B|D': 40,
    'C|C': 85, 'C|D': 40,
    'D|D': 95,
  },
};
