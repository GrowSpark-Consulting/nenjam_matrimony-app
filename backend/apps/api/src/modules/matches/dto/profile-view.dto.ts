import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';
import type { DiscoverProfileDto } from './discover-profile.response.dto';
import { DISCOVER_PROFILE_EXAMPLE } from '../../interests/dto/interest-response.dto';

/** Body for POST /matches/profile-view — whose profile was just opened. */
export class RecordProfileViewDto {
  @ApiProperty({
    description: 'The profile (user) id the caller has just opened.',
    example: DISCOVER_PROFILE_EXAMPLE.id,
  })
  @IsString()
  @IsNotEmpty()
  profileId!: string;
}

/**
 * One entry of GET /matches/profile-views.
 *
 * Wraps the standard Discover card rather than defining a parallel profile
 * shape, so the viewers grid reuses the same card widget as every other
 * profile list; [viewedAt] is the only extra the screen needs.
 */
export class ProfileViewerDto {
  @ApiProperty({ description: 'The viewer, as a Discover card.' })
  profile!: DiscoverProfileDto;

  @ApiProperty({
    description: "ISO-8601 timestamp of this viewer's most recent view.",
    example: '2026-08-10T09:15:00.000Z',
  })
  viewedAt!: string;
}

export const PROFILE_VIEWER_EXAMPLE = {
  profile: DISCOVER_PROFILE_EXAMPLE,
  viewedAt: '2026-08-10T09:15:00.000Z',
};
