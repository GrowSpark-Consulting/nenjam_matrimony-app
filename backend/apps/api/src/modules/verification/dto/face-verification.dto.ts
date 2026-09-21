import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  Equals,
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
} from 'class-validator';
import type { FaceVerificationDisplayStatus } from '../domain/face-verification-state';

// ─── Requests ──────────────────────────────────────────────────────────────

/** Body for POST /verification/face/sessions. */
export class StartFaceSessionDto {
  @ApiProperty({
    description:
      'Explicit consent to the liveness video check and face comparison. Must be true.',
    example: true,
  })
  @IsBoolean()
  @Equals(true, { message: 'consent must be true to start face verification' })
  consent!: boolean;
}

export const CLIENT_LIVENESS_OUTCOMES = [
  'COMPLETED',
  'CANCELLED',
  'ERROR',
] as const;
export type ClientLivenessOutcome = (typeof CLIENT_LIVENESS_OUTCOMES)[number];

/**
 * Body for POST /verification/face/complete. `clientOutcome`/`clientErrorCode`
 * are what the device observed — stored for audit and used only to close an
 * attempt AWS still reports as unfinished. They never decide verification.
 */
export class CompleteFaceSessionDto {
  @ApiProperty({
    description: 'The attemptId returned when the session started.',
  })
  @IsUUID()
  attemptId!: string;

  @ApiPropertyOptional({ enum: CLIENT_LIVENESS_OUTCOMES })
  @IsOptional()
  @IsIn(CLIENT_LIVENESS_OUTCOMES)
  clientOutcome?: ClientLivenessOutcome;

  @ApiPropertyOptional({ example: 'CAMERA_PERMISSION_DENIED' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  @Matches(/^[A-Za-z0-9_.:-]+$/, {
    message: 'clientErrorCode may only contain letters, digits and _ . : -',
  })
  clientErrorCode?: string;
}

// ─── Responses ─────────────────────────────────────────────────────────────

export const FACE_BLOCKED_REASONS = [
  'NOT_AVAILABLE',
  'ALREADY_VERIFIED',
  'NO_PRIMARY_PHOTO',
  'UNSUPPORTED_PHOTO',
  'ATTEMPT_LIMIT',
] as const;
export type FaceBlockedReason = (typeof FACE_BLOCKED_REASONS)[number];

/** GET /verification/face — the caller's own current state. */
export class FaceVerificationStateDto {
  @ApiProperty({ enum: ['UNVERIFIED', 'VERIFIED', 'REVOKED'] })
  status!: FaceVerificationDisplayStatus;

  @ApiProperty({ type: String, nullable: true })
  verifiedAt!: string | null;

  @ApiProperty()
  canStart!: boolean;

  @ApiProperty({ enum: FACE_BLOCKED_REASONS, nullable: true })
  blockedReason!: FaceBlockedReason | null;

  @ApiProperty()
  attemptsRemainingToday!: number;

  @ApiProperty({ type: String, nullable: true })
  retryAfter!: string | null;
}

export class TemporaryCredentialsDto {
  @ApiProperty() accessKeyId!: string;
  @ApiProperty() secretAccessKey!: string;
  @ApiProperty() sessionToken!: string;
  @ApiProperty({ description: 'ISO-8601 expiry of these credentials.' })
  expiration!: string;
}

/**
 * POST /verification/face/sessions — everything the device needs to run the
 * native liveness check, and nothing else. The credentials are STS temporary
 * credentials limited to rekognition:StartFaceLivenessSession.
 */
export class StartFaceSessionResponseDto {
  @ApiProperty() attemptId!: string;
  @ApiProperty() sessionId!: string;
  @ApiProperty({ example: 'ap-south-1' }) region!: string;
  @ApiProperty({
    description: 'ISO-8601 instant after which the session is dead.',
  })
  expiresAt!: string;
  @ApiProperty({ type: TemporaryCredentialsDto })
  credentials!: TemporaryCredentialsDto;
}

/**
 * POST /verification/face/complete — the backend's final decision. Scores are
 * deliberately absent: exposing confidence/similarity would help tune spoofs.
 */
export class CompleteFaceSessionResponseDto {
  @ApiProperty() attemptId!: string;

  @ApiProperty({ enum: ['VERIFIED', 'FAILED'] })
  status!: 'VERIFIED' | 'FAILED';

  @ApiProperty({
    type: String,
    nullable: true,
    description:
      'Why it failed: FAILED_LIVENESS, FAILED_MATCH, NO_FACE_IN_PHOTO, MULTIPLE_FACES_IN_PHOTO, UNSUPPORTED_PHOTO, NO_REFERENCE_IMAGE, PHOTO_CHANGED, EXPIRED, CANCELLED or ERROR.',
  })
  reason!: string | null;

  @ApiProperty() canRetry!: boolean;
  @ApiProperty() attemptsRemainingToday!: number;
}
