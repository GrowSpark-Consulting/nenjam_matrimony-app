import type { PrismaService } from '@app/database';
import { PsychologyRepository } from '../repositories/psychology.repository';

interface UpdateManyArgs {
  where: {
    userId: string;
    quizId: string;
    completedAt: { lte: Date };
  };
  data: {
    answers: unknown;
    quizVersion: string;
    completedAt: Date;
  };
}

function build() {
  const prisma = {
    psychologyQuiz: { findFirst: jest.fn().mockResolvedValue(null) },
    quizQuestion: { findMany: jest.fn().mockResolvedValue([]) },
    userQuizResponse: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      updateMany: jest.fn(),
    },
  };
  return {
    repository: new PsychologyRepository(prisma as unknown as PrismaService),
    prisma,
  };
}

describe('PsychologyRepository', () => {
  it('picks the active quiz deterministically: newest first, then id', async () => {
    const { repository, prisma } = build();
    await repository.findActiveQuiz();
    expect(prisma.psychologyQuiz.findFirst).toHaveBeenCalledWith({
      where: { isActive: true },
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
    });
  });

  it('reads only the scoring columns for Discover questions', async () => {
    const { repository, prisma } = build();
    await repository.findScoringQuestions('quiz');
    expect(prisma.quizQuestion.findMany).toHaveBeenCalledWith({
      where: { quizId: 'quiz' },
      orderBy: { order: 'asc' },
      select: { id: true, order: true, dimension: true, scoringType: true },
    });
  });

  it("reads only the seeker's own userId, answers and version", async () => {
    const { repository, prisma } = build();
    await repository.findUserAnswers('u', 'quiz');
    expect(prisma.userQuizResponse.findUnique).toHaveBeenCalledWith({
      where: { userId_quizId: { userId: 'u', quizId: 'quiz' } },
      select: { userId: true, answers: true, quizVersion: true },
    });
  });

  it('reads only userId, answers and version for the candidate batch, and skips the query for no candidates', async () => {
    const { repository, prisma } = build();
    await repository.findResponsesForUsers(['a', 'b'], 'quiz');
    expect(prisma.userQuizResponse.findMany).toHaveBeenCalledWith({
      where: { quizId: 'quiz', userId: { in: ['a', 'b'] } },
      select: { userId: true, answers: true, quizVersion: true },
    });

    prisma.userQuizResponse.findMany.mockClear();
    expect(await repository.findResponsesForUsers([], 'quiz')).toEqual([]);
    expect(prisma.userQuizResponse.findMany).not.toHaveBeenCalled();
  });

  describe('createUserResponse', () => {
    const saved = { userId: 'u', quizId: 'q', answers: { a: 'A' } };

    it('inserts the first response, recording the quiz version', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.create.mockResolvedValue(saved);

      const result = await repository.createUserResponse('u', 'q', '1.0', {
        a: 'A',
      });

      expect(result).toBe(saved);
      expect(prisma.userQuizResponse.create).toHaveBeenCalledWith({
        data: {
          userId: 'u',
          quizId: 'q',
          quizVersion: '1.0',
          answers: { a: 'A' },
        },
      });
    });

    it('returns null, not an error, when the row already exists (P2002): a lost first-submission race', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.create.mockRejectedValue({ code: 'P2002' });
      await expect(
        repository.createUserResponse('u', 'q', '1.0', { a: 'A' }),
      ).resolves.toBeNull();
    });

    it('rethrows every other database error unchanged', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.create.mockRejectedValue(
        new Error('connection lost'),
      );
      await expect(
        repository.createUserResponse('u', 'q', '1.0', { a: 'A' }),
      ).rejects.toThrow('connection lost');
    });
  });

  describe('updateUserResponseIfDue', () => {
    it('puts the cooldown condition in the UPDATE itself, and refreshes completedAt and the version', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.updateMany.mockResolvedValue({ count: 1 });
      const dueBefore = new Date('2026-01-01T00:00:00Z');

      const updated = await repository.updateUserResponseIfDue(
        'u',
        'q',
        '1.0',
        { a: 'B' },
        dueBefore,
      );

      expect(updated).toBe(true);
      const [arg] = prisma.userQuizResponse.updateMany.mock.calls[0] as [
        UpdateManyArgs,
      ];
      expect(arg.where).toEqual({
        userId: 'u',
        quizId: 'q',
        completedAt: { lte: dueBefore },
      });
      expect(arg.data.answers).toEqual({ a: 'B' });
      expect(arg.data.quizVersion).toBe('1.0');
      expect(arg.data.completedAt).toBeInstanceOf(Date);
    });

    it('reports false when the row is not yet due (nothing matched)', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.updateMany.mockResolvedValue({ count: 0 });
      await expect(
        repository.updateUserResponseIfDue(
          'u',
          'q',
          '1.0',
          { a: 'B' },
          new Date(),
        ),
      ).resolves.toBe(false);
    });

    it('does not swallow database errors', async () => {
      const { repository, prisma } = build();
      prisma.userQuizResponse.updateMany.mockRejectedValue(new Error('gone'));
      await expect(
        repository.updateUserResponseIfDue(
          'u',
          'q',
          '1.0',
          { a: 'B' },
          new Date(),
        ),
      ).rejects.toThrow('gone');
    });
  });
});
