import type { PrismaClient } from '../../generated/client';
import { QUESTIONS, QUIZ_ID, seedQuiz } from './quiz.seeder';

interface QuizUpsertArg {
  create: Record<string, unknown>;
  update: Record<string, unknown>;
}

function fakePrisma(activeCount = 1) {
  const quizUpsert = jest.fn().mockResolvedValue({
    id: QUIZ_ID,
    title: 'Marriage Compatibility Quiz',
    version: '1.0',
    isActive: true,
  });
  const questionUpsert = jest.fn().mockResolvedValue({});
  const count = jest.fn().mockResolvedValue(activeCount);
  return {
    prisma: {
      psychologyQuiz: { upsert: quizUpsert, count },
      quizQuestion: { upsert: questionUpsert },
    } as unknown as PrismaClient,
    quizUpsert,
    questionUpsert,
    count,
  };
}

describe('seedQuiz', () => {
  beforeEach(() => {
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  it('activates the quiz when it first creates it', async () => {
    const { prisma, quizUpsert } = fakePrisma();
    await seedQuiz(prisma);
    const [arg] = quizUpsert.mock.calls[0] as [QuizUpsertArg];
    expect(arg.create).toMatchObject({
      id: QUIZ_ID,
      isActive: true,
    });
  });

  it('never re-activates the quiz on a re-seed (an operator who retired it must not have that undone)', async () => {
    const { prisma, quizUpsert } = fakePrisma();
    await seedQuiz(prisma);
    const [arg] = quizUpsert.mock.calls[0] as [QuizUpsertArg];
    expect(arg.update).not.toHaveProperty('isActive');
  });

  it('upserts every question, by id, without moving it to another quiz', async () => {
    const { prisma, questionUpsert } = fakePrisma();
    await seedQuiz(prisma);

    expect(questionUpsert).toHaveBeenCalledTimes(QUESTIONS.length);
    for (const [arg] of questionUpsert.mock.calls as [QuizUpsertArg][]) {
      expect(arg.update).not.toHaveProperty('quizId');
      expect(arg.create.quizId).toBe(QUIZ_ID);
    }
  });

  it('warns, without changing anything, when more than one quiz is active', async () => {
    const { prisma, quizUpsert } = fakePrisma(2);
    await seedQuiz(prisma);
    expect(console.warn).toHaveBeenCalledWith(
      expect.stringContaining('2 psychology quizzes are active'),
    );
    expect(quizUpsert).toHaveBeenCalledTimes(1);
  });

  it('stays quiet when exactly one quiz is active', async () => {
    const { prisma } = fakePrisma(1);
    await seedQuiz(prisma);
    expect(console.warn).not.toHaveBeenCalled();
  });
});
