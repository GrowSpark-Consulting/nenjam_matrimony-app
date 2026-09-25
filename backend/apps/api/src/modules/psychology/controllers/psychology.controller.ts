import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import {
  ApiBearerAuth,
  ApiBadRequestResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiTooManyRequestsResponse,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { PsychologyService } from '../services/psychology.service';
import { SubmitQuizAnswersDto } from '../dto/submit-quiz-answers.dto';
import { ActiveQuizEntity } from '../entities/quiz-question.entity';
import { UserQuizResponseEntity } from '../entities/user-quiz-response.entity';
import { WRITE_LIMIT } from '../../../throttling';

// Marriage Compatibility Quiz — answer storage + validation. Nothing here
// exposes another member's answers or any compatibility score, and the
// caller's own scoring internals (pairRules) are never returned.
@ApiTags('Psychology')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@Controller('psychology/quiz')
@UseGuards(FirebaseAuthGuard)
export class PsychologyController {
  constructor(private readonly psychologyService: PsychologyService) {}

  @Get('active')
  @ApiOperation({
    summary: 'Get the active psychology quiz',
    description:
      'The current 10-question Marriage Compatibility Quiz. Never includes scoring internals (pairRules).',
  })
  @ApiOkResponse({ type: ActiveQuizEntity })
  @ApiNotFoundResponse({ description: 'No active quiz is configured.' })
  getActiveQuiz(): Promise<ActiveQuizEntity> {
    return this.psychologyService.getActiveQuiz();
  }

  @Get('me')
  @ApiOperation({
    summary: "Get the caller's saved answers to the active quiz",
  })
  @ApiOkResponse({ type: UserQuizResponseEntity })
  @ApiNotFoundResponse({
    description: 'No active quiz, or the caller has not taken it yet.',
  })
  getMyResponse(
    @CurrentUser('id') userId: string,
  ): Promise<UserQuizResponseEntity> {
    return this.psychologyService.getMyResponse(userId);
  }

  @Post('submit')
  @Throttle(WRITE_LIMIT)
  @ApiOperation({
    summary: 'Submit (or retake) the active quiz',
    description:
      'Requires exactly one answer for every question in the active quiz. The first submission is always accepted. Resubmitting the SAME answers is a no-op success. Submitting DIFFERENT answers is a retake, allowed once the retake cooldown (PSYCHOLOGY_RETAKE_COOLDOWN_DAYS, default 7) has passed since the last change — except that answers made stale by a quiz update can be retaken immediately.',
  })
  @ApiOkResponse({ type: UserQuizResponseEntity })
  @ApiBadRequestResponse({
    description:
      'Wrong quizId, missing/duplicate/unknown questions, or an invalid selected option.',
  })
  @ApiNotFoundResponse({ description: 'No active quiz is configured.' })
  @ApiTooManyRequestsResponse({
    description:
      'Retake cooldown active. Body: { statusCode: 429, message, retryAfterSeconds }.',
  })
  submitAnswers(
    @CurrentUser('id') userId: string,
    @Body() dto: SubmitQuizAnswersDto,
  ): Promise<UserQuizResponseEntity> {
    return this.psychologyService.submitAnswers(userId, dto);
  }
}
