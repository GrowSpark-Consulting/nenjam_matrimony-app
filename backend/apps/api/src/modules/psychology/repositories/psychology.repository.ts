import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  PsychologyQuiz,
  QuizQuestion,
  UserQuizResponse,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import type { ScoringQuestion } from '../scoring/psychology-compatibility.types';

/** What Discover needs from a stored response — no ids/timestamps. */
export type UserAnswersRow = Pick<
  UserQuizResponse,
  'userId' | 'answers' | 'quizVersion'
>;

function isUniqueViolation(error: unknown): boolean {
  return (error as { code?: string } | null)?.code === 'P2002';
}

@Injectable()
export class PsychologyRepository {
  constructor(private readonly prisma: PrismaService) {}

  findActiveQuiz(): Promise<PsychologyQuiz | null> {
    // A unique index guarantees at most one active quiz, so this is
    // deterministic by construction. The ordering is defence in depth for an
    // environment that hasn't applied that migration: newest wins,
    // identically on every API instance, rather than whichever row Postgres
    // returns first.
    return this.prisma.psychologyQuiz.findFirst({
      where: { isActive: true },
      orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
    });
  }

  findQuestionsForQuiz(quizId: string): Promise<QuizQuestion[]> {
    return this.prisma.quizQuestion.findMany({
      where: { quizId },
      orderBy: { order: 'asc' },
    });
  }

  /**
   * The columns scoring reads, nothing else. `options` and `pairRules` (the
   * bulk of a question row: labels and flag messages) are only needed to
   * render or explain a result, which Discover never does.
   */
  findScoringQuestions(quizId: string): Promise<ScoringQuestion[]> {
    return this.prisma.quizQuestion.findMany({
      where: { quizId },
      orderBy: { order: 'asc' },
      select: { id: true, order: true, dimension: true, scoringType: true },
    });
  }

  findUserResponse(
    userId: string,
    quizId: string,
  ): Promise<UserQuizResponse | null> {
    return this.prisma.userQuizResponse.findUnique({
      where: { userId_quizId: { userId, quizId } },
    });
  }

  /** The seeker's own answers only — one narrow row for the Discover path. */
  findUserAnswers(
    userId: string,
    quizId: string,
  ): Promise<UserAnswersRow | null> {
    return this.prisma.userQuizResponse.findUnique({
      where: { userId_quizId: { userId, quizId } },
      select: { userId: true, answers: true, quizVersion: true },
    });
  }

  /** Batch read for scoring a whole candidate pool in one round trip instead
   *  of one query per candidate. */
  findResponsesForUsers(
    userIds: string[],
    quizId: string,
  ): Promise<UserAnswersRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userQuizResponse.findMany({
      where: { quizId, userId: { in: userIds } },
      select: { userId: true, answers: true, quizVersion: true },
    });
  }

  /**
   * Inserts a member's first response to a quiz. Returns null — rather than
   * throwing — when the row already exists, which is what a lost race between
   * two first submissions looks like: the caller carries on with the row the
   * winner created. The (userId, quizId) unique constraint is what decides the
   * race, so it is settled by the database, not by a check-then-write.
   */
  async createUserResponse(
    userId: string,
    quizId: string,
    quizVersion: string,
    answers: Prisma.InputJsonValue,
  ): Promise<UserQuizResponse | null> {
    try {
      return await this.prisma.userQuizResponse.create({
        data: { userId, quizId, quizVersion, answers },
      });
    } catch (error) {
      if (isUniqueViolation(error)) return null;
      throw error;
    }
  }

  /**
   * Replaces a member's answers only if they were last completed at or before
   * `dueBefore`. The condition is part of the UPDATE's WHERE, so the cooldown
   * is enforced atomically by the database: N concurrent retakes can not each
   * pass a separate check and all write. Returns whether a row was updated.
   *
   * `completedAt` is refreshed to now — it means "when this set of answers was
   * completed", and is what the next cooldown counts from.
   */
  async updateUserResponseIfDue(
    userId: string,
    quizId: string,
    quizVersion: string,
    answers: Prisma.InputJsonValue,
    dueBefore: Date,
  ): Promise<boolean> {
    const { count } = await this.prisma.userQuizResponse.updateMany({
      where: { userId, quizId, completedAt: { lte: dueBefore } },
      data: { answers, quizVersion, completedAt: new Date() },
    });
    return count > 0;
  }
}
