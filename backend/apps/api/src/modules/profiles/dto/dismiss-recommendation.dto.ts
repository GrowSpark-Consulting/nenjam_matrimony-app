import { IsIn, IsString } from 'class-validator';
import { RECOMMENDATION_CARD_KEYS } from '../domain/recommendation-cards';

export class DismissRecommendationDto {
  /**
   * Which card to hide. Whitelisted against the known keys so a typo is a
   * 400 rather than a row that hides nothing and can never be undone from
   * the UI.
   */
  @IsString()
  @IsIn(RECOMMENDATION_CARD_KEYS as unknown as string[])
  cardKey!: string;
}
