import { PsychologyRepository } from '../repositories/psychology.repository';
import { PsychologyScoringQuizProvider } from '../scoring/psychology-scoring-quiz.provider';
import { resetWarnThrottle } from '../scoring/psychology-log';
import { QUIZ_ID, SCORING_QUESTIONS } from './psychology-fixtures';

const QUIZ = { id: QUIZ_ID, version: '1.0', isActive: true };

function build(
  overrides: {
    findActiveQuiz?: jest.Mock;
    findScoringQuestions?: jest.Mock;
  } = {},
) {
  const repository = {
    findActiveQuiz:
      overrides.findActiveQuiz ?? jest.fn().mockResolvedValue(QUIZ),
    findScoringQuestions:
      overrides.findScoringQuestions ??
      jest.fn().mockResolvedValue(SCORING_QUESTIONS),
  };
  return {
    provider: new PsychologyScoringQuizProvider(
      repository as unknown as PsychologyRepository,
    ),
    repository,
  };
}

describe('PsychologyScoringQuizProvider', () => {
  let now: number;
  beforeEach(() => {
    resetWarnThrottle();
    now = 1_000_000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
  });
  afterEach(() => jest.restoreAllMocks());

  it('loads the quiz once and serves it from cache within the TTL', async () => {
    const { provider, repository } = build();

    const first = await provider.get();
    now += 30_000;
    const second = await provider.get();

    expect(first).toEqual({
      quizId: QUIZ_ID,
      version: '1.0',
      questions: SCORING_QUESTIONS,
    });
    expect(second).toBe(first);
    expect(repository.findActiveQuiz).toHaveBeenCalledTimes(1);
    expect(repository.findScoringQuestions).toHaveBeenCalledTimes(1);
  });

  it('reloads after the TTL', async () => {
    const { provider, repository } = build();
    await provider.get();
    now += 61_000;
    await provider.get();
    expect(repository.findActiveQuiz).toHaveBeenCalledTimes(2);
  });

  it('shares one load between concurrent callers', async () => {
    const { provider, repository } = build();
    await Promise.all([provider.get(), provider.get(), provider.get()]);
    expect(repository.findActiveQuiz).toHaveBeenCalledTimes(1);
  });

  it('caches "no active quiz" briefly, then re-checks', async () => {
    const { provider, repository } = build({
      findActiveQuiz: jest.fn().mockResolvedValue(null),
    });

    expect(await provider.get()).toBeNull();
    now += 10_000;
    expect(await provider.get()).toBeNull();
    expect(repository.findActiveQuiz).toHaveBeenCalledTimes(1);

    now += 6_000; // past the 15s absent-TTL
    await provider.get();
    expect(repository.findActiveQuiz).toHaveBeenCalledTimes(2);
  });

  it('returns null (not a partial quiz) when the active quiz cannot be scored', async () => {
    const { provider } = build({
      findScoringQuestions: jest.fn().mockResolvedValue([
        ...SCORING_QUESTIONS,
        {
          id: 'nenjam-mc-q11-v1',
          order: 11,
          dimension: 'new',
          scoringType: 'MUST_ALIGN',
        },
      ]),
    });
    expect(await provider.get()).toBeNull();
  });

  it('throws when the database fails and there is nothing cached', async () => {
    const { provider } = build({
      findActiveQuiz: jest.fn().mockRejectedValue(new Error('db down')),
    });
    await expect(provider.get()).rejects.toThrow('db down');
  });

  it('keeps serving the previous quiz when a refresh fails', async () => {
    const findActiveQuiz = jest.fn().mockResolvedValueOnce(QUIZ);
    const { provider } = build({ findActiveQuiz });
    const loaded = await provider.get();

    findActiveQuiz.mockRejectedValue(new Error('neon blip'));
    now += 61_000;
    expect(await provider.get()).toBe(loaded);
  });

  it('stops serving a stale quiz after the max-stale window', async () => {
    const findActiveQuiz = jest.fn().mockResolvedValueOnce(QUIZ);
    const { provider } = build({ findActiveQuiz });
    await provider.get();

    findActiveQuiz.mockRejectedValue(new Error('neon down'));
    now += 11 * 60_000;
    await expect(provider.get()).rejects.toThrow('neon down');
  });

  it('a failed load is not cached: the next call retries', async () => {
    const findActiveQuiz = jest
      .fn()
      .mockRejectedValueOnce(new Error('blip'))
      .mockResolvedValue(QUIZ);
    const { provider } = build({ findActiveQuiz });

    await expect(provider.get()).rejects.toThrow('blip');
    expect(await provider.get()).not.toBeNull();
  });
});
