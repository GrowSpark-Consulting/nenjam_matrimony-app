import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  PsychologyQuiz,
  QuizQuestion,
  UserQuizResponse,
  Prisma,
} from '../../../../../../libs/database/generated/client';

@Injectable()
export class PsychologyRepository {
  constructor(private readonly prisma: PrismaService) {}

  findActiveQuiz(): Promise<PsychologyQuiz | null> {
    // isActive is a flag, not a uniqueness constraint at the DB level, but the
    // seeder only ever upserts one active quiz — findFirst is intentional
    // (not findUnique) since "at most one active quiz" is a content-ops
    // convention, not a schema guarantee.
    return this.prisma.psychologyQuiz.findFirst({ where: { isActive: true } });
  }

  findQuestionsForQuiz(quizId: string): Promise<QuizQuestion[]> {
    return this.prisma.quizQuestion.findMany({
      where: { quizId },
      orderBy: { order: 'asc' },
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

  /** Batch read for scoring a whole candidate pool in one round trip instead
   *  of one query per candidate. */
  findResponsesForUsers(
    userIds: string[],
    quizId: string,
  ): Promise<UserQuizResponse[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userQuizResponse.findMany({
      where: { quizId, userId: { in: userIds } },
    });
  }

  // Upsert on the (userId, quizId) unique constraint — a retake of the same
  // still-active quiz overwrites `answers` in place; a retired/replaced quiz
  // has a different quizId, so its old response row is untouched, not
  // overwritten (the versioning guarantee this schema was built for).
  upsertUserResponse(
    userId: string,
    quizId: string,
    answers: Prisma.InputJsonValue,
  ): Promise<UserQuizResponse> {
    return this.prisma.userQuizResponse.upsert({
      where: { userId_quizId: { userId, quizId } },
      create: { userId, quizId, answers },
      update: { answers },
    });
  }
}
