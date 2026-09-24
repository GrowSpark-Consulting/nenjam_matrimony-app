import type {
  PsychologyQuiz,
  QuizQuestion,
} from '../../../../../../libs/database/generated/client';
import { PsychologyRepository } from '../repositories/psychology.repository';
import { PsychologyCompatibilityService } from '../scoring/psychology-compatibility.service';

const ACTIVE_QUIZ: PsychologyQuiz = {
  id: 'marriage-compat-v1',
  title: 'Marriage Compatibility Quiz',
  description: null,
  version: '1.0',
  isActive: true,
  createdAt: new Date(),
  updatedAt: new Date(),
};

function question(
  id: string,
  dimension: string,
  pairRules: unknown[] = [],
): QuizQuestion {
  return {
    id,
    quizId: ACTIVE_QUIZ.id,
    dimension,
    scoringType: 'MUST_ALIGN',
    questionText: 't',
    options: [
      { key: 'A', label: 'A', value: 1 },
      { key: 'B', label: 'B', value: 2 },
      { key: 'C', label: 'C', value: 3 },
      { key: 'D', label: 'D', value: 4 },
    ],
    pairRules,
    order: 1,
    createdAt: new Date(),
  } as unknown as QuizQuestion;
}

const Q1 = question('nenjam-mc-q01-v1', 'conflict_style');

function buildService(overrides?: {
  findActiveQuiz?: jest.Mock;
  findQuestionsForQuiz?: jest.Mock;
  findUserResponse?: jest.Mock;
}) {
  const repository = {
    findActiveQuiz:
      overrides?.findActiveQuiz ?? jest.fn().mockResolvedValue(ACTIVE_QUIZ),
    findQuestionsForQuiz:
      overrides?.findQuestionsForQuiz ?? jest.fn().mockResolvedValue([Q1]),
    findUserResponse: overrides?.findUserResponse ?? jest.fn(),
  } as unknown as PsychologyRepository;

  return {
    service: new PsychologyCompatibilityService(repository),
    repository,
  };
}

describe('PsychologyCompatibilityService', () => {
  it('returns NO_ACTIVE_QUIZ when no quiz is active', async () => {
    const { service } = buildService({
      findActiveQuiz: jest.fn().mockResolvedValue(null),
    });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('NO_ACTIVE_QUIZ');
    expect(result.overallScore).toBeNull();
  });

  it('returns UNSUPPORTED_QUIZ_VERSION when the active quiz has a question outside the approved matrix', async () => {
    const { service } = buildService({
      findQuestionsForQuiz: jest
        .fn()
        .mockResolvedValue([question('some-future-question-id', 'x')]),
    });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('UNSUPPORTED_QUIZ_VERSION');
    expect(result.quizId).toBe(ACTIVE_QUIZ.id);
  });

  it('returns BOTH_INCOMPLETE when neither user has answered the active quiz', async () => {
    const { service } = buildService({
      findUserResponse: jest.fn().mockResolvedValue(null),
    });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('BOTH_INCOMPLETE');
  });

  it('returns USER_A_INCOMPLETE when only the first user has not answered', async () => {
    const findUserResponse = jest
      .fn()
      .mockImplementation((userId: string) =>
        Promise.resolve(
          userId === 'u2'
            ? { quizId: ACTIVE_QUIZ.id, answers: { [Q1.id]: 'A' } }
            : null,
        ),
      );
    const { service } = buildService({ findUserResponse });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('USER_A_INCOMPLETE');
  });

  it('returns USER_B_INCOMPLETE when only the second user has not answered', async () => {
    const findUserResponse = jest
      .fn()
      .mockImplementation((userId: string) =>
        Promise.resolve(
          userId === 'u1'
            ? { quizId: ACTIVE_QUIZ.id, answers: { [Q1.id]: 'A' } }
            : null,
        ),
      );
    const { service } = buildService({ findUserResponse });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('USER_B_INCOMPLETE');
  });

  it('treats a response that only exists for a RETIRED quiz id as incomplete for the active quiz', async () => {
    // findUserResponse is always called with the ACTIVE quiz's id (per the
    // repository's own (userId, quizId) signature) — a user whose only
    // stored response belongs to a retired quiz simply won't be found here,
    // which is exactly the desired "stale data" behaviour: no special
    // status, just indistinguishable from "hasn't taken the current quiz".
    const findUserResponse = jest.fn().mockResolvedValue(null);
    const { service } = buildService({ findUserResponse });

    await service.computeForUsers('u1', 'u2');

    expect(findUserResponse).toHaveBeenCalledWith('u1', ACTIVE_QUIZ.id);
    expect(findUserResponse).toHaveBeenCalledWith('u2', ACTIVE_QUIZ.id);
  });

  it('returns COMPLETE with a score when both users have answered', async () => {
    const findUserResponse = jest.fn().mockResolvedValue({
      quizId: ACTIVE_QUIZ.id,
      answers: { [Q1.id]: 'C' },
    });
    const { service } = buildService({ findUserResponse });

    const result = await service.computeForUsers('u1', 'u2');

    expect(result.status).toBe('COMPLETE');
    expect(result.overallScore).toBe(95); // Q1 C+C, per the approved matrix
    expect(result.quizId).toBe(ACTIVE_QUIZ.id);
  });
});
