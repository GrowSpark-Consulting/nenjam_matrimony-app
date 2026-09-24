import { Injectable } from '@nestjs/common';
import type { QuizQuestion } from '../../../../../../../libs/database/generated/client';
import { PsychologyRepository } from '../../../psychology/repositories/psychology.repository';

export interface PsychologyMatchContext {
  /** Empty when there's no active quiz, or the seeker hasn't completed it —
   *  in both cases psychology can never be applicable for this request, so
   *  the (more expensive) candidate batch lookup is skipped entirely. */
  questions: QuizQuestion[];
  answersByUserId: ReadonlyMap<string, Record<string, string>>;
}

const EMPTY_CONTEXT: PsychologyMatchContext = {
  questions: [],
  answersByUserId: new Map(),
};

/**
 * Fetches what a single Discover request needs to let
 * PSYCHOLOGY_COMPATIBILITY_SIGNAL do its work: the active quiz's questions,
 * plus every relevant user's raw answers, in at most 3 small queries total —
 * never one query per candidate.
 *
 * Short-circuits hard on "the seeker hasn't completed the quiz", which is
 * true for virtually every request today: the psychology signal can only
 * ever be applicable when BOTH sides have answers (see
 * psychology-compatibility.signal.ts), so if the seeker has none, no
 * candidate's answers could matter either, and the batch fetch below is
 * skipped — the cost for someone who hasn't taken the quiz is two
 * single-row lookups (findActiveQuiz, findUserResponse), not a 200-row scan.
 */
@Injectable()
export class PsychologyMatchContextService {
  constructor(private readonly repository: PsychologyRepository) {}

  async loadContext(
    seekerId: string,
    candidateIds: string[],
  ): Promise<PsychologyMatchContext> {
    const quiz = await this.repository.findActiveQuiz();
    if (!quiz) return EMPTY_CONTEXT;

    const seekerResponse = await this.repository.findUserResponse(
      seekerId,
      quiz.id,
    );
    if (!seekerResponse) return EMPTY_CONTEXT;

    const [questions, candidateResponses] = await Promise.all([
      this.repository.findQuestionsForQuiz(quiz.id),
      this.repository.findResponsesForUsers(candidateIds, quiz.id),
    ]);

    const answersByUserId = new Map<string, Record<string, string>>();
    answersByUserId.set(
      seekerId,
      seekerResponse.answers as unknown as Record<string, string>,
    );
    for (const response of candidateResponses) {
      answersByUserId.set(
        response.userId,
        response.answers as unknown as Record<string, string>,
      );
    }

    return { questions, answersByUserId };
  }
}
