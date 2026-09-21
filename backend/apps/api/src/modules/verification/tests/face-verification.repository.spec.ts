import type { PrismaService } from '@app/database';
import { FaceVerificationRepository } from '../repositories/face-verification.repository';

/**
 * Pins the query shapes that carry the security and cost guarantees:
 * ownership scoping, the per-member row lock, the "counted attempt" rule, the
 * conditional claim, and what a decision writes. A fake Prisma records calls;
 * no database is involved.
 */
type Args = Record<string, unknown>;
type QueryMock<R = unknown> = jest.Mock<Promise<R>, [Args]>;

interface PrismaMock {
  profilePhoto: { findFirst: QueryMock };
  faceVerification: { findUnique: QueryMock; upsert: QueryMock };
  faceVerificationAttempt: {
    findFirst: QueryMock;
    updateMany: QueryMock<{ count: number }>;
    count: QueryMock<number>;
    create: QueryMock;
    update: QueryMock;
  };
  $queryRaw: jest.Mock<
    Promise<unknown[]>,
    [TemplateStringsArray, ...unknown[]]
  >;
  $transaction: jest.Mock<
    Promise<unknown>,
    [(tx: PrismaMock) => Promise<unknown>]
  >;
}

function makePrisma(): PrismaMock {
  const echo = (id: string) => (args: Args) =>
    Promise.resolve({ id, ...(args.data as Args) });
  const query = <R>(value: R): QueryMock<R> =>
    jest.fn<Promise<R>, [Args]>(() => Promise.resolve(value));
  const prisma: PrismaMock = {
    profilePhoto: { findFirst: query<unknown>(null) },
    faceVerification: {
      findUnique: query<unknown>(null),
      upsert: query<unknown>({}),
    },
    faceVerificationAttempt: {
      findFirst: query<unknown>(null),
      updateMany: query({ count: 1 }),
      count: query(0),
      create: jest.fn(echo('new')),
      update: jest.fn(echo('a1')),
    },
    $queryRaw: jest.fn<
      Promise<unknown[]>,
      [TemplateStringsArray, ...unknown[]]
    >(() => Promise.resolve([])),
    $transaction: jest.fn((fn: (tx: PrismaMock) => Promise<unknown>) =>
      fn(prisma),
    ),
  };
  return prisma;
}

const COUNTED = {
  NOT: { AND: [{ outcome: 'ERROR' }, { livenessSessionId: null }] },
};

function reserveParams(overrides: Record<string, unknown> = {}) {
  const now = new Date('2026-09-21T10:00:00Z');
  return {
    userId: 'user-1',
    photo: { id: 'photo-1', s3Key: 'profile-photos/user-1/a.jpg' },
    now,
    expiresAt: new Date(now.getTime() + 180_000),
    userWindowStart: new Date(now.getTime() - 86_400_000),
    globalWindowStart: new Date('2026-09-21T00:00:00Z'),
    maxAttemptsPerUser: 3,
    globalDailyCap: 500,
    livenessThreshold: 90,
    similarityThreshold: 90,
    ...overrides,
  };
}

describe('FaceVerificationRepository', () => {
  let prisma: ReturnType<typeof makePrisma>;
  let repo: FaceVerificationRepository;

  beforeEach(() => {
    prisma = makePrisma();
    repo = new FaceVerificationRepository(prisma as unknown as PrismaService);
  });

  it('scopes an attempt lookup to its owner', async () => {
    await repo.findOwnedAttempt('a1', 'user-1');
    expect(prisma.faceVerificationAttempt.findFirst).toHaveBeenCalledWith({
      where: { id: 'a1', userId: 'user-1' },
    });
  });

  it('reads the primary photo by the isPrimary flag only', async () => {
    await repo.findPrimaryPhoto('user-1');
    expect(prisma.profilePhoto.findFirst).toHaveBeenCalledWith({
      where: { userId: 'user-1', isPrimary: true },
      select: { id: true, s3Key: true },
    });
  });

  it('counts only attempts that reached AWS', async () => {
    const since = new Date('2026-09-20T10:00:00Z');
    await repo.countUserAttemptsSince('user-1', since);
    expect(prisma.faceVerificationAttempt.count).toHaveBeenCalledWith({
      where: { userId: 'user-1', createdAt: { gte: since }, ...COUNTED },
    });
  });

  describe('reserveAttempt', () => {
    it('locks the member row, supersedes live attempts, then creates the attempt', async () => {
      const result = await repo.reserveAttempt(reserveParams());

      expect(prisma.faceVerification.upsert).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        create: { userId: 'user-1' },
        update: {},
      });
      const [sql, ...values] = prisma.$queryRaw.mock.calls[0];
      expect(sql.join('?')).toContain('FOR UPDATE');
      expect(values).toEqual(['user-1']);
      expect(prisma.faceVerificationAttempt.updateMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', outcome: 'PENDING' },
        data: <unknown>expect.objectContaining({
          outcome: 'EXPIRED',
          failureReason: 'SUPERSEDED',
        }),
      });
      expect(prisma.faceVerificationAttempt.create).toHaveBeenCalledWith({
        data: <unknown>expect.objectContaining({
          userId: 'user-1',
          provider: 'AWS_REKOGNITION',
          comparedPhotoId: 'photo-1',
          comparedPhotoS3Key: 'profile-photos/user-1/a.jpg',
          livenessThreshold: 90,
          similarityThreshold: 90,
        }),
      });
      expect(result.kind).toBe('CREATED');
    });

    it('returns USER_LIMIT without creating when the member is at the cap', async () => {
      const oldest = new Date('2026-09-21T01:00:00Z');
      prisma.faceVerificationAttempt.count.mockResolvedValueOnce(3);
      prisma.faceVerificationAttempt.findFirst.mockResolvedValueOnce({
        createdAt: oldest,
      });

      await expect(repo.reserveAttempt(reserveParams())).resolves.toEqual({
        kind: 'USER_LIMIT',
        oldestCountedAt: oldest,
      });
      expect(prisma.faceVerificationAttempt.create).not.toHaveBeenCalled();
    });

    it('returns GLOBAL_LIMIT without creating when the daily cap is reached', async () => {
      prisma.faceVerificationAttempt.count
        .mockResolvedValueOnce(0) // member
        .mockResolvedValueOnce(500); // global
      await expect(repo.reserveAttempt(reserveParams())).resolves.toEqual({
        kind: 'GLOBAL_LIMIT',
      });
      expect(prisma.faceVerificationAttempt.create).not.toHaveBeenCalled();
    });
  });

  it('claims only a PENDING attempt owned by the caller', async () => {
    const now = new Date();
    prisma.faceVerificationAttempt.updateMany.mockResolvedValueOnce({
      count: 0,
    });
    await expect(
      repo.claimForProcessing('a1', 'user-1', now, { outcome: 'COMPLETED' }),
    ).resolves.toBe(false);
    expect(prisma.faceVerificationAttempt.updateMany).toHaveBeenCalledWith({
      where: { id: 'a1', userId: 'user-1', outcome: 'PENDING' },
      data: {
        outcome: 'PROCESSING',
        processingStartedAt: now,
        clientOutcome: 'COMPLETED',
        clientErrorCode: null,
      },
    });
  });

  it('expires stale PENDING attempts and times out abandoned PROCESSING ones', async () => {
    const now = new Date('2026-09-21T10:00:00Z');
    await repo.expireStaleAttempts('user-1', now, 60_000);
    expect(prisma.faceVerificationAttempt.updateMany).toHaveBeenNthCalledWith(
      1,
      {
        where: {
          userId: 'user-1',
          outcome: 'PENDING',
          expiresAt: { lte: now },
        },
        data: <unknown>expect.objectContaining({ outcome: 'EXPIRED' }),
      },
    );
    expect(prisma.faceVerificationAttempt.updateMany).toHaveBeenNthCalledWith(
      2,
      {
        where: {
          userId: 'user-1',
          outcome: 'PROCESSING',
          expiresAt: { lte: new Date(now.getTime() - 60_000) },
        },
        data: <unknown>expect.objectContaining({
          outcome: 'ERROR',
          failureReason: 'PROCESSING_TIMEOUT',
        }),
      },
    );
  });

  describe('finalizeAttempt', () => {
    const now = new Date('2026-09-21T10:01:00Z');

    it('records a verification bound to the exact matched photo', async () => {
      await repo.finalizeAttempt({
        attemptId: 'a1',
        userId: 'user-1',
        outcome: 'VERIFIED',
        now,
        livenessConfidence: 97,
        matchSimilarity: 98,
        matchedPhoto: { id: 'photo-1', s3Key: 'profile-photos/user-1/a.jpg' },
      });

      const call = prisma.faceVerification.upsert.mock.calls[0][0] as {
        update: Record<string, unknown>;
      };
      expect(call.update).toMatchObject({
        status: 'VERIFIED',
        provider: 'AWS_REKOGNITION',
        isVerified: true,
        matchedPhotoId: 'photo-1',
        matchedPhotoS3Key: 'profile-photos/user-1/a.jpg',
        latestAttemptId: 'a1',
        verifiedAt: now,
        revokedAt: null,
      });
      // No biometric artefact is written anywhere.
      expect(JSON.stringify(call)).not.toMatch(/selfie|reference/i);
    });

    it('never downgrades the stored state on failure — only moves latestAttemptId', async () => {
      await repo.finalizeAttempt({
        attemptId: 'a1',
        userId: 'user-1',
        outcome: 'FAILED_MATCH',
        now,
      });
      expect(prisma.faceVerification.upsert).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        create: { userId: 'user-1', latestAttemptId: 'a1' },
        update: { latestAttemptId: 'a1' },
      });
    });
  });
});
