import { IsNotEmpty, IsString } from 'class-validator';

/** Body for POST/DELETE /matches/shortlist — the target profile's id (which is
 *  the target user's id, matching DiscoverProfileDto.id). */
export class ShortlistProfileDto {
  @IsString()
  @IsNotEmpty()
  profileId!: string;
}
