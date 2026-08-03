import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

/** Body for POST/DELETE /matches/shortlist — the target profile's id (which is
 *  the target user's id, matching DiscoverProfileDto.id). */
export class ShortlistProfileDto {
  @ApiProperty({
    description:
      'The target profile (user) id to add to / remove from the shortlist.',
    example: '5f2b1c8e-1a2b-4c3d-9e8f-0a1b2c3d4e5f',
  })
  @IsString()
  @IsNotEmpty()
  profileId!: string;
}
