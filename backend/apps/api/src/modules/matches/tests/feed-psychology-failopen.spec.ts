import type { S3Service } from '@app/storage';
import type { AppConfigService } from '@app/config';
import { FeedService } from '../services/feed.service';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { CompatibilityService } from '../scoring/compatibility.service';
import { RankingService } from '../scoring/ranking.service';
import type { FeedSeenService } from '../cache/feed-seen.cache';
import type { FeedVersionService } from '../cache/feed-version.cache';
import type { FeedProfileRow } from '../repositories/feed.repository';
import { PsychologyMatchContextService } from '../scoring/psychology/psychology-match-context.service';
import type { PsychologyRepository } from '../../psychology/repositories/psychology.repository';
import type { PsychologyScoringQuizProvider } from '../../psychology/scoring/psychology-scoring-quiz.provider';
import { resetWarnThrottle } from '../../psychology/scoring/psychology-log';
import {
  QUIZ_ID,
  SCORING_QUESTIONS,
  allAnswered,
  withAnswers,
} from '../../psychology/tests/psychology-fixtures';

/**
 * The hard requirement: psychology is an optional signal and must never turn
 * GET /discover into an error, and must never cost a member their score.
 *
 * Every case runs the REAL FeedService, CompatibilityService, RankingService,
 * ProfileFeedMapper and PsychologyMatchContextService — only the database edge
 * (repository / quiz provider) and Redis are faked. Three candidates have
 * IDENTICAL profiles, so any difference in order or score comes from
 * psychology alone:
 *
 *   c1  took the quiz, compatible with the seeker
 *   c2  took the quiz, hard-axis conflict with the seeker
 *   c3  did not take the quiz
 */
const s3 = {
  isConfigured: () => false,
  getPresignedGetUrl: () => Promise.resolve(''),
} as unknown as S3Service;

function profileRow(userId: string, i: number): FeedProfileRow {
  return {
    userId,
    firstName: userId,
    lastName: 'X',
    dob: new Date('1996-01-01'),
    gender: 'FEMALE',
    religion: 'Hindu',
    motherTongue: 'Tamil',
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    profileCompletePct: 100,
    createdAt: new Date(Date.UTC(2026, 0, 1) - i * 1000),
    updatedAt: new Date(),
    user: { trustScore: 60 },
  };
}

const SEEKER = {
  ...profileRow('me', 0),
  gender: 'MALE',
  user: { trustScore: 60 },
};
const CANDIDATES = ['c1', 'c2', 'c3'].map((id, i) => profileRow(id, i + 1));

const HEALTHY_CANDIDATE_ANSWERS: Record<string, Record<string, string>> = {
  c1: allAnswered('A'),
  c2: withAnswers(allAnswered('A'), { 9: 'D' }),
};

interface Faults {
  quiz?: 'reject' | 'hang' | 'none';
  seekerRow?: 'reject' | 'hang' | 'corrupt' | 'none';
  batch?: 'reject' | 'hang';
  enabled?: boolean;
  candidateAnswers?: Record<string, Record<string, string>>;
}

const SECRET = 'feed-test-secret-of-sufficient-length';

function buildFeed(faults: Faults = {}) {
  const hang = () => new Promise<never>(() => undefined);

  const quizProvider = {
    get: jest.fn(() => {
      if (faults.quiz === 'reject') return Promise.reject(new Error('quiz db'));
      if (faults.quiz === 'hang') return hang();
      if (faults.quiz === 'none') return Promise.resolve(null);
      return Promise.resolve({
        quizId: QUIZ_ID,
        version: '1.0',
        questions: SCORING_QUESTIONS,
      });
    }),
  };
  const repository = {
    findUserAnswers: jest.fn(() => {
      if (faults.seekerRow === 'reject') return Promise.reject(new Error('x'));
      if (faults.seekerRow === 'hang') return hang();
      if (faults.seekerRow === 'none') return Promise.resolve(null);
      return Promise.resolve({
        userId: 'me',
        quizVersion: null,
        answers: faults.seekerRow === 'corrupt' ? null : allAnswered('A'),
      });
    }),
    findResponsesForUsers: jest.fn(() => {
      if (faults.batch === 'reject') return Promise.reject(new Error('x'));
      if (faults.batch === 'hang') return hang();
      return Promise.resolve(
        Object.entries(
          faults.candidateAnswers ?? HEALTHY_CANDIDATE_ANSWERS,
        ).map(([userId, answers]) => ({ userId, answers, quizVersion: null })),
      );
    }),
  };
  const config = {
    psychology: { enabled: faults.enabled ?? true, timeoutMs: 40 },
    jwt: { secret: SECRET },
  };

  const context = new PsychologyMatchContextService(
    repository as unknown as PsychologyRepository,
    quizProvider as unknown as PsychologyScoringQuizProvider,
    config as unknown as AppConfigService,
  );

  const recommendation = {
    getFeedForUser: jest.fn().mockResolvedValue({
      rows: CANDIDATES,
      tier: 1,
      fallbackUsed: false,
      reason: '',
      relaxedFilters: [],
      seeker: SEEKER,
      seekerPreference: null,
    }),
  };

  const service = new FeedService(
    recommendation,
    new ProfileFeedMapper(s3),
    new CompatibilityService(),
    new RankingService(),
    {
      get: jest.fn().mockResolvedValue(new Set<string>()),
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as FeedSeenService,
    { get: jest.fn().mockResolvedValue(1) } as unknown as FeedVersionService,
    context,
    config as unknown as AppConfigService,
  );

  return { service, repository, quizProvider, recommendation, context };
}

async function feedOf(faults: Faults, query: { limit?: number } = {}) {
  const { service } = buildFeed(faults);
  return service.getFeed('me', { page: 1, limit: query.limit ?? 20 });
}

/** What a member can see per card, in feed order. */
async function visible(faults: Faults) {
  const result = await feedOf(faults);
  return result.items.map((i) => ({
    id: i.id,
    aiMatchPercent: i.compatibility.aiMatchPercent,
    overallCompatibility: i.compatibility.overallCompatibility,
  }));
}

const ids = (items: Array<{ id: string }>) => items.map((i) => i.id);

/** The ordering with psychology off: identical profiles fall back to createdAt. */
const BASELINE_ORDER = ['c1', 'c2', 'c3'];

describe('Discover with psychology: the four states', () => {
  beforeEach(() => resetWarnThrottle());

  it('neither member took the quiz: the plain ordering and scores', async () => {
    const items = await visible({ seekerRow: 'none', candidateAnswers: {} });
    expect(ids(items)).toEqual(BASELINE_ORDER);
  });

  it('only the seeker took it: no candidate has answers, so nothing changes', async () => {
    const items = await visible({ candidateAnswers: {} });
    expect(ids(items)).toEqual(BASELINE_ORDER);
  });

  it('only some candidates took it while the seeker did not: nothing changes', async () => {
    const items = await visible({ seekerRow: 'none' });
    expect(ids(items)).toEqual(BASELINE_ORDER);
  });

  it('both took it (c1, c2): the compatible taker leads, the non-taker is untouched, the conflict is demoted', async () => {
    const items = await visible({});
    // c1 +bonus, c3 (no quiz) +0, c2 -10 for the declared hard-axis conflict.
    expect(ids(items)).toEqual(['c1', 'c3', 'c2']);
  });

  it('a member who did not take the quiz keeps exactly the score they have with psychology switched off', async () => {
    const off = await visible({ enabled: false });
    const on = await visible({});
    const score = (items: typeof on, id: string) =>
      items.find((i) => i.id === id)!;
    expect(score(on, 'c3')).toEqual(score(off, 'c3'));
  });
});

describe('Discover with psychology: what a member can see never changes', () => {
  beforeEach(() => resetWarnThrottle());

  it('every visible score is identical whether or not psychology applies — only the order can differ', async () => {
    const off = await visible({ enabled: false });
    const on = await visible({});
    const byId = (items: typeof on) =>
      Object.fromEntries(items.map((i) => [i.id, i]));
    expect(byId(on)).toEqual(byId(off));
    expect(ids(on)).not.toEqual(ids(off)); // psychology did act on the order
  });

  it('the response carries no psychology or ranking-key data', async () => {
    const result = await feedOf({});
    const json = JSON.stringify(result);
    for (const forbidden of [
      'psychologyRefinement',
      'ranking',
      'refinement',
      'hardAxis',
      'pairRules',
      'psychologyAnswers',
    ]) {
      expect(json).not.toContain(forbidden);
    }
  });

  it('the next-page cursor does not reveal the ranking score', async () => {
    const result = await feedOf({}, { limit: 1 });
    expect(result.nextCursor).toEqual(expect.any(String));
    const cursor = result.nextCursor!;
    // Not decodable as the old plain base64 JSON, and no score/user id inside.
    const asPlain = Buffer.from(cursor, 'base64url').toString('utf8');
    expect(asPlain).not.toContain('userId');
    expect(asPlain).not.toContain('score');
  });
});

describe('Discover with psychology: cursor paging stays correct and tamper-proof', () => {
  beforeEach(() => resetWarnThrottle());

  it('pages through the full ordering, once each, using the sealed cursor', async () => {
    const seen: string[] = [];
    let cursor: string | undefined;
    for (let i = 0; i < 4; i++) {
      const { service } = buildFeed();
      const page = await service.getFeed('me', { limit: 1, cursor });
      seen.push(...ids(page.items));
      if (!page.nextCursor) break;
      cursor = page.nextCursor;
    }
    expect(seen).toEqual(['c1', 'c3', 'c2']);
  });

  it('a forged plain cursor is ignored (starts from the top rather than probing a score)', async () => {
    const forged = Buffer.from(
      JSON.stringify({ score: 0, createdAt: 0, userId: '' }),
    ).toString('base64url');
    const { service } = buildFeed();
    const page = await service.getFeed('me', { limit: 20, cursor: forged });
    expect(ids(page.items)).toEqual(['c1', 'c3', 'c2']);
  });

  it("another member's cursor is ignored", async () => {
    const { service } = buildFeed();
    const first = await service.getFeed('me', { limit: 1 });
    const stolen = first.nextCursor!;
    const other = buildFeed();
    const page = await other.service.getFeed('someone-else', {
      limit: 20,
      cursor: stolen,
    });
    // Treated as no cursor: the full first page, not "after c1".
    expect(ids(page.items)).toContain('c1');
  });
});

describe('Discover with psychology: fail-open', () => {
  beforeEach(() => resetWarnThrottle());

  it.each<[string, Faults]>([
    ['the quiz lookup rejects', { quiz: 'reject' }],
    ['the quiz lookup hangs', { quiz: 'hang' }],
    ['the seeker row lookup rejects', { seekerRow: 'reject' }],
    ['the seeker row lookup hangs', { seekerRow: 'hang' }],
    [
      "the seeker's stored answers are corrupt (null)",
      { seekerRow: 'corrupt' },
    ],
    ['the candidate batch rejects', { batch: 'reject' }],
    ['the candidate batch hangs', { batch: 'hang' }],
    ['there is no active quiz', { quiz: 'none' }],
    ['the kill switch is off', { enabled: false }],
    [
      "every candidate's stored answers are corrupt",
      {
        candidateAnswers: {
          c1: null as unknown as Record<string, string>,
          c2: [] as unknown as Record<string, string>,
        },
      },
    ],
  ])(
    'still returns the normal feed — same order, same scores — when %s',
    async (_label, faults) => {
      const baseline = await visible({ enabled: false });
      const items = await visible(faults);
      expect(items).toEqual(baseline);
    },
  );

  it('does not wait on a hung psychology query beyond its budget', async () => {
    const started = Date.now();
    await feedOf({ seekerRow: 'hang' });
    expect(Date.now() - started).toBeLessThan(1500);
  });

  it('issues no psychology query at all when the kill switch is off', async () => {
    const { service, repository, quizProvider } = buildFeed({ enabled: false });
    await service.getFeed('me', { page: 1, limit: 20 });
    expect(quizProvider.get).not.toHaveBeenCalled();
    expect(repository.findUserAnswers).not.toHaveBeenCalled();
    expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
  });

  it('starts the seeker lookup while the candidate query is still in flight (they overlap)', async () => {
    const order: string[] = [];
    const { service, repository, recommendation } = buildFeed();
    (repository.findUserAnswers as jest.Mock).mockImplementation(() => {
      order.push('seeker-lookup');
      return Promise.resolve({
        userId: 'me',
        quizVersion: null,
        answers: allAnswered('A'),
      });
    });
    const original = recommendation.getFeedForUser.getMockImplementation()!;
    recommendation.getFeedForUser.mockImplementation(
      (...args: unknown[]): Promise<unknown> => {
        order.push('candidate-query');
        return original(...args) as Promise<unknown>;
      },
    );

    await service.getFeed('me', { page: 1, limit: 20 });

    expect(order).toEqual(['candidate-query', 'seeker-lookup']);
  });

  it('a member with no seeker profile gets the empty feed without any candidate psychology query', async () => {
    const { service, repository, recommendation } = buildFeed();
    recommendation.getFeedForUser.mockResolvedValue({
      rows: [],
      seeker: null,
      seekerPreference: null,
    });

    const result = await service.getFeed('me', { page: 1, limit: 20 });

    expect(result.items).toEqual([]);
    expect(repository.findResponsesForUsers).not.toHaveBeenCalled();
  });

  it('a psychology failure is counted, and never surfaces as an error', async () => {
    const { service, context } = buildFeed({ batch: 'reject' });
    await expect(
      service.getFeed('me', { page: 1, limit: 20 }),
    ).resolves.toBeDefined();
    expect(context.stats.failures).toBe(1);
  });
});
