import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { AppConfigService } from '@app/config';
import type {
  PsychologyQuiz,
  QuizQuestion,
  UserQuizResponse,
} from '../../../../../../libs/database/generated/client';
import { PsychologyRepository } from '../repositories/psychology.repository';
import { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import {
  coversQuestions,
  parseStoredAnswers,
  responseMatchesQuizVersion,
  sameAnswers,
} from '../scoring/psychology-data.guards';
import { errorMessage } from '../scoring/psychology-log';
import { SubmitQuizAnswersDto } from '../dto/submit-quiz-answers.dto';
import {
  ActiveQuizEntity,
  QuizOptionEntity,
  QuizQuestionEntity,
} from '../entities/quiz-question.entity';
import {
  UserQuizAnswerEntity,
  UserQuizResponseEntity,
} from '../entities/user-quiz-response.entity';

const DAY_MS = 86_400_000;

/** A question's options, or none if the stored JSON isn't an array. */
function optionsOf(question: QuizQuestion): { key: string; label: string }[] {
  return Array.isArray(question.options)
    ? (question.options as unknown as { key: string; label: string }[])
    : [];
}

/**
 * Marriage Compatibility Quiz — answer storage + validation. No compatibility
 * score is computed here: this quiz's scoring is inherently pairwise, so there
 * is nothing a single submission can score on its own.
 * `UserQuizResponse.answers` is the SINGLE canonical record of what a user
 * submitted — every response returned by this service is built by re-reading
 * that field and joining it against the question bank for display labels,
 * never by storing a second copy of the answers.
 *
 * A member's answers are sensitive personal information and are used to order
 * OTHER members' feeds, so this service is also where the abuse of that is
 * limited: see the retake cooldown on `submitAnswers`.
 */
@Injectable()
export class PsychologyService {
  private readonly logger = new Logger(PsychologyService.name);

  constructor(
    private readonly repository: PsychologyRepository,
    private readonly feedInvalidation: FeedInvalidationService,
    private readonly config: AppConfigService,
  ) {}

  async getActiveQuiz(): Promise<ActiveQuizEntity> {
    const quiz = await this.requireActiveQuiz();
    const questions = await this.repository.findQuestionsForQuiz(quiz.id);
    return this.toActiveQuizEntity(quiz, questions);
  }

  async getMyResponse(userId: string): Promise<UserQuizResponseEntity> {
    const quiz = await this.requireActiveQuiz();
    const response = await this.repository.findUserResponse(userId, quiz.id);
    const questions = response
      ? await this.repository.findQuestionsForQuiz(quiz.id)
      : [];
    // A stored response that doesn't apply to the quiz as it is now — a
    // question was added after it was submitted, an option key is gone, the
    // quiz version moved on, or the stored JSON is malformed — is not usable:
    // scoring ignores it, so it is reported as "not taken" and the member is
    // asked to retake.
    if (!response || !this.isCurrent(response, quiz, questions)) {
      throw new NotFoundException(
        'You have not taken the psychology quiz yet.',
      );
    }
    return this.toUserResponseEntity(response, questions);
  }

  async submitAnswers(
    userId: string,
    dto: SubmitQuizAnswersDto,
  ): Promise<UserQuizResponseEntity> {
    const quiz = await this.requireActiveQuiz();

    if (dto.quizId !== quiz.id) {
      throw new BadRequestException(
        `quizId does not match the active quiz (expected "${quiz.id}").`,
      );
    }

    const questions = await this.repository.findQuestionsForQuiz(quiz.id);
    const questionsById = new Map(questions.map((q) => [q.id, q]));

    const submittedIds = dto.answers.map((a) => a.questionId);
    const submittedSet = new Set(submittedIds);
    if (submittedSet.size !== submittedIds.length) {
      throw new BadRequestException(
        'The same question was answered more than once.',
      );
    }

    const unknownIds = submittedIds.filter((id) => !questionsById.has(id));
    if (unknownIds.length > 0) {
      throw new BadRequestException(
        `Unknown question id(s) for this quiz: ${unknownIds.join(', ')}`,
      );
    }

    const missingIds = questions
      .map((q) => q.id)
      .filter((id) => !submittedSet.has(id));
    if (missingIds.length > 0) {
      throw new BadRequestException(
        `All ${questions.length} questions must be answered. Missing: ${missingIds.join(', ')}`,
      );
    }

    const answersMap: Record<string, string> = {};
    for (const answer of dto.answers) {
      // Present for every id here — unknownIds above already rejected anything
      // not in questionsById.
      const question = questionsById.get(answer.questionId)!;
      const validKeys = new Set(optionsOf(question).map((o) => o.key));
      if (!validKeys.has(answer.selectedKey)) {
        throw new BadRequestException(
          `"${answer.selectedKey}" is not a valid option for question "${answer.questionId}".`,
        );
      }
      answersMap[answer.questionId] = answer.selectedKey;
    }

    const { saved, changed } = await this.save(
      userId,
      quiz,
      questions,
      answersMap,
    );

    // Completing or changing the quiz changes this member's Discover ranking,
    // so tell an open client its feed is stale — same mechanism as a profile or
    // preference change. Best-effort and non-throwing: the answers are already
    // saved, and that is what matters. Skipped when nothing changed (an
    // identical resubmission).
    if (changed) {
      await this.feedInvalidation.invalidate(userId, 'psychology_updated');
    }

    return this.toUserResponseEntity(saved, questions);
  }

  /**
   * Stores the answers, and decides what a resubmission means.
   *
   *  - First submission: always accepted.
   *  - The same answers again (a double tap, a client retry): a success that
   *    changes nothing, so it can never trip the cooldown or 500.
   *  - Different answers: a retake, allowed once the cooldown since the last
   *    change has passed. The cooldown exists because a member's answers
   *    order other members' feeds — unlimited re-answering would let someone
   *    read a specific member's answers out of how their own feed reorders.
   *    It is enforced inside the UPDATE (see updateUserResponseIfDue), so
   *    concurrent retakes cannot each pass a separate check.
   *  - A stored response that is stale (a quiz update made it unusable) is
   *    never made to wait: the member has no working answers and must be able
   *    to retake now.
   *
   * Races between two first submissions are settled by the (user, quiz) unique
   * constraint: the loser re-reads the winner's row and carries on. Database
   * failures are logged without their message — Prisma errors embed the
   * failing query's arguments, which here are the member's answers.
   */
  private async save(
    userId: string,
    quiz: PsychologyQuiz,
    questions: QuizQuestion[],
    answers: Record<string, string>,
  ): Promise<{ saved: UserQuizResponse; changed: boolean }> {
    const cooldownMs =
      Math.max(0, this.config.psychology.retakeCooldownDays) * DAY_MS;

    try {
      // Twice at most: the second pass only happens after losing a
      // first-submission race, when the row is guaranteed to exist.
      for (let attempt = 0; attempt < 2; attempt++) {
        const existing = await this.repository.findUserResponse(
          userId,
          quiz.id,
        );

        if (!existing) {
          const created = await this.repository.createUserResponse(
            userId,
            quiz.id,
            quiz.version,
            answers,
          );
          if (created) return { saved: created, changed: true };
          continue; // lost the race — re-read the winner's row
        }

        const current = this.isCurrent(existing, quiz, questions);
        if (
          current &&
          sameAnswers(parseStoredAnswers(existing.answers), answers)
        ) {
          return { saved: existing, changed: false };
        }

        const now = Date.now();
        const dueBefore = new Date(current ? now - cooldownMs : now);
        const updated = await this.repository.updateUserResponseIfDue(
          userId,
          quiz.id,
          quiz.version,
          answers,
          dueBefore,
        );
        const latest = await this.repository.findUserResponse(userId, quiz.id);
        if (!latest) continue;
        if (updated) return { saved: latest, changed: true };

        // Not due. If a concurrent identical submission just wrote these very
        // answers, this one is that double tap, not a retake.
        if (
          this.isCurrent(latest, quiz, questions) &&
          sameAnswers(parseStoredAnswers(latest.answers), answers)
        ) {
          return { saved: latest, changed: false };
        }
        throw this.cooldownError(latest.completedAt, cooldownMs, now);
      }
    } catch (error) {
      if (error instanceof HttpException) throw error;
      this.logger.error(
        `Saving psychology answers failed: ${errorMessage(error)}`,
      );
      throw new InternalServerErrorException(
        'We could not save your answers. Please try again.',
      );
    }

    this.logger.error(
      'Saving psychology answers failed: no stable row after retry',
    );
    throw new InternalServerErrorException(
      'We could not save your answers. Please try again.',
    );
  }

  private cooldownError(
    completedAt: Date,
    cooldownMs: number,
    now: number,
  ): HttpException {
    const retryAfterSeconds = Math.max(
      1,
      Math.ceil((completedAt.getTime() + cooldownMs - now) / 1000),
    );
    const days = Math.ceil(retryAfterSeconds / 86_400);
    return new HttpException(
      {
        statusCode: HttpStatus.TOO_MANY_REQUESTS,
        error: 'Too Many Requests',
        message: `You can change your quiz answers again in ${days} day${days === 1 ? '' : 's'}.`,
        retryAfterSeconds,
      },
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  /** Whether a stored response applies to the quiz as it is right now. */
  private isCurrent(
    response: UserQuizResponse,
    quiz: PsychologyQuiz,
    questions: QuizQuestion[],
  ): boolean {
    return (
      responseMatchesQuizVersion(response.quizVersion, quiz.version) &&
      coversQuestions(parseStoredAnswers(response.answers), questions)
    );
  }

  private async requireActiveQuiz(): Promise<PsychologyQuiz> {
    const quiz = await this.repository.findActiveQuiz();
    if (!quiz) {
      throw new NotFoundException('No active psychology quiz is configured.');
    }
    return quiz;
  }

  private toActiveQuizEntity(
    quiz: PsychologyQuiz,
    questions: QuizQuestion[],
  ): ActiveQuizEntity {
    const entity = new ActiveQuizEntity();
    entity.id = quiz.id;
    entity.title = quiz.title;
    entity.description = quiz.description;
    entity.version = quiz.version;
    entity.questions = questions.map((q) => this.toQuestionEntity(q));
    return entity;
  }

  private toQuestionEntity(question: QuizQuestion): QuizQuestionEntity {
    const entity = new QuizQuestionEntity();
    entity.id = question.id;
    entity.order = question.order;
    entity.dimension = question.dimension;
    entity.questionText = question.questionText;
    // `options` carries key/label/value only — pairRules is never read here,
    // so it can never leak into a response even if this mapping is extended.
    entity.options = question.options as unknown as QuizOptionEntity[];
    return entity;
  }

  private toUserResponseEntity(
    response: UserQuizResponse,
    questions: QuizQuestion[],
  ): UserQuizResponseEntity {
    const questionsById = new Map(questions.map((q) => [q.id, q]));
    // Malformed stored JSON reads as "no answers" rather than throwing.
    const rawAnswers = parseStoredAnswers(response.answers) ?? {};

    const entity = new UserQuizResponseEntity();
    entity.quizId = response.quizId;
    entity.completedAt = response.completedAt;
    entity.updatedAt = response.updatedAt;
    // Only answers to questions in the current quiz are returned; an answer
    // to a question that no longer exists has nothing to label and would only
    // show the client a blank row.
    entity.answers = Object.entries(rawAnswers)
      .filter(([questionId]) => questionsById.has(questionId))
      .map(([questionId, selectedKey]) => {
        const question = questionsById.get(questionId)!;
        const options = optionsOf(question);
        const selectedOption = options.find((o) => o.key === selectedKey);

        const answer = new UserQuizAnswerEntity();
        answer.questionId = questionId;
        answer.dimension = question.dimension;
        answer.questionText = question.questionText;
        answer.selectedKey = selectedKey;
        answer.selectedLabel = selectedOption?.label ?? '';
        return answer;
      });
    return entity;
  }
}
