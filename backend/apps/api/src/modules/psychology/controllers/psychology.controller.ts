import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiBadRequestResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { PsychologyService } from '../services/psychology.service';
import { SubmitQuizAnswersDto } from '../dto/submit-quiz-answers.dto';
import { ActiveQuizEntity } from '../entities/quiz-question.entity';
import { UserQuizResponseEntity } from '../entities/user-quiz-response.entity';

// Marriage Compatibility Quiz — answer storage + validation only (Phase 1).
// No compatibility score is exposed here; see PsychologyService's doc comment.
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
  @ApiOperation({
    summary: 'Submit (or retake) the active quiz',
    description:
      'Requires exactly one answer for every question in the active quiz. Upserts — resubmitting replaces the caller’s prior answers for this quiz.',
  })
  @ApiOkResponse({ type: UserQuizResponseEntity })
  @ApiBadRequestResponse({
    description:
      'Wrong quizId, missing/duplicate/unknown questions, or an invalid selected option.',
  })
  @ApiNotFoundResponse({ description: 'No active quiz is configured.' })
  submitAnswers(
    @CurrentUser('id') userId: string,
    @Body() dto: SubmitQuizAnswersDto,
  ): Promise<UserQuizResponseEntity> {
    return this.psychologyService.submitAnswers(userId, dto);
  }
}
