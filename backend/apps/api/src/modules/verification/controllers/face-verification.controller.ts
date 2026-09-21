import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { UPLOAD_LIMIT, WRITE_LIMIT } from '../../../throttling';
import { FaceVerificationService } from '../services/face-verification.service';
import {
  CompleteFaceSessionDto,
  CompleteFaceSessionResponseDto,
  FaceVerificationStateDto,
  StartFaceSessionDto,
  StartFaceSessionResponseDto,
} from '../dto/face-verification.dto';

// Face verification (AWS Face Liveness + CompareFaces). Every route is scoped
// to the authenticated member: `userId` is the internal id FirebaseAuthGuard
// resolved from the verified Firebase token, so a caller can only ever start,
// complete or read their OWN verification. The device never decides the
// outcome — /complete makes the decision server-side from AWS results.
@ApiTags('verification')
@ApiBearerAuth()
@Controller('verification/face')
@UseGuards(FirebaseAuthGuard)
export class FaceVerificationController {
  constructor(private readonly faceVerification: FaceVerificationService) {}

  @ApiOperation({ summary: "The caller's face verification state." })
  @Get()
  getState(
    @CurrentUser('id') userId: string,
  ): Promise<FaceVerificationStateDto> {
    return this.faceVerification.getState(userId);
  }

  // Each call can create a paid AWS liveness session, so it gets the
  // tightest tier; the per-member and global caps sit behind this.
  @ApiOperation({
    summary:
      'Start a liveness attempt: returns the session and short-lived device credentials.',
  })
  @Throttle(UPLOAD_LIMIT)
  @Post('sessions')
  @HttpCode(HttpStatus.CREATED)
  startSession(
    @CurrentUser('id') userId: string,
    @Body() dto: StartFaceSessionDto,
  ): Promise<StartFaceSessionResponseDto> {
    return this.faceVerification.startSession(userId, dto);
  }

  // Idempotent and retried by the client while the result is not ready, so
  // the write tier rather than the upload tier.
  @ApiOperation({
    summary:
      'Complete an attempt: the backend fetches AWS results and decides verification.',
  })
  @Throttle(WRITE_LIMIT)
  @Post('complete')
  @HttpCode(HttpStatus.OK)
  complete(
    @CurrentUser('id') userId: string,
    @Body() dto: CompleteFaceSessionDto,
  ): Promise<CompleteFaceSessionResponseDto> {
    return this.faceVerification.complete(userId, dto);
  }
}
