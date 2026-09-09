import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { ProfileCompletionService } from '../services/profile-completion.service';
import { RecommendationDismissalRepository } from '../repositories/recommendation-dismissal.repository';
import { ProfileCompletionEntity } from '../entities/profile-completion.entity';
import { DismissRecommendationDto } from '../dto/dismiss-recommendation.dto';
import type { RecommendationCardKey } from '../domain/recommendation-cards';

/**
 * The "Complete Your Profile" recommendations, and the dismissals that hide
 * them.
 *
 * Every route returns the WHOLE completion entity — percentage, breakdown and
 * cards — rather than just the thing that changed. That is what keeps Home
 * and Edit Profile in step: whichever screen dismissed a card gets back the
 * same authoritative state the other screen would have fetched, so there is
 * no window in which the two disagree and no second endpoint to keep
 * consistent.
 *
 * Nothing here writes profile data. A dismissal adds or removes one row in
 * `profile_recommendation_dismissals`, which no profile section reads — the
 * member's family, horoscope and verification answers are untouched either
 * way, and restoring a card brings back the suggestion with the saved data
 * still behind it.
 */
@Controller('profiles/completion')
@UseGuards(FirebaseAuthGuard)
export class ProfileCompletionController {
  constructor(
    private readonly completionService: ProfileCompletionService,
    private readonly dismissalRepository: RecommendationDismissalRepository,
  ) {}

  /**
   * The completion state on its own — same numbers `GET /profiles/draft`
   * carries, without the draft payload, for a screen that only needs the
   * cards.
   */
  @Get()
  get(@CurrentUser('id') userId: string): Promise<ProfileCompletionEntity> {
    return this.completionService.calculate(userId);
  }

  @Post('dismissals')
  async dismiss(
    @CurrentUser('id') userId: string,
    @Body() dto: DismissRecommendationDto,
  ): Promise<ProfileCompletionEntity> {
    await this.dismissalRepository.dismiss(
      userId,
      dto.cardKey as RecommendationCardKey,
    );
    return this.completionService.calculate(userId);
  }

  /**
   * Un-dismisses a card. Not reachable from the cards themselves (there is no
   * "bring it back" affordance on a card that is gone), but it is what any
   * future "show me my suggestions again" control calls, and it is what makes
   * a dismissal provably reversible rather than a one-way door.
   */
  @Delete('dismissals/:cardKey')
  async restore(
    @CurrentUser('id') userId: string,
    @Param('cardKey') cardKey: string,
  ): Promise<ProfileCompletionEntity> {
    await this.dismissalRepository.restore(
      userId,
      cardKey as RecommendationCardKey,
    );
    return this.completionService.calculate(userId);
  }
}
