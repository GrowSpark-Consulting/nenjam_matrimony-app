import type { PsychologyQuiz } from '../../../../../../libs/database/generated/client';
import { PsychologyRepository } from '../../psychology/repositories/psychology.repository';
import { PsychologyMatchContextService } from '../scoring/psychology/psychology-match-context.service';

const QUIZ: PsychologyQuiz = {
  id: 'marriage-compat-v1',
  title: 'Marriage Compatibility Quiz',
  description: null,
  version: '1.0',
  isActive: true,
  createdAt: new Date(),
  updatedAt: new Date(),
};

function buildService(overrides?: {
  findActiveQuiz?: jest.Mock;
  findUserResponse?: jest.Mock;
  findQuestionsForQuiz?: jest.Mock;
  findResponsesForUsers?: jest.Mock;
}) {
  const repository = {
    findActiveQuiz:
      overrides?.findActiveQuiz ?? jest.fn().mockResolvedValue(QUIZ),
    findUserResponse: overrides?.findUserResponse ?? jest.fn(),
    findQuestionsForQuiz:
      overrides?.findQuestionsForQuiz ?? jest.fn().mockResolvedValue([]),
    findResponsesForUsers:
      overrides?.findResponsesForUsers ?? jest.fn().mockResolvedValue([]),
  } as unknown as PsychologyRepository;

  return {
    service: new PsychologyMatchContextService(repository),
    repository,
  };
}

describe('PsychologyMatchContextService', () => {
  it('returns an empty context, and skips the candidate batch fetch, when no quiz is active', async () => {
    const findResponsesForUsers = jest.fn();
    const { service } = buildService({
      findActiveQuiz: jest.fn().mockResolvedValue(null),
      findResponsesForUsers,
    });

    const result = await service.loadContext('seeker-1', ['c1', 'c2']);

    expect(result.questions).toEqual([]);
    expect(result.answersByUserId.size).toBe(0);
    expect(findResponsesForUsers).not.toHaveBeenCalled();
  });

  it('returns an empty context, and skips the candidate batch fetch, when the seeker has not completed the quiz', async () => {
    // This is the common case today: virtually nobody has taken the quiz.
    const findResponsesForUsers = jest.fn();
    const findQuestionsForQuiz = jest.fn();
    const { service } = buildService({
      findUserResponse: jest.fn().mockResolvedValue(null),
      findResponsesForUsers,
      findQuestionsForQuiz,
    });

    const result = await service.loadContext('seeker-1', ['c1', 'c2']);

    expect(result.questions).toEqual([]);
    expect(result.answersByUserId.size).toBe(0);
    expect(findResponsesForUsers).not.toHaveBeenCalled();
    expect(findQuestionsForQuiz).not.toHaveBeenCalled();
  });

  it('loads the seeker + candidate answers and the quiz questions when the seeker has completed it', async () => {
    const findUserResponse = jest.fn().mockResolvedValue({
      userId: 'seeker-1',
      quizId: QUIZ.id,
      answers: { q1: 'A' },
    });
    const findQuestionsForQuiz = jest
      .fn()
      .mockResolvedValue([{ id: 'q1', order: 1 }]);
    const findResponsesForUsers = jest.fn().mockResolvedValue([
      { userId: 'c1', quizId: QUIZ.id, answers: { q1: 'B' } },
      // c2 never took it — simply absent from the result set.
    ]);
    const { service } = buildService({
      findUserResponse,
      findQuestionsForQuiz,
      findResponsesForUsers,
    });

    const result = await service.loadContext('seeker-1', ['c1', 'c2']);

    expect(findResponsesForUsers).toHaveBeenCalledWith(['c1', 'c2'], QUIZ.id);
    expect(result.questions).toEqual([{ id: 'q1', order: 1 }]);
    expect(result.answersByUserId.get('seeker-1')).toEqual({ q1: 'A' });
    expect(result.answersByUserId.get('c1')).toEqual({ q1: 'B' });
    expect(result.answersByUserId.has('c2')).toBe(false);
  });

  it('runs the questions fetch and the candidate batch fetch in parallel, not sequentially', async () => {
    const order: string[] = [];
    const findQuestionsForQuiz = jest.fn(async () => {
      order.push('questions-start');
      await Promise.resolve();
      order.push('questions-end');
      return [];
    });
    const findResponsesForUsers = jest.fn(async () => {
      order.push('responses-start');
      await Promise.resolve();
      order.push('responses-end');
      return [];
    });
    const { service } = buildService({
      findUserResponse: jest.fn().mockResolvedValue({
        userId: 'seeker-1',
        quizId: QUIZ.id,
        answers: {},
      }),
      findQuestionsForQuiz,
      findResponsesForUsers,
    });

    await service.loadContext('seeker-1', ['c1']);

    // Both must have started before either finished.
    expect(order.indexOf('responses-start')).toBeLessThan(
      order.indexOf('questions-end'),
    );
  });
});
