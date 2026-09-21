import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  FaceVerificationAttempt,
  FaceVerificationOutcome,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import type {
  PrimaryPhotoRef,
  StoredFaceVerification,
} from '../domain/face-verification-state';

/** Outcomes that end an attempt. PENDING/PROCESSING are the only live ones. */
export const IN_FLIGHT_OUTCOMES: readonly FaceVerificationOutcome[] = [
  'PENDING',
  'PROCESSING',
];

/**
 * Which attempts count toward the per-member and global caps: every attempt
 * EXCEPT one that failed before an AWS session existed (nothing was paid for,
 * so the member should not lose a try to our own/AWS's outage).
 */
const COUNTED_ATTEMPT: Prisma.FaceVerificationAttemptWhereInput = {
  NOT: { AND: [{ outcome: 'ERROR' }, { livenessSessionId: null }] },
};

export interface StoredStateRow extends StoredFaceVerification {
  verifiedAt: Date | null;
}

export interface ReserveAttemptParams {
  userId: string;
  photo: PrimaryPhotoRef;
  now: Date;
  expiresAt: Date;
  userWindowStart: Date;
  globalWindowStart: Date;
  maxAttemptsPerUser: number;
  globalDailyCap: number;
  livenessThreshold: number;
  similarityThreshold: number;
}

export type ReserveAttemptResult =
  | { kind: 'CREATED'; attempt: FaceVerificationAttempt }
  | { kind: 'USER_LIMIT'; oldestCountedAt: Date | null }
  | { kind: 'GLOBAL_LIMIT' };

export interface FinalizeAttemptParams {
  attemptId: string;
  userId: string;
  outcome: FaceVerificationOutcome;
  now: Date;
  livenessStatus?: string;
  livenessConfidence?: number;
  matchSimilarity?: number;
  targetFaceCount?: number;
  failureReason?: string;
  /** Present only when outcome is VERIFIED: the photo that was matched. */
  matchedPhoto?: PrimaryPhotoRef;
}

/**
 * All face-verification persistence. Every read of an attempt is scoped by
 * `userId` — the internal id FirebaseAuthGuard resolved from the verified
 * token — so one member can never read or complete another member's attempt.
 */
@Injectable()
export class FaceVerificationRepository {
  constructor(private readonly prisma: PrismaService) {}

  findPrimaryPhoto(userId: string): Promise<PrimaryPhotoRef | null> {
    return this.prisma.profilePhoto.findFirst({
      where: { userId, isPrimary: true },
      select: { id: true, s3Key: true },
    });
  }

  findState(userId: string): Promise<StoredStateRow | null> {
    return this.prisma.faceVerification.findUnique({
      where: { userId },
      select: {
        status: true,
        matchedPhotoId: true,
        matchedPhotoS3Key: true,
        revokedAt: true,
        verifiedAt: true,
      },
    });
  }

  findOwnedAttempt(
    attemptId: string,
    userId: string,
  ): Promise<FaceVerificationAttempt | null> {
    return this.prisma.faceVerificationAttempt.findFirst({
      where: { id: attemptId, userId },
    });
  }

  /**
   * Lazily closes this member's attempts that can no longer succeed:
   * PENDING past the AWS session window -> EXPIRED, and PROCESSING stuck past
   * the window plus a grace period (a request died mid-flight) -> ERROR.
   * Replaces a scheduler: runs on the member's next read or start.
   */
  async expireStaleAttempts(
    userId: string,
    now: Date,
    processingGraceMs: number,
  ): Promise<void> {
    await this.prisma.faceVerificationAttempt.updateMany({
      where: { userId, outcome: 'PENDING', expiresAt: { lte: now } },
      data: {
        outcome: 'EXPIRED',
        failureReason: 'NOT_COMPLETED_IN_TIME',
        completedAt: now,
      },
    });
    await this.prisma.faceVerificationAttempt.updateMany({
      where: {
        userId,
        outcome: 'PROCESSING',
        expiresAt: { lte: new Date(now.getTime() - processingGraceMs) },
      },
      data: {
        outcome: 'ERROR',
        failureReason: 'PROCESSING_TIMEOUT',
        completedAt: now,
      },
    });
  }

  countUserAttemptsSince(userId: string, since: Date): Promise<number> {
    return this.prisma.faceVerificationAttempt.count({
      where: { userId, createdAt: { gte: since }, ...COUNTED_ATTEMPT },
    });
  }

  async oldestUserAttemptSince(
    userId: string,
    since: Date,
  ): Promise<Date | null> {
    const row = await this.prisma.faceVerificationAttempt.findFirst({
      where: { userId, createdAt: { gte: since }, ...COUNTED_ATTEMPT },
      orderBy: { createdAt: 'asc' },
      select: { createdAt: true },
    });
    return row?.createdAt ?? null;
  }

  countGlobalAttemptsSince(since: Date): Promise<number> {
    return this.prisma.faceVerificationAttempt.count({
      where: { createdAt: { gte: since }, ...COUNTED_ATTEMPT },
    });
  }

  /**
   * Atomically checks both caps and creates the attempt.
   *
   * The member's FaceVerification row is upserted and then locked
   * (SELECT ... FOR UPDATE) for the transaction, so two concurrent start
   * requests from one member serialise here instead of both passing the count
   * and both creating a paid AWS session. The global cap is a spend breaker,
   * not a hard quota, so it is not serialised across members.
   *
   * Any older in-flight PENDING attempt is closed as superseded — a member has
   * at most one live session at a time.
   */
  reserveAttempt(params: ReserveAttemptParams): Promise<ReserveAttemptResult> {
    const { userId, now } = params;
    return this.prisma.$transaction(async (tx) => {
      await tx.faceVerification.upsert({
        where: { userId },
        create: { userId },
        update: {},
      });
      await tx.$queryRaw`SELECT id FROM face_verifications WHERE user_id = ${userId} FOR UPDATE`;

      await tx.faceVerificationAttempt.updateMany({
        where: { userId, outcome: 'PENDING' },
        data: {
          outcome: 'EXPIRED',
          failureReason: 'SUPERSEDED',
          completedAt: now,
        },
      });

      const userCount = await tx.faceVerificationAttempt.count({
        where: {
          userId,
          createdAt: { gte: params.userWindowStart },
          ...COUNTED_ATTEMPT,
        },
      });
      if (userCount >= params.maxAttemptsPerUser) {
        const oldest = await tx.faceVerificationAttempt.findFirst({
          where: {
            userId,
            createdAt: { gte: params.userWindowStart },
            ...COUNTED_ATTEMPT,
          },
          orderBy: { createdAt: 'asc' },
          select: { createdAt: true },
        });
        return {
          kind: 'USER_LIMIT',
          oldestCountedAt: oldest?.createdAt ?? null,
        };
      }

      const globalCount = await tx.faceVerificationAttempt.count({
        where: {
          createdAt: { gte: params.globalWindowStart },
          ...COUNTED_ATTEMPT,
        },
      });
      if (globalCount >= params.globalDailyCap) {
        return { kind: 'GLOBAL_LIMIT' };
      }

      const attempt = await tx.faceVerificationAttempt.create({
        data: {
          userId,
          provider: 'AWS_REKOGNITION',
          comparedPhotoId: params.photo.id,
          comparedPhotoS3Key: params.photo.s3Key,
          livenessThreshold: params.livenessThreshold,
          similarityThreshold: params.similarityThreshold,
          consentAt: now,
          expiresAt: params.expiresAt,
        },
      });
      return { kind: 'CREATED', attempt };
    });
  }

  async setLivenessSession(
    attemptId: string,
    sessionId: string,
  ): Promise<void> {
    await this.prisma.faceVerificationAttempt.update({
      where: { id: attemptId },
      data: { livenessSessionId: sessionId },
    });
  }

  /**
   * Claims a PENDING attempt for processing. The conditional update is the
   * idempotency guard: of two concurrent /complete calls exactly one gets
   * `true`; the other sees PROCESSING (or the final outcome) on re-read.
   */
  async claimForProcessing(
    attemptId: string,
    userId: string,
    now: Date,
    client: { outcome?: string; errorCode?: string },
  ): Promise<boolean> {
    const { count } = await this.prisma.faceVerificationAttempt.updateMany({
      where: { id: attemptId, userId, outcome: 'PENDING' },
      data: {
        outcome: 'PROCESSING',
        processingStartedAt: now,
        clientOutcome: client.outcome ?? null,
        clientErrorCode: client.errorCode ?? null,
      },
    });
    return count === 1;
  }

  /** Hands a claimed attempt back (AWS has no result yet; client may retry). */
  async releaseClaim(attemptId: string, userId: string): Promise<void> {
    await this.prisma.faceVerificationAttempt.updateMany({
      where: { id: attemptId, userId, outcome: 'PROCESSING' },
      data: { outcome: 'PENDING', processingStartedAt: null },
    });
  }

  /**
   * Records an attempt's terminal outcome and, in the same transaction, the
   * member's current state. Only a VERIFIED outcome changes the stored
   * verification; a failure never downgrades an existing one (it only moves
   * `latestAttemptId`), because starting is refused while verified and a
   * stale verification is already invalid by derivation.
   */
  finalizeAttempt(
    params: FinalizeAttemptParams,
  ): Promise<FaceVerificationAttempt> {
    const { attemptId, userId, outcome, now } = params;
    return this.prisma.$transaction(async (tx) => {
      const attempt = await tx.faceVerificationAttempt.update({
        where: { id: attemptId },
        data: {
          outcome,
          livenessStatus: params.livenessStatus,
          livenessConfidence: params.livenessConfidence,
          matchSimilarity: params.matchSimilarity,
          targetFaceCount: params.targetFaceCount,
          failureReason: params.failureReason,
          completedAt: now,
        },
      });

      if (outcome === 'VERIFIED' && params.matchedPhoto) {
        const verified = {
          status: 'VERIFIED' as const,
          provider: 'AWS_REKOGNITION' as const,
          isVerified: true,
          confidenceScore: params.livenessConfidence,
          matchSimilarity: params.matchSimilarity,
          matchedPhotoId: params.matchedPhoto.id,
          matchedPhotoS3Key: params.matchedPhoto.s3Key,
          latestAttemptId: attemptId,
          verifiedAt: now,
          revokedAt: null,
          revocationReason: null,
        };
        await tx.faceVerification.upsert({
          where: { userId },
          create: { userId, ...verified },
          update: verified,
        });
      } else {
        await tx.faceVerification.upsert({
          where: { userId },
          create: { userId, latestAttemptId: attemptId },
          update: { latestAttemptId: attemptId },
        });
      }
      return attempt;
    });
  }
}
