import { Logger } from '@nestjs/common';
import type { AppConfigService } from '@app/config';
import type { PsychologyRepository } from '../../psychology/repositories/psychology.repository';
import type { PsychologyScoringQuizProvider } from '../../psychology/scoring/psychology-scoring-quiz.provider';
import { resetWarnThrottle } from '../../psychology/scoring/psychology-log';
import {
  QUIZ_ID,
  SCORING_QUESTIONS,
  allAnswered,
  QUESTION_IDS,
} from '../../psychology/tests/psychology-fixtures';
import { PsychologyMatchContextService } from '../scoring/psychology/psychology-match-context.service';

const QUIZ = { quizId: QUIZ_ID, version: '1.0', questions: SCORING_QUESTIONS };

function build(
  overrides: {
    get?: jest.Mock;
    findUserAnswers?: jest.Mock;
    findResponsesForUsers?: jest.Mock;
    psychology?: { enabled: boolean; timeoutMs: number };
  } = {},
) {
  const provider = {
    get: overrides.get ?? jest.fn().mockResolvedValue(QUIZ),
  };
  const repository = {
    findUserAnswers:
      overrides.findUserAnswers ??
      jest
        .fn()
        .mockResolvedValue({ userId: 'seeker', answers: allAnswered('A') }),
    findResponsesForUsers:
      overrides.findResponsesForUsers ?? jest.fn().mockResolvedValue([]),
  };
  const config = {
    psychology: overrides.psychology ?? { enabled: true, timeoutMs: 200 },
  };
  return {
    service: new PsychologyMatchContextService(
      repository as unknown as PsychologyRepository,
      provider as unknown as PsychologyScoringQuizProvider,
      config as unknown as AppConfigService,
    ),
    provider,
    repository,
  };
}

const EMPTY = { questions: [], answersByUserId: new Map() };

describe('PsychologyMatchContextService', () => {
  beforeEach(() => resetWarnThrottle());
  afterEach(() => jest.restoreAllMocks());

  describe('when psychology applies', () => {
    it('loads the seeker + candidate answers and the quiz questions', async () => {
      const { service, repository } = build({
        findResponsesForUsers: jest.fn().mockResolvedValue([
          { userId: 'c1', answers: allAnswered('B') },
          // c2 never took it — simply absent from the result set.
        ]),
      });

      const result = await service.loadContext('seeker', ['c1', 'c2']);

      expect(repository.findResponsesForUsers).toHaveBeenCalledWith(
        ['c1', 'c2'],
        QUIZ_ID,
      );
      expect(result.questions).toBe(SCORING_QUESTIONS);
      expect(result.answersByUserId.get('seeker')).toEqual(allAnswered('A'));
      expect(result.answersByUserId.get('c1')).toEqual(allAnswered('B'));
      expect(result.answersByUserId.has('c2')).toBe(false);
    });

    it('never issues a per-candidate query: one seeker row, one candidate batch', async () => {
      const { service, repository } = build();

      await service.loadContext(
        'seeker',
        Array.from({ length: 200 }, (_, i) => `c${i}`),
      );

      expect(repository.findUserAnswers).toHaveBeenCalledTimes(1);
      expect(repository.findResponsesForUsers).toHaveBeenCalledTimes(1);
    });

    it('accepts a prefetched seeker lookup and does not repeat it', async () => {
      const { service, repository } = build();

      const seeker = service.prefetchSeeker('seeker');
      await service.loadContext('seeker', ['c1'], seeker);

      expect(repository.findUserAnswers).toHaveBeenCalledTimes(1);
    });

    it('leaves out a candidate whose answers no longer cover the quiz (never a partial-quiz score)', async () => {
      const stale = allAnswered('B');
      delete stale[QUESTION_IDS[8]];
      const { service } = build({
        findResponsesForUsers: jest.fn().mockResolvedValue([
          { userId: 'stale', answers: stale },
          { userId: 'ok', answers: allAnswered('B') },
        ]),
      });

      const result = await service.loadContext('seeker', ['stale', 'ok']);

      expect(result.answersByUserId.has('stale')).toBe(false);
      expect(result.answersByUserId.has('ok')).toBe(true);
    });

    it.each([
      ['null', null],
      ['an array', ['A']],
      ['a string', 'A'],
    ])(
      'leaves out a candidate whose stored answers are %s',
      async (_l, bad) => {
        const { service } = build({
          findResponsesForUsers: jest.fn().mockResolvedValue([
            { userId: 'bad', answers: bad },
            { userId: 'ok', answers: allAnswered('B') },
          ]),
        });

        const result = await service.loadContext('seeker', ['bad', 'ok']);

        expect(result.answersByUserId.has('bad')).toBe(false);
        expect(result.answersByUserId.has('ok')).toBe(true);
      },
    );
  });

  describe('when psychology cannot apply — empty context, no batch query', () => {
    it('kill switch off: no query of any kind', async () => {
      const { service, provider, repository } = build({
        psychology: { enabled: false, timeoutMs: 200 },
      });

      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
      expect(provider.get).not.toHaveBeenCalled();
      expect(repository.findUserAnswers).not.toHaveBeenCalled();
      expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
    });

    it('no usable quiz', async () => {
      const { service, repository } = build({
        get: jest.fn().mockResolvedValue(null),
      });

      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
      expect(repository.findUserAnswers).not.toHaveBeenCalled();
      expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
    });

    it('the seeker has not completed the quiz — the common case', async () => {
      const { service, repository } = build({
        findUserAnswers: jest.fn().mockResolvedValue(null),
      });

      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
      expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
    });

    it.each([
      ['null', null],
      ['an array', ['A']],
    ])("the seeker's stored answers are %s", async (_l, bad) => {
      const { service, repository } = build({
        findUserAnswers: jest
          .fn()
          .mockResolvedValue({ userId: 'seeker', answers: bad }),
      });

      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
      expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
    });

    it("the seeker's answers predate the quiz's current content", async () => {
      const partial = allAnswered('A');
      delete partial[QUESTION_IDS[0]];
      const { service } = build({
        findUserAnswers: jest
          .fn()
          .mockResolvedValue({ userId: 'seeker', answers: partial }),
      });

      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
    });
  });

  describe('fail-open: it never throws, whatever goes wrong', () => {
    it('the quiz lookup rejects', async () => {
      const { service } = build({
        get: jest.fn().mockRejectedValue(new Error('neon blip')),
      });
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
    });

    it('the quiz lookup throws synchronously', async () => {
      const { service } = build({
        get: jest.fn(() => {
          throw new Error('sync boom');
        }),
      });
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
    });

    it('the seeker lookup rejects', async () => {
      const { service } = build({
        findUserAnswers: jest
          .fn()
          .mockRejectedValue(new Error('pool exhausted')),
      });
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
    });

    it('the candidate batch rejects', async () => {
      const { service } = build({
        findResponsesForUsers: jest
          .fn()
          .mockRejectedValue(new Error('statement timeout')),
      });
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
    });

    it('a query that never settles is abandoned at the time budget', async () => {
      const { service } = build({
        psychology: { enabled: true, timeoutMs: 30 },
        findUserAnswers: jest.fn(() => new Promise(() => undefined)),
      });

      const started = Date.now();
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
      expect(Date.now() - started).toBeLessThan(1000);
    });

    it('a candidate batch that outruns the budget is abandoned', async () => {
      const { service } = build({
        psychology: { enabled: true, timeoutMs: 30 },
        findResponsesForUsers: jest.fn(() => new Promise(() => undefined)),
      });
      await expect(service.loadContext('seeker', ['c1'])).resolves.toEqual(
        EMPTY,
      );
    });

    it('a late rejection after the budget does not surface as an unhandled rejection', async () => {
      const unhandled = jest.fn();
      process.on('unhandledRejection', unhandled);
      let rejectLate: (e: Error) => void = () => undefined;
      const { service } = build({
        psychology: { enabled: true, timeoutMs: 20 },
        findUserAnswers: jest.fn(
          () =>
            new Promise((_, reject) => {
              rejectLate = reject;
            }),
        ),
      });

      await service.loadContext('seeker', ['c1']);
      rejectLate(new Error('too late'));
      await new Promise((r) => setTimeout(r, 20));
      process.off('unhandledRejection', unhandled);

      expect(unhandled).not.toHaveBeenCalled();
    });

    it('a misbehaving caller-supplied seeker lookup that rejects still cannot make it throw', async () => {
      const { service } = build();
      await expect(
        service.loadContext(
          'seeker',
          ['c1'],
          Promise.reject(new Error('caller bug')),
        ),
      ).resolves.toEqual(EMPTY);
    });

    it('prefetchSeeker never rejects', async () => {
      const { service } = build({
        get: jest.fn().mockRejectedValue(new Error('down')),
      });
      await expect(service.prefetchSeeker('seeker')).resolves.toBeNull();
    });
  });

  describe('circuit breaker', () => {
    it('after three consecutive failures it stops querying, then lets one trial through after the cool-down', async () => {
      let now = 1_000_000;
      jest.spyOn(Date, 'now').mockImplementation(() => now);
      const get = jest.fn().mockRejectedValue(new Error('down'));
      const { service } = build({ get });

      for (let i = 0; i < 3; i++) await service.loadContext('seeker', ['c1']);
      expect(get).toHaveBeenCalledTimes(3);

      // Open: no further queries are attempted.
      await service.loadContext('seeker', ['c1']);
      await service.loadContext('seeker', ['c1']);
      expect(get).toHaveBeenCalledTimes(3);

      // Cool-down elapsed: one trial. It fails again, so it re-opens at once.
      now += 31_000;
      await service.loadContext('seeker', ['c1']);
      expect(get).toHaveBeenCalledTimes(4);
      await service.loadContext('seeker', ['c1']);
      expect(get).toHaveBeenCalledTimes(4);

      // Database recovers: the next trial succeeds and the breaker closes.
      now += 31_000;
      get.mockResolvedValue(QUIZ);
      const result = await service.loadContext('seeker', ['c1']);
      expect(result.answersByUserId.has('seeker')).toBe(true);
      await service.loadContext('seeker', ['c1']);
      expect(get).toHaveBeenCalledTimes(6);
    });

    it('a success in between resets the failure count', async () => {
      const get = jest
        .fn()
        .mockRejectedValueOnce(new Error('x'))
        .mockRejectedValueOnce(new Error('x'))
        .mockResolvedValueOnce(QUIZ)
        .mockRejectedValue(new Error('x'));
      const { service } = build({ get });

      for (let i = 0; i < 5; i++) await service.loadContext('seeker', ['c1']);

      // 2 fails, 1 success, then 2 more fails: never 3 in a row, never open.
      expect(get).toHaveBeenCalledTimes(5);
    });
  });

  describe('quiz version: an answer set from another version of the quiz is stale', () => {
    it('treats a response with no recorded version as current (existing answers stay valid)', async () => {
      const { service } = build({
        findUserAnswers: jest.fn().mockResolvedValue({
          userId: 'seeker',
          quizVersion: null,
          answers: allAnswered('A'),
        }),
      });
      expect((await service.loadContext('seeker', ['c1'])).questions).toBe(
        SCORING_QUESTIONS,
      );
    });

    it('accepts a response recorded against the active version', async () => {
      const { service } = build({
        findUserAnswers: jest.fn().mockResolvedValue({
          userId: 'seeker',
          quizVersion: '1.0',
          answers: allAnswered('A'),
        }),
      });
      expect((await service.loadContext('seeker', ['c1'])).questions).toBe(
        SCORING_QUESTIONS,
      );
    });

    it('ignores a seeker whose answers were given against another version', async () => {
      const { service, repository } = build({
        findUserAnswers: jest.fn().mockResolvedValue({
          userId: 'seeker',
          quizVersion: '0.9',
          answers: allAnswered('A'),
        }),
      });
      expect(await service.loadContext('seeker', ['c1'])).toEqual(EMPTY);
      expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
    });

    it('leaves out only the candidates whose answers are from another version', async () => {
      const { service } = build({
        findResponsesForUsers: jest.fn().mockResolvedValue([
          { userId: 'old', quizVersion: '0.9', answers: allAnswered('B') },
          { userId: 'new', quizVersion: '1.0', answers: allAnswered('B') },
          { userId: 'legacy', quizVersion: null, answers: allAnswered('B') },
        ]),
      });
      const result = await service.loadContext('seeker', [
        'old',
        'new',
        'legacy',
      ]);
      expect(result.answersByUserId.has('old')).toBe(false);
      expect(result.answersByUserId.has('new')).toBe(true);
      expect(result.answersByUserId.has('legacy')).toBe(true);
    });
  });

  describe('observability', () => {
    it('counts failures, timeouts and breaker skips without ever throwing', async () => {
      const { service } = build({
        psychology: { enabled: true, timeoutMs: 20 },
        get: jest
          .fn()
          .mockRejectedValueOnce(new Error('down'))
          .mockImplementationOnce(() => new Promise(() => undefined))
          .mockRejectedValueOnce(new Error('down')),
      });

      await service.loadContext('seeker', ['c1']); // failure
      await service.loadContext('seeker', ['c1']); // timeout
      await service.loadContext('seeker', ['c1']); // failure -> breaker opens
      await service.loadContext('seeker', ['c1']); // skipped

      expect(service.stats).toEqual({
        failures: 2,
        timeouts: 1,
        breakerSkips: 1,
      });
    });

    it('never logs the database error message (it can embed a member answers)', async () => {
      const logs: string[] = [];
      jest.spyOn(Logger.prototype, 'warn').mockImplementation((m: unknown) => {
        logs.push(String(m));
      });
      const prismaLike = Object.assign(
        new Error(
          'Invalid `prisma.userQuizResponse.create()` invocation: answers: {"q1":"A"}',
        ),
        { name: 'PrismaClientKnownRequestError', code: 'P2002' },
      );
      const { service } = build({
        findUserAnswers: jest.fn().mockRejectedValue(prismaLike),
      });

      await service.loadContext('seeker', ['c1']);

      const logged = logs.join(' ');
      expect(logged).toContain('PrismaClientKnownRequestError (P2002)');
      expect(logged).not.toContain('answers');
      expect(logged).not.toContain('q1');
    });
  });
});
