import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type {
  PsychologyQuiz,
  QuizQuestion,
  UserQuizResponse,
} from '../../../../../../libs/database/generated/client';
import { PsychologyRepository } from '../repositories/psychology.repository';
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

/**
 * Marriage Compatibility Quiz — answer storage + validation only (Phase 1 /
 * Step 3). No compatibility score is computed here: this quiz's scoring is
 * inherently pairwise (see the marriage-compatibility spec's option-pair
 * matrices), so there is nothing a single submission can score on its own.
 * `UserQuizResponse.answers` is the SINGLE canonical record of what a user
 * submitted — every response returned by this service is built by re-reading
 * that field and joining it against the question bank for display labels,
 * never by storing a second copy of the answers.
 */
@Injectable()
export class PsychologyService {
  constructor(private readonly repository: PsychologyRepository) {}

  async getActiveQuiz(): Promise<ActiveQuizEntity> {
    const quiz = await this.requireActiveQuiz();
    const questions = await this.repository.findQuestionsForQuiz(quiz.id);
    return this.toActiveQuizEntity(quiz, questions);
  }

  async getMyResponse(userId: string): Promise<UserQuizResponseEntity> {
    const quiz = await this.requireActiveQuiz();
    const response = await this.repository.findUserResponse(userId, quiz.id);
    if (!response) {
      throw new NotFoundException(
        'You have not taken the psychology quiz yet.',
      );
    }
    const questions = await this.repository.findQuestionsForQuiz(quiz.id);
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
    if (new Set(submittedIds).size !== submittedIds.length) {
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
      .filter((id) => !submittedIds.includes(id));
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
      const options = question.options as unknown as { key: string }[];
      const validKeys = new Set(options.map((o) => o.key));
      if (!validKeys.has(answer.selectedKey)) {
        throw new BadRequestException(
          `"${answer.selectedKey}" is not a valid option for question "${answer.questionId}".`,
        );
      }
      answersMap[answer.questionId] = answer.selectedKey;
    }

    // Upsert — a user retaking the (still-active) quiz safely overwrites
    // their prior answers in place; a retired quiz's responses are a
    // different quizId and are never touched by this call.
    const updated = await this.repository.upsertUserResponse(
      userId,
      quiz.id,
      answersMap,
    );

    return this.toUserResponseEntity(updated, questions);
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
    const rawAnswers = response.answers as unknown as Record<string, string>;

    const entity = new UserQuizResponseEntity();
    entity.quizId = response.quizId;
    entity.completedAt = response.completedAt;
    entity.updatedAt = response.updatedAt;
    entity.answers = Object.entries(rawAnswers).map(
      ([questionId, selectedKey]) => {
        const question = questionsById.get(questionId);
        const options =
          (question?.options as unknown as { key: string; label: string }[]) ??
          [];
        const selectedOption = options.find((o) => o.key === selectedKey);

        const answer = new UserQuizAnswerEntity();
        answer.questionId = questionId;
        answer.dimension = question?.dimension ?? '';
        answer.questionText = question?.questionText ?? '';
        answer.selectedKey = selectedKey;
        answer.selectedLabel = selectedOption?.label ?? '';
        return answer;
      },
    );
    return entity;
  }
}
