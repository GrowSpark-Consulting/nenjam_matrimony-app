import {
  BadRequestException,
  HttpException,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import type { AppConfigService } from '@app/config';
import type { PsychologyRepository } from '../repositories/psychology.repository';
import { PsychologyService } from '../services/psychology.service';
import type { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import { SubmitQuizAnswersDto } from '../dto/submit-quiz-answers.dto';

const DAY = 86_400_000;

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

interface Row {
  id: string;
  userId: string;
  quizId: string;
  quizVersion: string | null;
  answers: unknown;
  completedAt: Date;
  updatedAt: Date;
}

/**
 * An in-memory stand-in for the response table that enforces what the real one
 * does: a unique (userId, quizId) key, and an UPDATE whose WHERE carries the
 * cooldown condition. That is what lets the race and cooldown tests below mean
 * something — they exercise the service against database semantics, not
 * against a mock that returns whatever the test says.
 */
function fakeDatabase(initial: Row[] = []) {
  const rows = new Map<string, Row>();
  for (const r of initial) rows.set(`${r.userId}|${r.quizId}`, r);
  let clock = () => new Date();
  const findUserResponse = jest.fn((userId: string, quizId: string) =>
    Promise.resolve(rows.get(`${userId}|${quizId}`) ?? null),
  );
  const createUserResponse = jest.fn(
    (userId: string, quizId: string, quizVersion: string, answers: unknown) => {
      const key = `${userId}|${quizId}`;
      if (rows.has(key)) return Promise.resolve(null); // unique violation
      const now = clock();
      const row: Row = {
        id: key,
        userId,
        quizId,
        quizVersion,
        answers,
        completedAt: now,
        updatedAt: now,
      };
      rows.set(key, row);
      return Promise.resolve(row);
    },
  );
  const updateUserResponseIfDue = jest.fn(
    (
      userId: string,
      quizId: string,
      quizVersion: string,
      answers: unknown,
      dueBefore: Date,
    ) => {
      const row = rows.get(`${userId}|${quizId}`);
      if (!row || row.completedAt.getTime() > dueBefore.getTime()) {
        return Promise.resolve(false);
      }
      row.answers = answers;
      row.quizVersion = quizVersion;
      row.completedAt = clock();
      row.updatedAt = clock();
      return Promise.resolve(true);
    },
  );
  return {
    rows,
    findUserResponse,
    createUserResponse,
    updateUserResponseIfDue,
    setClock: (fn: () => Date) => {
      clock = fn;
    },
  };
}

describe('PsychologyService', () => {
  function buildService(
    overrides: {
      findActiveQuiz?: jest.Mock;
      findQuestionsForQuiz?: jest.Mock;
      findUserResponse?: jest.Mock;
      createUserResponse?: jest.Mock;
      updateUserResponseIfDue?: jest.Mock;
      cooldownDays?: number;
      quiz?: typeof QUIZ;
    } = {},
  ) {
    const repository = {
      findActiveQuiz:
        overrides.findActiveQuiz ??
        jest.fn().mockResolvedValue(overrides.quiz ?? QUIZ),
      findQuestionsForQuiz:
        overrides.findQuestionsForQuiz ??
        jest.fn().mockResolvedValue(buildTwoQuestions()),
      findUserResponse: overrides.findUserResponse ?? jest.fn(),
      createUserResponse: overrides.createUserResponse ?? jest.fn(),
      updateUserResponseIfDue: overrides.updateUserResponseIfDue ?? jest.fn(),
    } as unknown as PsychologyRepository;

    const feedInvalidation = {
      invalidate: jest.fn().mockResolvedValue(undefined),
    };
    const config = {
      psychology: {
        enabled: true,
        timeoutMs: 800,
        retakeCooldownDays: overrides.cooldownDays ?? 7,
      },
    } as unknown as AppConfigService;

    return {
      service: new PsychologyService(
        repository,
        feedInvalidation as unknown as FeedInvalidationService,
        config,
      ),
      repository,
      feedInvalidation,
    };
  }

  /** A service wired to the in-memory database. */
  function buildWithDb(
    initial: Row[] = [],
    opts: { cooldownDays?: number; quiz?: typeof QUIZ } = {},
  ) {
    const db = fakeDatabase(initial);
    const built = buildService({
      findUserResponse: db.findUserResponse,
      createUserResponse: db.createUserResponse,
      updateUserResponseIfDue: db.updateUserResponseIfDue,
      cooldownDays: opts.cooldownDays,
      quiz: opts.quiz,
    });
    return { ...built, db };
  }

  const dto = (a: string, b: string): SubmitQuizAnswersDto => ({
    quizId: QUIZ.id,
    answers: [
      { questionId: 'q1', selectedKey: a },
      { questionId: 'q2', selectedKey: b },
    ],
  });

  const rowFor = (
    userId: string,
    answers: unknown,
    completedAt: Date,
    quizVersion: string | null = '1.0',
  ): Row => ({
    id: `${userId}|${QUIZ.id}`,
    userId,
    quizId: QUIZ.id,
    quizVersion,
    answers,
    completedAt,
    updatedAt: completedAt,
  });

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
    const stored = (answers: unknown, quizVersion: string | null = '1.0') =>
      jest.fn().mockResolvedValue({
        quizId: QUIZ.id,
        quizVersion,
        answers,
        completedAt: new Date('2026-02-01'),
        updatedAt: new Date('2026-02-01'),
      });

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
        findUserResponse: stored({ q1: 'A', q2: 'C' }),
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

    it.each([
      ['null', null],
      ['an array', ['A', 'C']],
      ['a string', 'A'],
    ])(
      'reports "not taken" (not a 500) when the stored answers are %s',
      async (_l, bad) => {
        const { service } = buildService({ findUserResponse: stored(bad) });
        await expect(service.getMyResponse('user-1')).rejects.toThrow(
          NotFoundException,
        );
      },
    );

    it('reports "not taken" when a question was added after the response was submitted', async () => {
      const { service } = buildService({
        findUserResponse: stored({ q1: 'A' }),
      });
      await expect(service.getMyResponse('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('reports "not taken" when a stored option key is no longer valid for its question', async () => {
      const { service } = buildService({
        findUserResponse: stored({ q1: 'A', q2: 'B' }),
      });
      await expect(service.getMyResponse('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('reports "not taken" when the answers were given against another version of the quiz', async () => {
      const { service } = buildService({
        findUserResponse: stored({ q1: 'A', q2: 'C' }, '0.9'),
      });
      await expect(service.getMyResponse('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('treats answers with no recorded version as current', async () => {
      const { service } = buildService({
        findUserResponse: stored({ q1: 'A', q2: 'C' }, null),
      });
      await expect(service.getMyResponse('user-1')).resolves.toBeDefined();
    });

    it('omits stored answers to questions that are no longer in the quiz', async () => {
      const { service } = buildService({
        findUserResponse: stored({ q1: 'A', q2: 'C', retired: 'A' }),
      });
      const result = await service.getMyResponse('user-1');
      expect(result.answers.map((a) => a.questionId).sort()).toEqual([
        'q1',
        'q2',
      ]);
    });
  });

  describe('submitAnswers: validation', () => {
    it('throws NotFoundException when no quiz is active', async () => {
      const { service } = buildService({
        findActiveQuiz: jest.fn().mockResolvedValue(null),
      });
      await expect(service.submitAnswers('u', dto('A', 'C'))).rejects.toThrow(
        NotFoundException,
      );
    });

    it('rejects a quizId that does not match the active quiz', async () => {
      const { service } = buildService();
      await expect(
        service.submitAnswers('u', { ...dto('A', 'C'), quizId: 'stale-quiz' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a duplicated question with a fixed message that does not echo caller input', async () => {
      const { service } = buildService();
      await expect(
        service.submitAnswers('u', {
          quizId: QUIZ.id,
          answers: [
            { questionId: 'q1', selectedKey: 'A' },
            { questionId: 'q1', selectedKey: 'B' },
          ],
        }),
      ).rejects.toThrow('The same question was answered more than once.');
    });

    it('rejects a questionId that does not belong to the active quiz', async () => {
      const { service } = buildService();
      await expect(
        service.submitAnswers('u', {
          quizId: QUIZ.id,
          answers: [
            { questionId: 'q1', selectedKey: 'A' },
            { questionId: 'not-a-real-question', selectedKey: 'A' },
          ],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects an incomplete submission', async () => {
      const { service } = buildService();
      await expect(
        service.submitAnswers('u', {
          quizId: QUIZ.id,
          answers: [{ questionId: 'q1', selectedKey: 'A' }],
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a selectedKey that is not a valid option for that question', async () => {
      const { service } = buildService();
      await expect(service.submitAnswers('u', dto('Z', 'C'))).rejects.toThrow(
        BadRequestException,
      );
    });

    it('writes nothing and invalidates nothing when validation rejects', async () => {
      const created = jest.fn();
      const updated = jest.fn();
      const { service, feedInvalidation } = buildService({
        createUserResponse: created,
        updateUserResponseIfDue: updated,
      });
      await expect(
        service.submitAnswers('u', { ...dto('A', 'C'), quizId: 'stale' }),
      ).rejects.toThrow(BadRequestException);
      expect(created).not.toHaveBeenCalled();
      expect(updated).not.toHaveBeenCalled();
      expect(feedInvalidation.invalidate).not.toHaveBeenCalled();
    });
  });

  describe('submitAnswers: first submission', () => {
    it('stores the answers keyed by questionId, against the active quiz version', async () => {
      const { service, db } = buildWithDb();

      const result = await service.submitAnswers('u1', dto('A', 'C'));

      expect(db.createUserResponse).toHaveBeenCalledWith('u1', QUIZ.id, '1.0', {
        q1: 'A',
        q2: 'C',
      });
      expect(db.rows.get(`u1|${QUIZ.id}`)!.answers).toEqual({
        q1: 'A',
        q2: 'C',
      });
      expect(result.answers).toHaveLength(2);
    });

    it('is never delayed by the cooldown', async () => {
      const { service } = buildWithDb([], { cooldownDays: 365 });
      await expect(
        service.submitAnswers('u1', dto('A', 'C')),
      ).resolves.toBeDefined();
    });

    it('invalidates the submitting member feed, after the save', async () => {
      const order: string[] = [];
      const { service, feedInvalidation, db } = buildWithDb();
      db.createUserResponse.mockImplementationOnce((userId: string) => {
        order.push('saved');
        return Promise.resolve(rowFor(userId, {}, new Date()));
      });
      feedInvalidation.invalidate.mockImplementation(() => {
        order.push('invalidated');
        return Promise.resolve();
      });

      await service.submitAnswers('u1', dto('A', 'C'));

      expect(order).toEqual(['saved', 'invalidated']);
      expect(feedInvalidation.invalidate).toHaveBeenCalledWith(
        'u1',
        'psychology_updated',
      );
    });
  });

  describe('submitAnswers: resubmitting the same answers (double tap / client retry)', () => {
    it('is a success that changes and invalidates nothing', async () => {
      const { service, db, feedInvalidation } = buildWithDb([
        rowFor('u1', { q1: 'A', q2: 'C' }, new Date()),
      ]);

      const result = await service.submitAnswers('u1', dto('A', 'C'));

      expect(result.answers).toHaveLength(2);
      expect(db.updateUserResponseIfDue).not.toHaveBeenCalled();
      expect(db.createUserResponse).not.toHaveBeenCalled();
      expect(feedInvalidation.invalidate).not.toHaveBeenCalled();
    });

    it('never trips the cooldown, however recent the last change was', async () => {
      const { service } = buildWithDb(
        [rowFor('u1', { q1: 'A', q2: 'C' }, new Date())],
        { cooldownDays: 365 },
      );
      await expect(
        service.submitAnswers('u1', dto('A', 'C')),
      ).resolves.toBeDefined();
    });
  });

  describe('submitAnswers: retake cooldown', () => {
    const answersA = { q1: 'A', q2: 'C' };

    it('rejects a change inside the cooldown with a 429 that says when to retry', async () => {
      const { service, feedInvalidation, db } = buildWithDb([
        rowFor('u1', answersA, new Date(Date.now() - 2 * DAY)),
      ]);

      const error: HttpException = await service
        .submitAnswers('u1', dto('B', 'C'))
        .then(
          () => {
            throw new Error('expected a rejection');
          },
          (e: HttpException) => e,
        );

      expect(error).toBeInstanceOf(HttpException);
      expect(error.getStatus()).toBe(429);
      const body = error.getResponse() as {
        message: string;
        retryAfterSeconds: number;
      };
      expect(body.message).toMatch(/in 5 days/);
      // 7 days after the last change, 2 days ago: 5 days left.
      expect(body.retryAfterSeconds).toBeGreaterThan(4.9 * 86_400);
      expect(body.retryAfterSeconds).toBeLessThanOrEqual(5 * 86_400);
      // Nothing changed.
      expect(db.rows.get(`u1|${QUIZ.id}`)!.answers).toEqual(answersA);
      expect(feedInvalidation.invalidate).not.toHaveBeenCalled();
    });

    it('allows a change once the cooldown has passed, and restarts it', async () => {
      const { service, db, feedInvalidation } = buildWithDb([
        rowFor('u1', answersA, new Date(Date.now() - 8 * DAY)),
      ]);

      await service.submitAnswers('u1', dto('B', 'C'));

      expect(db.rows.get(`u1|${QUIZ.id}`)!.answers).toEqual({
        q1: 'B',
        q2: 'C',
      });
      expect(feedInvalidation.invalidate).toHaveBeenCalledTimes(1);
      // Immediately changing again is now blocked.
      await expect(service.submitAnswers('u1', dto('A', 'C'))).rejects.toThrow(
        HttpException,
      );
    });

    it('a cooldown of 0 disables the limit', async () => {
      const { service } = buildWithDb([rowFor('u1', answersA, new Date())], {
        cooldownDays: 0,
      });
      await expect(
        service.submitAnswers('u1', dto('B', 'C')),
      ).resolves.toBeDefined();
    });

    it('never makes a member wait to retake answers that a quiz update made stale', async () => {
      // Answered only q1 before q2 existed, moments ago.
      const { service, db } = buildWithDb(
        [rowFor('u1', { q1: 'A' }, new Date())],
        { cooldownDays: 365 },
      );
      await service.submitAnswers('u1', dto('A', 'C'));
      expect(db.rows.get(`u1|${QUIZ.id}`)!.answers).toEqual({
        q1: 'A',
        q2: 'C',
      });
    });

    it('never makes a member wait when their answers are from another version of the quiz', async () => {
      const { service } = buildWithDb(
        [rowFor('u1', { q1: 'A', q2: 'C' }, new Date(), '0.9')],
        { cooldownDays: 365 },
      );
      await expect(
        service.submitAnswers('u1', dto('A', 'C')),
      ).resolves.toBeDefined();
    });

    it('never makes a member wait when their stored answers are corrupt', async () => {
      const { service } = buildWithDb([rowFor('u1', null, new Date())], {
        cooldownDays: 365,
      });
      await expect(
        service.submitAnswers('u1', dto('A', 'C')),
      ).resolves.toBeDefined();
    });

    it('re-recording a stale response stamps the current quiz version on it', async () => {
      const { service, db } = buildWithDb([
        rowFor('u1', { q1: 'A', q2: 'C' }, new Date(), '0.9'),
      ]);
      await service.submitAnswers('u1', dto('A', 'C'));
      expect(db.rows.get(`u1|${QUIZ.id}`)!.quizVersion).toBe('1.0');
    });

    it('members are limited independently', async () => {
      const { service } = buildWithDb([rowFor('u1', answersA, new Date())], {
        cooldownDays: 7,
      });
      await expect(service.submitAnswers('u1', dto('B', 'C'))).rejects.toThrow(
        HttpException,
      );
      await expect(
        service.submitAnswers('u2', dto('B', 'C')),
      ).resolves.toBeDefined();
    });
  });

  describe('submitAnswers: concurrency', () => {
    it('two simultaneous first submissions of the same answers both succeed and leave one row', async () => {
      const { service, db } = buildWithDb();

      const [a, b] = await Promise.all([
        service.submitAnswers('u1', dto('A', 'C')),
        service.submitAnswers('u1', dto('A', 'C')),
      ]);

      expect(a.answers).toHaveLength(2);
      expect(b.answers).toHaveLength(2);
      expect(db.rows.size).toBe(1);
    });

    it('two simultaneous first submissions with DIFFERENT answers: one wins, the loser is held to the cooldown, no 500', async () => {
      const { service, db } = buildWithDb();

      const results = await Promise.allSettled([
        service.submitAnswers('u1', dto('A', 'C')),
        service.submitAnswers('u1', dto('B', 'A')),
      ]);

      const fulfilled = results.filter((r) => r.status === 'fulfilled');
      const rejected = results.filter(
        (r): r is PromiseRejectedResult => r.status === 'rejected',
      );
      expect(fulfilled).toHaveLength(1);
      expect(rejected).toHaveLength(1);
      expect(rejected[0].reason).toBeInstanceOf(HttpException);
      expect((rejected[0].reason as HttpException).getStatus()).toBe(429);
      expect(db.rows.size).toBe(1);
    });

    it('a burst of simultaneous retakes with different answers lets exactly one through', async () => {
      const { service, db } = buildWithDb([
        rowFor('u1', { q1: 'A', q2: 'C' }, new Date(Date.now() - 30 * DAY)),
      ]);
      const attempts = [
        dto('B', 'C'),
        dto('B', 'A'),
        dto('A', 'A'),
        dto('B', 'C'),
        dto('A', 'C'),
      ];

      const results = await Promise.allSettled(
        attempts.map((d) => service.submitAnswers('u1', d)),
      );

      // The cooldown is decided inside the UPDATE, so the row changed once.
      const updated = await Promise.all(
        db.updateUserResponseIfDue.mock.results.map(
          (r) => r.value as Promise<boolean>,
        ),
      );
      expect(updated.filter(Boolean)).toHaveLength(1);
      // No unexpected errors: every outcome is a success or a 429.
      for (const r of results) {
        if (r.status === 'rejected') {
          expect(r.reason).toBeInstanceOf(HttpException);
          expect((r.reason as HttpException).getStatus()).toBe(429);
        }
      }
      expect(db.rows.size).toBe(1);
    });
  });

  describe('submitAnswers: failures are contained and never leak answers', () => {
    it('turns a database error into a generic 500, and logs only the error class and code', async () => {
      const logs: string[] = [];
      jest.spyOn(Logger.prototype, 'error').mockImplementation((m: unknown) => {
        logs.push(String(m));
      });
      const prismaLike = Object.assign(
        new Error(
          'Invalid `prisma.userQuizResponse.create()` invocation: data: { answers: {"q1":"A","q2":"C"} }',
        ),
        { name: 'PrismaClientKnownRequestError', code: 'P2011' },
      );
      const { service } = buildService({
        findUserResponse: jest.fn().mockResolvedValue(null),
        createUserResponse: jest.fn().mockRejectedValue(prismaLike),
      });

      const error: unknown = await service
        .submitAnswers('u1', dto('A', 'C'))
        .then(
          () => null,
          (e: unknown) => e,
        );

      expect(error).toBeInstanceOf(InternalServerErrorException);
      expect((error as Error).message).not.toContain('q1');
      const logged = logs.join(' ');
      expect(logged).toContain('PrismaClientKnownRequestError (P2011)');
      expect(logged).not.toContain('q1');
      expect(logged).not.toContain('"A"');
      expect(logged).not.toContain('invocation');
      jest.restoreAllMocks();
    });

    it('a failure of feed invalidation does not fail the submission', async () => {
      const { service, feedInvalidation } = buildWithDb();
      // FeedInvalidationService swallows its own errors; even if that ever
      // regressed to throwing, the answers are already saved.
      feedInvalidation.invalidate.mockResolvedValue(undefined);
      await expect(
        service.submitAnswers('u1', dto('A', 'C')),
      ).resolves.toBeDefined();
    });
  });
});
