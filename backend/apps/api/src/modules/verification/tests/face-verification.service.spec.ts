import { HttpException } from '@nestjs/common';
import type { AppConfigService } from '@app/config';
import type { GetObjectBytesResult, S3Service } from '@app/storage';
import type { FaceVerificationAttempt } from '../../../../../../libs/database/generated/client';
import { FaceVerificationService } from '../services/face-verification.service';
import type {
  CompareFacesResult,
  FaceLivenessGateway,
  LivenessSessionResult,
} from '../gateways/face-liveness.gateway';
import type {
  FaceVerificationRepository,
  FinalizeAttemptParams,
  ReserveAttemptParams,
  StoredStateRow,
} from '../repositories/face-verification.repository';
import type { PrimaryPhotoRef } from '../domain/face-verification-state';

// ─── In-memory stand-ins ─────────────────────────────────────────────────
//
// The repository double keeps real state (attempts + current verification)
// so the service's flow — caps, idempotency, ownership, derivation — is
// exercised end to end. Nothing here reaches AWS, S3 or a database.

const USER = 'user-1';
const OTHER_USER = 'user-2';
const PHOTO: PrimaryPhotoRef = {
  id: 'photo-1',
  s3Key: 'profile-photos/user-1/a.jpg',
};
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const PERMANENT_KEY = 'test-permanent-backend-key-id';

/** A jest mock that resolves whatever the synchronous `fn` returns. */
function later<A extends unknown[], R>(fn: (...args: A) => R) {
  return jest.fn((...args: A) => Promise.resolve(fn(...args)));
}

class InMemoryRepository {
  attempts: FaceVerificationAttempt[] = [];
  state = new Map<string, StoredStateRow & { latestAttemptId?: string }>();
  primary = new Map<string, PrimaryPhotoRef | null>([[USER, PHOTO]]);
  private seq = 0;

  private counted(userId: string | null, since: Date) {
    return this.attempts.filter(
      (a) =>
        (userId === null || a.userId === userId) &&
        a.createdAt >= since &&
        !(a.outcome === 'ERROR' && a.livenessSessionId === null),
    );
  }

  findPrimaryPhoto = later(
    (userId: string) => this.primary.get(userId) ?? null,
  );
  findState = later((userId: string) => this.state.get(userId) ?? null);
  findOwnedAttempt = later(
    (id: string, userId: string) =>
      this.attempts.find((a) => a.id === id && a.userId === userId) ?? null,
  );
  expireStaleAttempts = later((userId: string, now: Date) => {
    for (const a of this.attempts) {
      if (
        a.userId === userId &&
        a.outcome === 'PENDING' &&
        a.expiresAt <= now
      ) {
        a.outcome = 'EXPIRED';
      }
    }
  });
  countUserAttemptsSince = later(
    (userId: string, since: Date) => this.counted(userId, since).length,
  );
  oldestUserAttemptSince = later((userId: string, since: Date) => {
    const rows = this.counted(userId, since).sort(
      (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
    );
    return rows[0]?.createdAt ?? null;
  });
  countGlobalAttemptsSince = later(
    (since: Date) => this.counted(null, since).length,
  );
  reserveAttempt = later((p: ReserveAttemptParams) => {
    for (const a of this.attempts) {
      if (a.userId === p.userId && a.outcome === 'PENDING')
        a.outcome = 'EXPIRED';
    }
    const userRows = this.counted(p.userId, p.userWindowStart);
    if (userRows.length >= p.maxAttemptsPerUser) {
      return {
        kind: 'USER_LIMIT' as const,
        oldestCountedAt: userRows[0]?.createdAt ?? null,
      };
    }
    if (this.counted(null, p.globalWindowStart).length >= p.globalDailyCap) {
      return { kind: 'GLOBAL_LIMIT' as const };
    }
    const attempt = this.insert({
      userId: p.userId,
      comparedPhotoId: p.photo.id,
      comparedPhotoS3Key: p.photo.s3Key,
      livenessThreshold: p.livenessThreshold,
      similarityThreshold: p.similarityThreshold,
      createdAt: p.now,
      expiresAt: p.expiresAt,
    });
    return { kind: 'CREATED' as const, attempt };
  });
  setLivenessSession = later((id: string, sessionId: string) => {
    this.byId(id).livenessSessionId = sessionId;
  });
  claimForProcessing = later(
    (id: string, userId: string, _now: Date, client: { outcome?: string }) => {
      const a = this.attempts.find((x) => x.id === id && x.userId === userId);
      if (!a || a.outcome !== 'PENDING') return false;
      a.outcome = 'PROCESSING';
      a.clientOutcome = client.outcome ?? null;
      return true;
    },
  );
  releaseClaim = later((id: string) => {
    const a = this.byId(id);
    if (a.outcome === 'PROCESSING') a.outcome = 'PENDING';
  });
  finalizeAttempt = later((p: FinalizeAttemptParams) => {
    const a = this.byId(p.attemptId);
    Object.assign(a, {
      outcome: p.outcome,
      livenessStatus: p.livenessStatus ?? null,
      livenessConfidence: p.livenessConfidence ?? null,
      matchSimilarity: p.matchSimilarity ?? null,
      targetFaceCount: p.targetFaceCount ?? null,
      failureReason: p.failureReason ?? null,
      completedAt: p.now,
    });
    const current = this.state.get(p.userId);
    if (p.outcome === 'VERIFIED' && p.matchedPhoto) {
      this.state.set(p.userId, {
        status: 'VERIFIED',
        matchedPhotoId: p.matchedPhoto.id,
        matchedPhotoS3Key: p.matchedPhoto.s3Key,
        revokedAt: null,
        verifiedAt: p.now,
        latestAttemptId: a.id,
      });
    } else {
      this.state.set(p.userId, {
        ...(current ?? {
          status: 'UNVERIFIED',
          matchedPhotoId: null,
          matchedPhotoS3Key: null,
          revokedAt: null,
          verifiedAt: null,
        }),
        latestAttemptId: a.id,
      });
    }
    return a;
  });

  insert(
    fields: Partial<Record<keyof FaceVerificationAttempt, unknown>>,
  ): FaceVerificationAttempt {
    this.seq += 1;
    const now = new Date();
    const attempt = {
      id: `00000000-0000-4000-8000-${String(this.seq).padStart(12, '0')}`,
      userId: USER,
      provider: 'AWS_REKOGNITION',
      livenessSessionId: null,
      livenessStatus: null,
      livenessConfidence: null,
      comparedPhotoId: PHOTO.id,
      comparedPhotoS3Key: PHOTO.s3Key,
      matchSimilarity: null,
      targetFaceCount: null,
      livenessThreshold: 90,
      similarityThreshold: 90,
      outcome: 'PENDING',
      failureReason: null,
      clientOutcome: null,
      clientErrorCode: null,
      consentAt: now,
      expiresAt: new Date(now.getTime() + 3 * 60 * 1000),
      processingStartedAt: null,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
      ...fields,
    } as unknown as FaceVerificationAttempt;
    this.attempts.push(attempt);
    return attempt;
  }

  private byId(id: string): FaceVerificationAttempt {
    const a = this.attempts.find((x) => x.id === id);
    if (!a) throw new Error(`no attempt ${id}`);
    return a;
  }
}

function makeGateway(configured = true) {
  return {
    isConfigured: jest.fn(() => configured),
    region: jest.fn(() => 'ap-south-1'),
    createLivenessSession: later(() => 'session-1'),
    getLivenessSessionResults: later((): LivenessSessionResult => ({
      status: 'SUCCEEDED',
      confidence: 97,
      referenceImage: new Uint8Array([7, 7, 7]),
    })),
    compareFaces: later((): CompareFacesResult => ({
      faceCount: 1,
      bestSimilarity: 98,
    })),
    issueClientCredentials: later(() => ({
      accessKeyId: 'ASIATEMPORARY',
      secretAccessKey: 'temp-secret',
      sessionToken: 'temp-token',
      expiration: new Date('2026-09-21T10:15:00Z'),
    })),
  } satisfies FaceLivenessGateway;
}

function makeS3(
  result: GetObjectBytesResult = {
    ok: true,
    bytes: JPEG,
    format: 'jpeg',
    contentLength: JPEG.length,
  },
) {
  return {
    isConfigured: jest.fn(() => true),
    getObjectBytes: later(() => result),
  };
}

function makeConfig(overrides: Record<string, unknown> = {}): AppConfigService {
  return {
    faceVerification: {
      enabled: true,
      region: 'ap-south-1',
      accessKeyId: PERMANENT_KEY,
      secretAccessKey: 'permanent-secret',
      clientRoleArn:
        'arn:aws:iam::123456789012:role/nenjam-face-liveness-client',
      credentialsTtlSeconds: 900,
      minLivenessConfidence: 90,
      minMatchSimilarity: 90,
      maxAttemptsPerDay: 3,
      globalDailyCap: 500,
      ...overrides,
    },
  } as unknown as AppConfigService;
}

function setup(
  opts: {
    config?: Record<string, unknown>;
    gatewayConfigured?: boolean;
    s3?: ReturnType<typeof makeS3>;
  } = {},
) {
  const repo = new InMemoryRepository();
  const gateway = makeGateway(opts.gatewayConfigured ?? true);
  const s3 = opts.s3 ?? makeS3();
  const service = new FaceVerificationService(
    makeConfig(opts.config),
    repo as unknown as FaceVerificationRepository,
    s3 as unknown as S3Service,
    gateway,
  );
  return { service, repo, gateway, s3 };
}

async function expectHttpError(
  promise: Promise<unknown>,
  status: number,
  code: string,
): Promise<Record<string, unknown>> {
  try {
    await promise;
  } catch (error) {
    expect(error).toBeInstanceOf(HttpException);
    const http = error as HttpException;
    expect(http.getStatus()).toBe(status);
    const body = http.getResponse() as Record<string, unknown>;
    expect(body.code).toBe(code);
    return body;
  }
  throw new Error(`expected HTTP ${status} ${code}, but the call succeeded`);
}

const START = { consent: true as const };

describe('FaceVerificationService', () => {
  describe('availability', () => {
    it('refuses to start when disabled, without touching AWS or S3', async () => {
      const { service, gateway, s3 } = setup({ config: { enabled: false } });
      await expectHttpError(
        service.startSession(USER, START),
        503,
        'NOT_AVAILABLE',
      );
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
      expect(s3.getObjectBytes).not.toHaveBeenCalled();
    });

    it('refuses to start when enabled but the AWS identity is not configured', async () => {
      const { service, gateway } = setup({ gatewayConfigured: false });
      await expectHttpError(
        service.startSession(USER, START),
        503,
        'NOT_AVAILABLE',
      );
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
    });

    it('refuses to complete when disabled', async () => {
      const { service } = setup({ config: { enabled: false } });
      await expectHttpError(
        service.complete(USER, {
          attemptId: '00000000-0000-4000-8000-000000000001',
        }),
        503,
        'NOT_AVAILABLE',
      );
    });
  });

  describe('startSession', () => {
    it('creates an attempt, a liveness session and scoped device credentials', async () => {
      const { service, repo, gateway } = setup();

      const res = await service.startSession(USER, START);

      const attempt = repo.attempts[0];
      expect(res).toEqual({
        attemptId: attempt.id,
        sessionId: 'session-1',
        region: 'ap-south-1',
        expiresAt: attempt.expiresAt.toISOString(),
        credentials: {
          accessKeyId: 'ASIATEMPORARY',
          secretAccessKey: 'temp-secret',
          sessionToken: 'temp-token',
          expiration: '2026-09-21T10:15:00.000Z',
        },
      });
      expect(gateway.createLivenessSession).toHaveBeenCalledWith(attempt.id);
      expect(gateway.issueClientCredentials).toHaveBeenCalledWith(
        `nenjam-fv-${attempt.id}`,
      );
      expect(attempt.livenessSessionId).toBe('session-1');
      expect(attempt.comparedPhotoId).toBe(PHOTO.id);
      expect(attempt.comparedPhotoS3Key).toBe(PHOTO.s3Key);
      expect(attempt.expiresAt.getTime() - attempt.createdAt.getTime()).toBe(
        3 * 60 * 1000,
      );
    });

    it('never returns the permanent backend credentials', async () => {
      const { service } = setup();
      const res = await service.startSession(USER, START);
      expect(JSON.stringify(res)).not.toContain(PERMANENT_KEY);
      expect(JSON.stringify(res)).not.toContain('permanent-secret');
    });

    it('refuses a member who is already verified against their current primary photo', async () => {
      const { service, repo, gateway } = setup();
      repo.state.set(USER, {
        status: 'VERIFIED',
        matchedPhotoId: PHOTO.id,
        matchedPhotoS3Key: PHOTO.s3Key,
        revokedAt: null,
        verifiedAt: new Date(),
      });
      await expectHttpError(
        service.startSession(USER, START),
        409,
        'ALREADY_VERIFIED',
      );
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
    });

    it('lets a member re-verify once the verified photo stopped being primary', async () => {
      const { service, repo } = setup();
      repo.state.set(USER, {
        status: 'VERIFIED',
        matchedPhotoId: 'old-photo',
        matchedPhotoS3Key: 'profile-photos/user-1/old.jpg',
        revokedAt: null,
        verifiedAt: new Date(),
      });
      await expect(service.startSession(USER, START)).resolves.toMatchObject({
        sessionId: 'session-1',
      });
    });

    it('requires a primary photo', async () => {
      const { service, repo, gateway } = setup();
      repo.primary.set(USER, null);
      await expectHttpError(
        service.startSession(USER, START),
        422,
        'NO_PRIMARY_PHOTO',
      );
      expect(repo.attempts).toHaveLength(0);
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
    });

    it('rejects a WebP primary photo by key before reading S3 or paying AWS', async () => {
      const { service, repo, gateway, s3 } = setup();
      repo.primary.set(USER, {
        id: 'p',
        s3Key: 'profile-photos/user-1/a.webp',
      });
      await expectHttpError(
        service.startSession(USER, START),
        422,
        'UNSUPPORTED_PHOTO',
      );
      expect(s3.getObjectBytes).not.toHaveBeenCalled();
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
      expect(repo.attempts).toHaveLength(0);
    });

    it.each(['UNSUPPORTED_FORMAT', 'TOO_LARGE', 'EMPTY'] as const)(
      'rejects a primary photo the S3 read reports as %s, before any AWS call',
      async (reason) => {
        const { service, repo, gateway, s3 } = setup({
          s3: makeS3({ ok: false, reason }),
        });
        await expectHttpError(
          service.startSession(USER, START),
          422,
          'UNSUPPORTED_PHOTO',
        );
        expect(s3.getObjectBytes).toHaveBeenCalledWith(PHOTO.s3Key, {
          maxBytes: 5 * 1024 * 1024,
          allowedFormats: ['jpeg', 'png'],
        });
        expect(gateway.createLivenessSession).not.toHaveBeenCalled();
        expect(repo.attempts).toHaveLength(0);
      },
    );

    it('enforces the per-member daily cap with a retryAfter', async () => {
      const { service, repo, gateway } = setup();
      const t0 = new Date(Date.now() - 60 * 60 * 1000);
      for (let i = 0; i < 3; i += 1) {
        repo.insert({
          outcome: 'FAILED_LIVENESS',
          livenessSessionId: `s${i}`,
          createdAt: t0,
        });
      }
      const body = await expectHttpError(
        service.startSession(USER, START),
        429,
        'ATTEMPT_LIMIT',
      );
      expect(body.retryAfter).toBe(
        new Date(t0.getTime() + 24 * 60 * 60 * 1000).toISOString(),
      );
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
    });

    it('does not count attempts that failed before an AWS session existed', async () => {
      const { service, repo } = setup();
      for (let i = 0; i < 3; i += 1) {
        repo.insert({ outcome: 'ERROR', livenessSessionId: null });
      }
      await expect(service.startSession(USER, START)).resolves.toBeDefined();
    });

    it('enforces the global daily cap as NOT_AVAILABLE', async () => {
      const { service, repo, gateway } = setup({
        config: { globalDailyCap: 2 },
      });
      repo.insert({
        userId: 'a',
        outcome: 'VERIFIED',
        livenessSessionId: 'x1',
      });
      repo.insert({
        userId: 'b',
        outcome: 'VERIFIED',
        livenessSessionId: 'x2',
      });
      await expectHttpError(
        service.startSession(USER, START),
        503,
        'NOT_AVAILABLE',
      );
      expect(gateway.createLivenessSession).not.toHaveBeenCalled();
    });

    it('closes the attempt as an uncounted ERROR when AWS cannot create a session', async () => {
      const { service, repo, gateway } = setup();
      gateway.createLivenessSession.mockRejectedValueOnce(
        Object.assign(new Error('boom'), { name: 'AccessDeniedException' }),
      );
      await expectHttpError(
        service.startSession(USER, START),
        503,
        'PROVIDER_UNAVAILABLE',
      );
      expect(repo.attempts[0]).toMatchObject({
        outcome: 'ERROR',
        livenessSessionId: null,
        failureReason: 'CREATE_SESSION:AccessDeniedException',
      });
      expect(gateway.issueClientCredentials).not.toHaveBeenCalled();
      await expect(
        repo.countUserAttemptsSince(USER, new Date(0)),
      ).resolves.toBe(0);
    });

    it('closes the attempt as ERROR when device credentials cannot be issued', async () => {
      const { service, repo, gateway } = setup();
      gateway.issueClientCredentials.mockRejectedValueOnce(
        Object.assign(new Error('denied'), { name: 'AccessDenied' }),
      );
      await expectHttpError(
        service.startSession(USER, START),
        503,
        'PROVIDER_UNAVAILABLE',
      );
      expect(repo.attempts[0]).toMatchObject({
        outcome: 'ERROR',
        livenessSessionId: 'session-1',
        failureReason: 'ISSUE_CREDENTIALS:AccessDenied',
      });
    });
  });

  describe('complete', () => {
    async function started() {
      const ctx = setup();
      const res = await ctx.service.startSession(USER, START);
      return { ...ctx, attemptId: res.attemptId };
    }

    it('verifies a live selfie that matches the primary photo, server-side', async () => {
      const { service, repo, gateway, s3, attemptId } = await started();

      const res = await service.complete(USER, {
        attemptId,
        clientOutcome: 'COMPLETED',
      });

      expect(res).toEqual({
        attemptId,
        status: 'VERIFIED',
        reason: null,
        canRetry: false,
        attemptsRemainingToday: 2,
      });
      expect(gateway.getLivenessSessionResults).toHaveBeenCalledWith(
        'session-1',
      );
      expect(s3.getObjectBytes).toHaveBeenLastCalledWith(PHOTO.s3Key, {
        maxBytes: 5 * 1024 * 1024,
        allowedFormats: ['jpeg', 'png'],
      });
      expect(gateway.compareFaces).toHaveBeenCalledWith(
        new Uint8Array([7, 7, 7]),
        JPEG,
      );
      expect(repo.state.get(USER)).toMatchObject({
        status: 'VERIFIED',
        matchedPhotoId: PHOTO.id,
        matchedPhotoS3Key: PHOTO.s3Key,
      });
      expect(repo.attempts[0]).toMatchObject({
        outcome: 'VERIFIED',
        livenessConfidence: 97,
        matchSimilarity: 98,
        targetFaceCount: 1,
      });
    });

    it('is idempotent: a repeated call returns the stored decision without new AWS calls', async () => {
      const { service, gateway, attemptId } = await started();
      const first = await service.complete(USER, { attemptId });
      const second = await service.complete(USER, { attemptId });
      expect(second).toEqual(first);
      expect(gateway.getLivenessSessionResults).toHaveBeenCalledTimes(1);
      expect(gateway.compareFaces).toHaveBeenCalledTimes(1);
    });

    it("never lets one member complete (or learn about) another member's attempt", async () => {
      const { service, gateway, attemptId } = await started();
      await expectHttpError(
        service.complete(OTHER_USER, { attemptId }),
        404,
        'ATTEMPT_NOT_FOUND',
      );
      expect(gateway.getLivenessSessionResults).not.toHaveBeenCalled();
    });

    it('ignores a client claim of success when AWS says liveness failed', async () => {
      const { service, repo, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockResolvedValueOnce({
        status: 'FAILED',
        confidence: 12,
      });
      const res = await service.complete(USER, {
        attemptId,
        clientOutcome: 'COMPLETED',
      });
      expect(res).toMatchObject({
        status: 'FAILED',
        reason: 'FAILED_LIVENESS',
        canRetry: true,
      });
      expect(gateway.compareFaces).not.toHaveBeenCalled();
      expect(repo.state.get(USER)?.status).not.toBe('VERIFIED');
    });

    it('fails liveness below the configured confidence threshold', async () => {
      const { service, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockResolvedValueOnce({
        status: 'SUCCEEDED',
        confidence: 89.5,
        referenceImage: new Uint8Array([1]),
      });
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        reason: 'FAILED_LIVENESS',
      });
      expect(gateway.compareFaces).not.toHaveBeenCalled();
    });

    it('fails when AWS returns no reference image', async () => {
      const { service, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockResolvedValueOnce({
        status: 'SUCCEEDED',
        confidence: 99,
      });
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        reason: 'NO_REFERENCE_IMAGE',
      });
    });

    it.each([
      [
        'another photo became primary',
        { id: 'photo-2', s3Key: 'profile-photos/user-1/b.jpg' },
      ],
      [
        'the photo was replaced',
        { id: PHOTO.id, s3Key: 'profile-photos/user-1/new.jpg' },
      ],
      ['the primary photo was removed', null],
    ])(
      'fails as PHOTO_CHANGED when %s mid-attempt',
      async (_label, primary) => {
        const { service, repo, gateway, attemptId } = await started();
        repo.primary.set(USER, primary);
        await expect(
          service.complete(USER, { attemptId }),
        ).resolves.toMatchObject({
          reason: 'PHOTO_CHANGED',
        });
        expect(gateway.compareFaces).not.toHaveBeenCalled();
      },
    );

    it('rejects an unsupported profile photo before CompareFaces', async () => {
      const ctx = await started();
      ctx.s3.getObjectBytes.mockResolvedValueOnce({
        ok: false,
        reason: 'UNSUPPORTED_FORMAT',
      });
      await expect(
        ctx.service.complete(USER, { attemptId: ctx.attemptId }),
      ).resolves.toMatchObject({
        reason: 'UNSUPPORTED_PHOTO',
      });
      expect(ctx.gateway.compareFaces).not.toHaveBeenCalled();
    });

    it.each([
      [{ faceCount: 2, bestSimilarity: 99 }, 'MULTIPLE_FACES_IN_PHOTO'],
      [{ faceCount: 0 }, 'NO_FACE_IN_PHOTO'],
      [{ faceCount: 1, bestSimilarity: 85 }, 'FAILED_MATCH'],
    ])('decides %j as %s', async (match, reason) => {
      const { service, repo, gateway, attemptId } = await started();
      gateway.compareFaces.mockResolvedValueOnce(match);
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        status: 'FAILED',
        reason,
      });
      expect(repo.state.get(USER)?.status).not.toBe('VERIFIED');
    });

    it('maps "no face found" from CompareFaces to NO_FACE_IN_PHOTO', async () => {
      const { service, gateway, attemptId } = await started();
      gateway.compareFaces.mockRejectedValueOnce(
        Object.assign(new Error('x'), { name: 'InvalidParameterException' }),
      );
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        reason: 'NO_FACE_IN_PHOTO',
      });
    });

    it('expires an attempt past the AWS session window without calling AWS', async () => {
      const { service, repo, gateway } = setup();
      const past = new Date(Date.now() - 10 * 60 * 1000);
      const attempt = repo.insert({
        livenessSessionId: 'session-old',
        createdAt: past,
        expiresAt: new Date(past.getTime() + 3 * 60 * 1000),
      });
      await expect(
        service.complete(USER, { attemptId: attempt.id }),
      ).resolves.toMatchObject({
        status: 'FAILED',
        reason: 'EXPIRED',
      });
      expect(gateway.getLivenessSessionResults).not.toHaveBeenCalled();
    });

    it('maps a session AWS no longer knows to EXPIRED', async () => {
      const { service, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockRejectedValueOnce(
        Object.assign(new Error('gone'), { name: 'SessionNotFoundException' }),
      );
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        reason: 'EXPIRED',
      });
    });

    it('answers RESULT_NOT_READY (and stays retryable) while AWS is still processing', async () => {
      const { service, repo, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockResolvedValueOnce({
        status: 'IN_PROGRESS',
      });
      await expectHttpError(
        service.complete(USER, { attemptId, clientOutcome: 'COMPLETED' }),
        409,
        'RESULT_NOT_READY',
      );
      expect(repo.attempts[0].outcome).toBe('PENDING');

      // The retry then gets the real decision.
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        status: 'VERIFIED',
      });
    });

    it('closes an unfinished session the device cancelled as CANCELLED', async () => {
      const { service, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockResolvedValueOnce({
        status: 'CREATED',
      });
      await expect(
        service.complete(USER, { attemptId, clientOutcome: 'CANCELLED' }),
      ).resolves.toMatchObject({ status: 'FAILED', reason: 'CANCELLED' });
    });

    it('reports ATTEMPT_IN_PROGRESS while a concurrent completion holds the attempt', async () => {
      const { service, repo, attemptId } = await started();
      repo.attempts[0].outcome = 'PROCESSING';
      await expectHttpError(
        service.complete(USER, { attemptId }),
        409,
        'ATTEMPT_IN_PROGRESS',
      );
    });

    it('turns an unexpected AWS failure into a recorded ERROR, not a 500', async () => {
      const { service, repo, gateway, attemptId } = await started();
      gateway.getLivenessSessionResults.mockRejectedValueOnce(
        Object.assign(new Error('x'), { name: 'ThrottlingException' }),
      );
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        status: 'FAILED',
        reason: 'ERROR',
        canRetry: true,
      });
      expect(repo.attempts[0].failureReason).toBe(
        'GET_RESULTS:ThrottlingException',
      );
    });

    it('reports canRetry=false once the member has no attempts left today', async () => {
      const { service, repo, gateway } = setup();
      repo.insert({ outcome: 'FAILED_MATCH', livenessSessionId: 'a' });
      repo.insert({ outcome: 'FAILED_MATCH', livenessSessionId: 'b' });
      const { attemptId } = await service.startSession(USER, START);
      gateway.compareFaces.mockResolvedValueOnce({
        faceCount: 1,
        bestSimilarity: 10,
      });
      await expect(
        service.complete(USER, { attemptId }),
      ).resolves.toMatchObject({
        status: 'FAILED',
        canRetry: false,
        attemptsRemainingToday: 0,
      });
    });
  });

  describe('getState', () => {
    it('reports VERIFIED while the matched photo is primary, REVOKED once it is not', async () => {
      const { service, repo } = setup();
      const verifiedAt = new Date('2026-09-20T08:00:00Z');
      repo.state.set(USER, {
        status: 'VERIFIED',
        matchedPhotoId: PHOTO.id,
        matchedPhotoS3Key: PHOTO.s3Key,
        revokedAt: null,
        verifiedAt,
      });
      await expect(service.getState(USER)).resolves.toMatchObject({
        status: 'VERIFIED',
        verifiedAt: verifiedAt.toISOString(),
        canStart: false,
        blockedReason: 'ALREADY_VERIFIED',
      });

      repo.primary.set(USER, {
        id: 'photo-2',
        s3Key: 'profile-photos/user-1/b.jpg',
      });
      await expect(service.getState(USER)).resolves.toMatchObject({
        status: 'REVOKED',
        verifiedAt: null,
        canStart: true,
        blockedReason: null,
      });
    });

    it('can start when eligible', async () => {
      const { service } = setup();
      await expect(service.getState(USER)).resolves.toEqual({
        status: 'UNVERIFIED',
        verifiedAt: null,
        canStart: true,
        blockedReason: null,
        attemptsRemainingToday: 3,
        retryAfter: null,
      });
    });

    it('explains why a member cannot start', async () => {
      const disabled = setup({ config: { enabled: false } });
      await expect(disabled.service.getState(USER)).resolves.toMatchObject({
        canStart: false,
        blockedReason: 'NOT_AVAILABLE',
      });

      const noPhoto = setup();
      noPhoto.repo.primary.set(USER, null);
      await expect(noPhoto.service.getState(USER)).resolves.toMatchObject({
        blockedReason: 'NO_PRIMARY_PHOTO',
      });

      const webp = setup();
      webp.repo.primary.set(USER, {
        id: 'p',
        s3Key: 'profile-photos/user-1/a.webp',
      });
      await expect(webp.service.getState(USER)).resolves.toMatchObject({
        blockedReason: 'UNSUPPORTED_PHOTO',
      });

      const capped = setup();
      for (let i = 0; i < 3; i += 1) {
        capped.repo.insert({
          outcome: 'FAILED_MATCH',
          livenessSessionId: `s${i}`,
        });
      }
      const state = await capped.service.getState(USER);
      expect(state).toMatchObject({
        blockedReason: 'ATTEMPT_LIMIT',
        attemptsRemainingToday: 0,
      });
      expect(state.retryAfter).not.toBeNull();
    });

    it('still reports a valid verification while the feature is switched off', async () => {
      const { service, repo } = setup({ config: { enabled: false } });
      repo.state.set(USER, {
        status: 'VERIFIED',
        matchedPhotoId: PHOTO.id,
        matchedPhotoS3Key: PHOTO.s3Key,
        revokedAt: null,
        verifiedAt: new Date(),
      });
      await expect(service.getState(USER)).resolves.toMatchObject({
        status: 'VERIFIED',
      });
    });
  });
});
