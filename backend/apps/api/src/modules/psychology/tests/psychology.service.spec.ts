import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PsychologyRepository } from '../repositories/psychology.repository';
import { PsychologyService } from '../services/psychology.service';
import { SubmitQuizAnswersDto } from '../dto/submit-quiz-answers.dto';

const QUIZ = {
  id: 'marriage-compat-v1',
  title: 'Marriage Compatibility Quiz',
  description: 'desc',
  version: '1.0',
  isActive: true,
  createdAt: new Date('2026-01-01'),
  updatedAt: new Date('2026-01-01'),
};

function buildQuestion(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'q1',
    quizId: QUIZ.id,
    dimension: 'conflict_style',
    scoringType: 'MUST_ALIGN',
    questionText: 'How do you handle conflict?',
    options: [
      { key: 'A', label: 'Pursue', value: 1 },
      { key: 'B', label: 'Withdraw', value: 2 },
    ],
    pairRules: [
      { pair: ['A', 'B'], type: 'flag', severity: 'soft', message: 'x' },
    ],
    order: 1,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  };
}

function buildTwoQuestions() {
  return [
    buildQuestion({ id: 'q1', order: 1 }),
    buildQuestion({
      id: 'q2',
      order: 2,
      dimension: 'financial_philosophy',
      questionText: 'How do you handle money?',
      options: [
        { key: 'A', label: 'Joint', value: 1 },
        { key: 'C', label: 'Separate', value: 3 },
      ],
    }),
  ];
}

describe('PsychologyService', () => {
  function buildService(overrides?: {
    findActiveQuiz?: jest.Mock;
    findQuestionsForQuiz?: jest.Mock;
    findUserResponse?: jest.Mock;
    upsertUserResponse?: jest.Mock;
  }) {
    const repository = {
      findActiveQuiz:
        overrides?.findActiveQuiz ?? jest.fn().mockResolvedValue(QUIZ),
      findQuestionsForQuiz:
        overrides?.findQuestionsForQuiz ??
        jest.fn().mockResolvedValue(buildTwoQuestions()),
      findUserResponse: overrides?.findUserResponse ?? jest.fn(),
      upsertUserResponse: overrides?.upsertUserResponse ?? jest.fn(),
    } as unknown as PsychologyRepository;

    return { service: new PsychologyService(repository), repository };
  }

  describe('getActiveQuiz', () => {
    it('returns the quiz with its questions, never including pairRules or scoringType', async () => {
      const { service } = buildService();

      const result = await service.getActiveQuiz();

      expect(result.id).toBe(QUIZ.id);
      expect(result.questions).toHaveLength(2);
      expect(result.questions[0]).toEqual({
        id: 'q1',
        order: 1,
        dimension: 'conflict_style',
        questionText: 'How do you handle conflict?',
        options: [
          { key: 'A', label: 'Pursue', value: 1 },
          { key: 'B', label: 'Withdraw', value: 2 },
        ],
      });
      expect(JSON.stringify(result)).not.toContain('pairRules');
      expect(JSON.stringify(result)).not.toContain('scoringType');
    });

    it('throws NotFoundException when no quiz is active', async () => {
      const { service } = buildService({
        findActiveQuiz: jest.fn().mockResolvedValue(null),
      });

      await expect(service.getActiveQuiz()).rejects.toThrow(NotFoundException);
    });
  });

  describe('getMyResponse', () => {
    it('throws NotFoundException when no quiz is active', async () => {
      const { service } = buildService({
        findActiveQuiz: jest.fn().mockResolvedValue(null),
      });

      await expect(service.getMyResponse('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('throws NotFoundException when the user has no saved response', async () => {
      const { service } = buildService({
        findUserResponse: jest.fn().mockResolvedValue(null),
      });

      await expect(service.getMyResponse('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('joins the raw answers against the question bank for display labels', async () => {
      const { service } = buildService({
        findUserResponse: jest.fn().mockResolvedValue({
          quizId: QUIZ.id,
          answers: { q1: 'A', q2: 'C' },
          completedAt: new Date('2026-02-01'),
          updatedAt: new Date('2026-02-01'),
        }),
      });

      const result = await service.getMyResponse('user-1');

      expect(result.quizId).toBe(QUIZ.id);
      expect(result.answers).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            questionId: 'q1',
            selectedKey: 'A',
            selectedLabel: 'Pursue',
            dimension: 'conflict_style',
          }),
          expect.objectContaining({
            questionId: 'q2',
            selectedKey: 'C',
            selectedLabel: 'Separate',
            dimension: 'financial_philosophy',
          }),
        ]),
      );
    });
  });

  describe('submitAnswers', () => {
    const validDto: SubmitQuizAnswersDto = {
      quizId: QUIZ.id,
      answers: [
        { questionId: 'q1', selectedKey: 'A' },
        { questionId: 'q2', selectedKey: 'C' },
      ],
    };

    it('throws NotFoundException when no quiz is active', async () => {
      const { service } = buildService({
        findActiveQuiz: jest.fn().mockResolvedValue(null),
      });

      await expect(service.submitAnswers('user-1', validDto)).rejects.toThrow(
        NotFoundException,
      );
    });

    it('rejects a quizId that does not match the active quiz', async () => {
      const { service } = buildService();

      await expect(
        service.submitAnswers('user-1', { ...validDto, quizId: 'stale-quiz' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a duplicate questionId within the same submission', async () => {
      const { service } = buildService();

      await expect(
        service.submitAnswers('user-1', {
          quizId: QUIZ.id,
          answers: [
            { questionId: 'q1', selectedKey: 'A' },
            { questionId: 'q1', selectedKey: 'B' },
          ],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a questionId that does not belong to the active quiz', async () => {
      const { service } = buildService();

      await expect(
        service.submitAnswers('user-1', {
          quizId: QUIZ.id,
          answers: [
            { questionId: 'q1', selectedKey: 'A' },
            { questionId: 'not-a-real-question', selectedKey: 'A' },
          ],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects an incomplete submission (fewer than all questions answered)', async () => {
      const { service } = buildService();

      await expect(
        service.submitAnswers('user-1', {
          quizId: QUIZ.id,
          answers: [{ questionId: 'q1', selectedKey: 'A' }],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a selectedKey that is not a valid option for that question', async () => {
      const { service } = buildService();

      await expect(
        service.submitAnswers('user-1', {
          quizId: QUIZ.id,
          answers: [
            { questionId: 'q1', selectedKey: 'Z' },
            { questionId: 'q2', selectedKey: 'C' },
          ],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('accepts a valid, complete submission and stores answers keyed by questionId', async () => {
      const upsertUserResponse = jest.fn().mockResolvedValue({
        quizId: QUIZ.id,
        answers: { q1: 'A', q2: 'C' },
        completedAt: new Date('2026-02-01'),
        updatedAt: new Date('2026-02-01'),
      });
      const { service } = buildService({ upsertUserResponse });

      const result = await service.submitAnswers('user-1', validDto);

      expect(upsertUserResponse).toHaveBeenCalledWith('user-1', QUIZ.id, {
        q1: 'A',
        q2: 'C',
      });
      expect(result.answers).toHaveLength(2);
    });

    it('retaking the quiz upserts (overwrites) rather than duplicating', async () => {
      const upsertUserResponse = jest.fn().mockResolvedValue({
        quizId: QUIZ.id,
        answers: { q1: 'B', q2: 'A' },
        completedAt: new Date('2026-02-01'),
        updatedAt: new Date('2026-03-01'),
      });
      const { service } = buildService({ upsertUserResponse });

      await service.submitAnswers('user-1', {
        quizId: QUIZ.id,
        answers: [
          { questionId: 'q1', selectedKey: 'B' },
          { questionId: 'q2', selectedKey: 'A' },
        ],
      });

      // Same (userId, quizId) pair both times — the repository's upsert is
      // what guarantees this overwrites rather than creating a second row;
      // this test pins the service's contract with that repository call.
      expect(upsertUserResponse).toHaveBeenCalledTimes(1);
      expect(upsertUserResponse).toHaveBeenCalledWith('user-1', QUIZ.id, {
        q1: 'B',
        q2: 'A',
      });
    });
  });
});
