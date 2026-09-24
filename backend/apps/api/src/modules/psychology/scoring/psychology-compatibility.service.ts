import { Injectable } from '@nestjs/common';
import { PsychologyRepository } from '../repositories/psychology.repository';
import { PSYCHOLOGY_COMPATIBILITY_MATRIX } from './compatibility-matrix.data';
import { calculatePsychologyCompatibility } from './psychology-compatibility.calculator';
import { PsychologyCompatibilityResult } from './psychology-compatibility.types';

/**
 * Pairwise psychology compatibility — entirely separate from
 * `matches/scoring/compatibility.service.ts` (CompatibilityService). Nothing
 * in this module is imported by, or imports, the matches module. Not wired
 * into any controller yet — this is the standalone engine only, pending a
 * separate, explicitly-approved integration step.
 */
@Injectable()
export class PsychologyCompatibilityService {
  constructor(private readonly repository: PsychologyRepository) {}

  async computeForUsers(
    userIdA: string,
    userIdB: string,
  ): Promise<PsychologyCompatibilityResult> {
    const quiz = await this.repository.findActiveQuiz();
    if (!quiz) {
      return this.emptyResult('NO_ACTIVE_QUIZ', null);
    }

    const questions = await this.repository.findQuestionsForQuiz(quiz.id);
    const unsupported = questions.some(
      (q) => PSYCHOLOGY_COMPATIBILITY_MATRIX[q.id] === undefined,
    );
    if (unsupported) {
      // The active quiz's content has changed since this engine's matrix was
      // authored/approved — refuse to score rather than silently produce a
      // number against a matrix that no longer matches the questions.
      return this.emptyResult('UNSUPPORTED_QUIZ_VERSION', quiz.id);
    }

    // A response tied to a RETIRED quiz id (different from `quiz.id`) simply
    // won't be found here — that's deliberate, not a separate "stale" status:
    // it is functionally identical to "hasn't taken the current quiz yet",
    // which is exactly the guarantee the quiz-versioning schema (Step 2) was
    // built to provide.
    const [responseA, responseB] = await Promise.all([
      this.repository.findUserResponse(userIdA, quiz.id),
      this.repository.findUserResponse(userIdB, quiz.id),
    ]);

    if (!responseA && !responseB) {
      return this.emptyResult('BOTH_INCOMPLETE', quiz.id);
    }
    if (!responseA) {
      return this.emptyResult('USER_A_INCOMPLETE', quiz.id);
    }
    if (!responseB) {
      return this.emptyResult('USER_B_INCOMPLETE', quiz.id);
    }

    const answersA = responseA.answers as unknown as Record<string, string>;
    const answersB = responseB.answers as unknown as Record<string, string>;

    const calculated = calculatePsychologyCompatibility(
      questions,
      answersA,
      answersB,
    );

    return {
      status: 'COMPLETE',
      quizId: quiz.id,
      ...calculated,
    };
  }

  private emptyResult(
    status: PsychologyCompatibilityResult['status'],
    quizId: string | null,
  ): PsychologyCompatibilityResult {
    return {
      status,
      quizId,
      overallScore: null,
      ceilingApplied: false,
      breakdown: [],
      flags: [],
      skippedQuestionIds: [],
    };
  }
}
