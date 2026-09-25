import {
  answerFor,
  coversQuestions,
  parsePairRules,
  parseStoredAnswers,
  unsupportedQuizReason,
} from '../scoring/psychology-data.guards';
import { SCORING_QUESTIONS, allAnswered } from './psychology-fixtures';

describe('parseStoredAnswers', () => {
  it('returns a plain string map unchanged', () => {
    expect(parseStoredAnswers({ q1: 'A', q2: 'B' })).toEqual({
      q1: 'A',
      q2: 'B',
    });
  });

  it.each([
    ['null', null],
    ['undefined', undefined],
    ['an array', ['A', 'B']],
    ['a string', 'abc'],
    ['a number', 7],
  ])('returns null for %s', (_label, raw) => {
    expect(parseStoredAnswers(raw)).toBeNull();
  });

  it('drops non-string and empty values instead of keeping them', () => {
    expect(
      parseStoredAnswers({ q1: 'A', q2: 3, q3: null, q4: '', q5: { k: 'A' } }),
    ).toEqual({ q1: 'A' });
  });

  it('never carries a __proto__ key through', () => {
    const raw = JSON.parse('{"__proto__":"A","q1":"B"}') as unknown;
    const parsed = parseStoredAnswers(raw)!;
    expect(Object.keys(parsed)).toEqual(['q1']);
  });
});

describe('answerFor', () => {
  it('reads only own, non-empty string values', () => {
    expect(answerFor({ q1: 'A' }, 'q1')).toBe('A');
    expect(answerFor({ q1: 'A' }, 'q2')).toBeUndefined();
    expect(answerFor({ q1: 5 }, 'q1')).toBeUndefined();
    expect(answerFor({ q1: '' }, 'q1')).toBeUndefined();
  });

  it('does not resolve inherited Object.prototype members', () => {
    expect(answerFor({}, 'constructor')).toBeUndefined();
    expect(answerFor({}, 'toString')).toBeUndefined();
  });

  it('is safe on non-objects', () => {
    expect(answerFor(null, 'q1')).toBeUndefined();
    expect(answerFor(undefined, 'q1')).toBeUndefined();
    expect(answerFor(['A'] as never, '0')).toBeUndefined();
  });
});

describe('parsePairRules', () => {
  const good = {
    pair: ['A', 'B'],
    type: 'flag',
    severity: 'soft',
    message: 'm',
  };

  it('keeps well-formed rules', () => {
    expect(parsePairRules([good])).toEqual([good]);
  });

  it.each([
    ['null', null],
    ['an object', { a: 1 }],
    ['a string', 'x'],
  ])('returns [] when pairRules is %s', (_l, raw) => {
    expect(parsePairRules(raw)).toEqual([]);
  });

  it('drops each kind of malformed entry, keeps the good one', () => {
    const rules = parsePairRules([
      null,
      'x',
      { severity: 'soft', message: 'no pair', type: 'flag' },
      { ...good, pair: ['A'] },
      { ...good, pair: ['A', 3] },
      { ...good, severity: 'catastrophic' },
      { ...good, type: 'other' },
      { ...good, message: undefined },
      good,
    ]);
    expect(rules).toEqual([good]);
  });
});

describe('unsupportedQuizReason', () => {
  it('accepts the real seeded quiz', () => {
    expect(unsupportedQuizReason(SCORING_QUESTIONS)).toBeNull();
  });

  it('rejects an empty quiz', () => {
    expect(unsupportedQuizReason([])).toMatch(/no questions/);
  });

  it('rejects a question with no entry in the approved matrix', () => {
    const reason = unsupportedQuizReason([
      ...SCORING_QUESTIONS,
      {
        id: 'nenjam-mc-q11-v1',
        order: 11,
        dimension: 'x',
        scoringType: 'MUST_ALIGN',
      },
    ]);
    expect(reason).toMatch(/nenjam-mc-q11-v1/);
  });

  it('does not treat inherited names as matrix entries', () => {
    expect(
      unsupportedQuizReason([
        {
          id: 'constructor',
          order: 1,
          dimension: 'x',
          scoringType: 'MUST_ALIGN',
        },
      ]),
    ).toMatch(/no entry/);
  });

  it('rejects duplicate question ids and duplicate dimensions', () => {
    const [first] = SCORING_QUESTIONS;
    expect(unsupportedQuizReason([first, first])).toMatch(/twice/);
    expect(
      unsupportedQuizReason([
        first,
        { ...SCORING_QUESTIONS[1], dimension: first.dimension },
      ]),
    ).toMatch(/more than one question/);
  });
});

describe('coversQuestions', () => {
  it('is true only when every question has an answer', () => {
    expect(coversQuestions(allAnswered('A'), SCORING_QUESTIONS)).toBe(true);
    const missing = allAnswered('A');
    delete missing[SCORING_QUESTIONS[3].id];
    expect(coversQuestions(missing, SCORING_QUESTIONS)).toBe(false);
  });

  it('is false for no questions or non-object answers', () => {
    expect(coversQuestions({ q: 'A' }, [])).toBe(false);
    expect(coversQuestions(null, SCORING_QUESTIONS)).toBe(false);
  });

  it('checks the key against the question options when options are supplied', () => {
    const questions = [{ id: 'q1', options: [{ key: 'A' }, { key: 'B' }] }];
    expect(coversQuestions({ q1: 'B' }, questions)).toBe(true);
    expect(coversQuestions({ q1: 'D' }, questions)).toBe(false);
  });
});
