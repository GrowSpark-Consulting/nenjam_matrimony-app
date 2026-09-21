import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { S3Service } from '@app/storage';
import type {
  FaceVerificationAttempt,
  FaceVerificationOutcome,
} from '../../../../../../libs/database/generated/client';
import {
  COMPARE_FACES_FORMATS,
  COMPARE_FACES_MAX_BYTES,
  FaceVerificationErrorCode,
  LIVENESS_SESSION_LIFETIME_MS,
  PROCESSING_GRACE_MS,
  USER_ATTEMPT_WINDOW_MS,
  faceVerificationError,
} from '../domain/face-verification.constants';
import {
  evaluateLiveness,
  evaluateMatch,
} from '../domain/face-verification-decision';
import {
  faceVerificationDisplayStatus,
  isFaceVerified,
  type PrimaryPhotoRef,
} from '../domain/face-verification-state';
import {
  FACE_LIVENESS_GATEWAY,
  awsErrorName,
  type CompareFacesResult,
  type FaceLivenessGateway,
  type LivenessSessionResult,
  type TemporaryAwsCredentials,
} from '../gateways/face-liveness.gateway';
import {
  FaceVerificationRepository,
  IN_FLIGHT_OUTCOMES,
  type FinalizeAttemptParams,
} from '../repositories/face-verification.repository';
import type {
  CompleteFaceSessionDto,
  CompleteFaceSessionResponseDto,
  FaceVerificationStateDto,
  StartFaceSessionDto,
  StartFaceSessionResponseDto,
} from '../dto/face-verification.dto';

/** Profile-photo keys whose extension CompareFaces can never accept. */
const UNSUPPORTED_PHOTO_EXTENSION = /\.(webp|gif|heic|heif|bmp|tiff?)$/i;

/**
 * Face verification = AWS Face Liveness (a live person is in front of the
 * camera) + CompareFaces (that person is the one in the member's current
 * primary profile photo).
 *
 * The device only ever runs the capture. Every decision is made here, from
 * AWS results the backend fetches itself and thresholds it configures; the
 * client's own report is stored for audit and never trusted. No biometric
 * artefact is stored: the liveness reference image lives in memory for the
 * one CompareFaces call and is then dropped.
 */
@Injectable()
export class FaceVerificationService {
  private readonly logger = new Logger(FaceVerificationService.name);

  constructor(
    private readonly config: AppConfigService,
    private readonly repository: FaceVerificationRepository,
    private readonly s3: S3Service,
    @Inject(FACE_LIVENESS_GATEWAY)
    private readonly gateway: FaceLivenessGateway,
  ) {}

  private get settings() {
    return this.config.faceVerification;
  }

  /** Enabled AND every dependency configured — the only state that may spend. */
  private isAvailable(): boolean {
    return (
      this.settings.enabled &&
      this.gateway.isConfigured() &&
      this.s3.isConfigured()
    );
  }

  private assertAvailable(): void {
    if (!this.isAvailable()) {
      throw faceVerificationError(
        HttpStatus.SERVICE_UNAVAILABLE,
        FaceVerificationErrorCode.NOT_AVAILABLE,
        'Face verification is not available right now.',
      );
    }
  }

  // ─── GET /verification/face ────────────────────────────────────────────

  async getState(userId: string): Promise<FaceVerificationStateDto> {
    const now = new Date();
    const available = this.isAvailable();
    if (available) {
      await this.repository.expireStaleAttempts(
        userId,
        now,
        PROCESSING_GRACE_MS,
      );
    }

    const [stored, primary] = await Promise.all([
      this.repository.findState(userId),
      this.repository.findPrimaryPhoto(userId),
    ]);
    const status = faceVerificationDisplayStatus(stored, primary);
    const base = {
      status,
      verifiedAt:
        status === 'VERIFIED' && stored?.verifiedAt
          ? stored.verifiedAt.toISOString()
          : null,
    };

    if (!available) {
      return {
        ...base,
        canStart: false,
        blockedReason: 'NOT_AVAILABLE',
        attemptsRemainingToday: 0,
        retryAfter: null,
      };
    }

    const quota = await this.userQuota(userId, now);
    const blocked = (
      blockedReason: FaceVerificationStateDto['blockedReason'],
    ): FaceVerificationStateDto => ({
      ...base,
      canStart: false,
      blockedReason,
      attemptsRemainingToday: quota.remaining,
      retryAfter: quota.retryAfter,
    });

    if (status === 'VERIFIED') return blocked('ALREADY_VERIFIED');
    if (!primary) return blocked('NO_PRIMARY_PHOTO');
    // Cheap hint only; the authoritative check reads the real bytes on start.
    if (UNSUPPORTED_PHOTO_EXTENSION.test(primary.s3Key)) {
      return blocked('UNSUPPORTED_PHOTO');
    }
    if (quota.remaining <= 0) return blocked('ATTEMPT_LIMIT');
    if (await this.globalCapReached(now)) return blocked('NOT_AVAILABLE');

    return {
      ...base,
      canStart: true,
      blockedReason: null,
      attemptsRemainingToday: quota.remaining,
      retryAfter: null,
    };
  }

  // ─── POST /verification/face/sessions ──────────────────────────────────

  async startSession(
    userId: string,
    dto: StartFaceSessionDto,
  ): Promise<StartFaceSessionResponseDto> {
    // The DTO already requires consent === true; re-checked here so no other
    // caller can ever start a biometric check without it. Recorded as the
    // attempt's consentAt.
    if (dto.consent !== true) {
      throw new BadRequestException(
        'consent must be true to start face verification',
      );
    }
    this.assertAvailable();
    const now = new Date();
    await this.repository.expireStaleAttempts(userId, now, PROCESSING_GRACE_MS);

    const [stored, primary] = await Promise.all([
      this.repository.findState(userId),
      this.repository.findPrimaryPhoto(userId),
    ]);
    if (isFaceVerified(stored, primary)) {
      throw faceVerificationError(
        HttpStatus.CONFLICT,
        FaceVerificationErrorCode.ALREADY_VERIFIED,
        'Your profile is already face verified.',
      );
    }
    if (!primary) throw this.noPrimaryPhoto();

    // Cheap pre-check so a member at their cap cannot make us read S3 again
    // and again. reserveAttempt below re-checks under a lock.
    const quota = await this.userQuota(userId, now);
    if (quota.remaining <= 0) throw this.attemptLimit(quota.retryAfter);

    // Validate the photo BEFORE anything is paid for.
    await this.readComparablePhoto(primary);

    const reservation = await this.repository.reserveAttempt({
      userId,
      photo: primary,
      now,
      expiresAt: new Date(now.getTime() + LIVENESS_SESSION_LIFETIME_MS),
      userWindowStart: new Date(now.getTime() - USER_ATTEMPT_WINDOW_MS),
      globalWindowStart: startOfUtcDay(now),
      maxAttemptsPerUser: this.settings.maxAttemptsPerDay,
      globalDailyCap: this.settings.globalDailyCap,
      livenessThreshold: this.settings.minLivenessConfidence,
      similarityThreshold: this.settings.minMatchSimilarity,
    });
    if (reservation.kind === 'USER_LIMIT') {
      throw this.attemptLimit(retryAfterFrom(reservation.oldestCountedAt));
    }
    if (reservation.kind === 'GLOBAL_LIMIT') {
      this.logger.warn(
        `Face verification global daily cap (${this.settings.globalDailyCap}) reached; refusing new sessions until 00:00 UTC.`,
      );
      throw faceVerificationError(
        HttpStatus.SERVICE_UNAVAILABLE,
        FaceVerificationErrorCode.NOT_AVAILABLE,
        'Face verification is not available right now. Please try again later.',
      );
    }
    const attempt = reservation.attempt;

    let sessionId: string;
    try {
      sessionId = await this.gateway.createLivenessSession(attempt.id);
    } catch (error) {
      await this.finalize({
        attemptId: attempt.id,
        userId,
        outcome: 'ERROR',
        now: new Date(),
        failureReason: `CREATE_SESSION:${awsErrorName(error)}`,
      });
      throw this.providerUnavailable(
        'create liveness session',
        attempt.id,
        error,
      );
    }
    await this.repository.setLivenessSession(attempt.id, sessionId);

    let credentials: TemporaryAwsCredentials;
    try {
      credentials = await this.gateway.issueClientCredentials(
        `nenjam-fv-${attempt.id}`,
      );
    } catch (error) {
      await this.finalize({
        attemptId: attempt.id,
        userId,
        outcome: 'ERROR',
        now: new Date(),
        failureReason: `ISSUE_CREDENTIALS:${awsErrorName(error)}`,
      });
      throw this.providerUnavailable(
        'issue client credentials',
        attempt.id,
        error,
      );
    }

    this.logger.log(
      `Face verification attempt ${attempt.id} started for user ${userId}.`,
    );
    return {
      attemptId: attempt.id,
      sessionId,
      region: this.gateway.region(),
      expiresAt: attempt.expiresAt.toISOString(),
      credentials: {
        accessKeyId: credentials.accessKeyId,
        secretAccessKey: credentials.secretAccessKey,
        sessionToken: credentials.sessionToken,
        expiration: credentials.expiration.toISOString(),
      },
    };
  }

  // ─── POST /verification/face/complete ──────────────────────────────────

  async complete(
    userId: string,
    dto: CompleteFaceSessionDto,
  ): Promise<CompleteFaceSessionResponseDto> {
    this.assertAvailable();
    const now = new Date();

    const attempt = await this.repository.findOwnedAttempt(
      dto.attemptId,
      userId,
    );
    if (!attempt) {
      // Same answer for "does not exist" and "belongs to someone else".
      throw faceVerificationError(
        HttpStatus.NOT_FOUND,
        FaceVerificationErrorCode.ATTEMPT_NOT_FOUND,
        'Verification attempt not found.',
      );
    }

    // Idempotent: an already-decided attempt just reports its decision.
    if (!IN_FLIGHT_OUTCOMES.includes(attempt.outcome)) {
      return this.resultOf(userId, attempt, now);
    }

    if (attempt.outcome === 'PROCESSING') {
      const abandoned =
        now.getTime() >= attempt.expiresAt.getTime() + PROCESSING_GRACE_MS;
      if (!abandoned) throw this.attemptInProgress();
      return this.finalizeAndReport(userId, now, {
        attemptId: attempt.id,
        outcome: 'ERROR',
        failureReason: 'PROCESSING_TIMEOUT',
      });
    }

    // PENDING from here on.
    if (now.getTime() >= attempt.expiresAt.getTime()) {
      return this.finalizeAndReport(userId, now, {
        attemptId: attempt.id,
        outcome: 'EXPIRED',
        failureReason: 'NOT_COMPLETED_IN_TIME',
      });
    }
    if (!attempt.livenessSessionId) {
      return this.finalizeAndReport(userId, now, {
        attemptId: attempt.id,
        outcome: 'ERROR',
        failureReason: 'NO_LIVENESS_SESSION',
      });
    }

    const claimed = await this.repository.claimForProcessing(
      attempt.id,
      userId,
      now,
      { outcome: dto.clientOutcome, errorCode: dto.clientErrorCode },
    );
    if (!claimed) {
      // Lost a race with a concurrent /complete: report whatever it decided.
      const current = await this.repository.findOwnedAttempt(
        attempt.id,
        userId,
      );
      if (current && !IN_FLIGHT_OUTCOMES.includes(current.outcome)) {
        return this.resultOf(userId, current, now);
      }
      throw this.attemptInProgress();
    }

    try {
      return await this.decide(userId, attempt, attempt.livenessSessionId, dto);
    } catch (error) {
      // Deliberate HTTP answers (e.g. RESULT_NOT_READY) pass straight through.
      if (error instanceof HttpException) throw error;
      this.logger.error(
        `Face verification attempt ${attempt.id} failed unexpectedly: ${(error as Error).message}`,
      );
      return this.finalizeAndReport(userId, new Date(), {
        attemptId: attempt.id,
        outcome: 'ERROR',
        failureReason: `UNEXPECTED:${awsErrorName(error)}`,
      });
    }
  }

  /** Runs the AWS checks for a claimed attempt and records the decision. */
  private async decide(
    userId: string,
    attempt: FaceVerificationAttempt,
    sessionId: string,
    dto: CompleteFaceSessionDto,
  ): Promise<CompleteFaceSessionResponseDto> {
    const report = (
      outcome: FaceVerificationOutcome,
      extra: Partial<FinalizeAttemptParams> = {},
    ) =>
      this.finalizeAndReport(userId, new Date(), {
        attemptId: attempt.id,
        outcome,
        ...extra,
      });

    let liveness: LivenessSessionResult;
    try {
      liveness = await this.gateway.getLivenessSessionResults(sessionId);
    } catch (error) {
      const name = awsErrorName(error);
      return report(name === 'SessionNotFoundException' ? 'EXPIRED' : 'ERROR', {
        failureReason: `GET_RESULTS:${name}`,
      });
    }

    // AWS has not finished (or the capture never streamed).
    if (liveness.status === 'CREATED' || liveness.status === 'IN_PROGRESS') {
      if (dto.clientOutcome === 'CANCELLED' || dto.clientOutcome === 'ERROR') {
        return report(
          dto.clientOutcome === 'CANCELLED' ? 'CANCELLED' : 'ERROR',
          {
            livenessStatus: liveness.status,
            failureReason: `CLIENT_${dto.clientOutcome}`,
          },
        );
      }
      await this.repository.releaseClaim(attempt.id, userId);
      throw faceVerificationError(
        HttpStatus.CONFLICT,
        FaceVerificationErrorCode.RESULT_NOT_READY,
        'The liveness result is not ready yet. Please retry shortly.',
      );
    }

    const livenessFields = {
      livenessStatus: liveness.status,
      livenessConfidence: liveness.confidence,
    };
    const livenessOutcome = evaluateLiveness(
      {
        status: liveness.status,
        confidence: liveness.confidence,
        hasReferenceImage: (liveness.referenceImage?.length ?? 0) > 0,
      },
      Number(attempt.livenessThreshold),
    );
    if (livenessOutcome) return report(livenessOutcome, livenessFields);

    // Compare only against the exact photo the attempt was started with, and
    // only while it is still the member's primary photo.
    const primary = await this.repository.findPrimaryPhoto(userId);
    if (
      !primary ||
      !attempt.comparedPhotoId ||
      primary.id !== attempt.comparedPhotoId ||
      primary.s3Key !== attempt.comparedPhotoS3Key
    ) {
      return report('PHOTO_CHANGED', livenessFields);
    }

    const photo = await this.s3.getObjectBytes(primary.s3Key, {
      maxBytes: COMPARE_FACES_MAX_BYTES,
      allowedFormats: COMPARE_FACES_FORMATS,
    });
    if (!photo.ok) {
      return report(
        photo.reason === 'NOT_FOUND' ? 'PHOTO_CHANGED' : 'UNSUPPORTED_PHOTO',
        {
          ...livenessFields,
          failureReason: `PHOTO_${photo.reason}`,
        },
      );
    }

    let match: CompareFacesResult;
    try {
      match = await this.gateway.compareFaces(
        liveness.referenceImage as Uint8Array,
        photo.bytes,
      );
    } catch (error) {
      const name = awsErrorName(error);
      // InvalidParameterException = no face found in an image; the liveness
      // reference always has one, so it is the profile photo.
      const outcome: FaceVerificationOutcome =
        name === 'InvalidParameterException'
          ? 'NO_FACE_IN_PHOTO'
          : name === 'InvalidImageFormatException' ||
              name === 'ImageTooLargeException'
            ? 'UNSUPPORTED_PHOTO'
            : 'ERROR';
      return report(outcome, {
        ...livenessFields,
        failureReason: `COMPARE:${name}`,
      });
    }

    const outcome = evaluateMatch(match, Number(attempt.similarityThreshold));
    return report(outcome, {
      ...livenessFields,
      matchSimilarity: match.bestSimilarity,
      targetFaceCount: match.faceCount,
      matchedPhoto: outcome === 'VERIFIED' ? primary : undefined,
    });
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  private async finalizeAndReport(
    userId: string,
    now: Date,
    params: Omit<FinalizeAttemptParams, 'userId' | 'now'>,
  ): Promise<CompleteFaceSessionResponseDto> {
    const attempt = await this.finalize({ ...params, userId, now });
    if (attempt.outcome === 'VERIFIED') {
      this.logger.log(`User ${userId} face verified (attempt ${attempt.id}).`);
    } else {
      this.logger.log(
        `Face verification attempt ${attempt.id} ended: ${attempt.outcome}.`,
      );
    }
    return this.resultOf(userId, attempt, now);
  }

  private finalize(
    params: FinalizeAttemptParams,
  ): Promise<FaceVerificationAttempt> {
    return this.repository.finalizeAttempt(params);
  }

  private async resultOf(
    userId: string,
    attempt: FaceVerificationAttempt,
    now: Date,
  ): Promise<CompleteFaceSessionResponseDto> {
    const verified = attempt.outcome === 'VERIFIED';
    const { remaining } = await this.userQuota(userId, now);
    return {
      attemptId: attempt.id,
      status: verified ? 'VERIFIED' : 'FAILED',
      reason: verified ? null : attempt.outcome,
      canRetry: !verified && remaining > 0,
      attemptsRemainingToday: remaining,
    };
  }

  private async userQuota(
    userId: string,
    now: Date,
  ): Promise<{ remaining: number; retryAfter: string | null }> {
    const since = new Date(now.getTime() - USER_ATTEMPT_WINDOW_MS);
    const used = await this.repository.countUserAttemptsSince(userId, since);
    const remaining = Math.max(0, this.settings.maxAttemptsPerDay - used);
    if (remaining > 0) return { remaining, retryAfter: null };
    const oldest = await this.repository.oldestUserAttemptSince(userId, since);
    return { remaining, retryAfter: retryAfterFrom(oldest) };
  }

  private async globalCapReached(now: Date): Promise<boolean> {
    const used = await this.repository.countGlobalAttemptsSince(
      startOfUtcDay(now),
    );
    return used >= this.settings.globalDailyCap;
  }

  /** Throws unless the photo is a readable JPEG/PNG within Rekognition's limit. */
  private async readComparablePhoto(photo: PrimaryPhotoRef): Promise<void> {
    if (UNSUPPORTED_PHOTO_EXTENSION.test(photo.s3Key))
      throw this.unsupportedPhoto();
    const result = await this.s3.getObjectBytes(photo.s3Key, {
      maxBytes: COMPARE_FACES_MAX_BYTES,
      allowedFormats: COMPARE_FACES_FORMATS,
    });
    if (result.ok) return;
    if (result.reason === 'NOT_FOUND') throw this.noPrimaryPhoto();
    throw this.unsupportedPhoto();
  }

  private noPrimaryPhoto() {
    return faceVerificationError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      FaceVerificationErrorCode.NO_PRIMARY_PHOTO,
      'Add a clear photo of your face as your main profile photo first.',
    );
  }

  private unsupportedPhoto() {
    return faceVerificationError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      FaceVerificationErrorCode.UNSUPPORTED_PHOTO,
      'Your main profile photo must be a JPEG or PNG under 5 MB to be verified.',
    );
  }

  private attemptLimit(retryAfter: string | null) {
    return faceVerificationError(
      HttpStatus.TOO_MANY_REQUESTS,
      FaceVerificationErrorCode.ATTEMPT_LIMIT,
      "You've reached today's face verification limit.",
      { retryAfter },
    );
  }

  private attemptInProgress() {
    return faceVerificationError(
      HttpStatus.CONFLICT,
      FaceVerificationErrorCode.ATTEMPT_IN_PROGRESS,
      'This verification is already being processed. Please retry shortly.',
    );
  }

  private providerUnavailable(step: string, attemptId: string, error: unknown) {
    // Error name only — never the message, which can echo request details.
    this.logger.error(
      `Face verification attempt ${attemptId}: failed to ${step} (${awsErrorName(error)}).`,
    );
    return faceVerificationError(
      HttpStatus.SERVICE_UNAVAILABLE,
      FaceVerificationErrorCode.PROVIDER_UNAVAILABLE,
      'Face verification is temporarily unavailable. Please try again.',
    );
  }
}

function startOfUtcDay(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}

function retryAfterFrom(oldestCountedAt: Date | null): string | null {
  return oldestCountedAt
    ? new Date(oldestCountedAt.getTime() + USER_ATTEMPT_WINDOW_MS).toISOString()
    : null;
}
