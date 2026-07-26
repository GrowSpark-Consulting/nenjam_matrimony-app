import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsNotEmpty, IsOptional, IsString } from 'class-validator';

/**
 * Body for `POST /matches/interest`, which the Flutter client hits for two
 * distinct actions (one path, by design — see the frontend
 * InterestsRepositoryImpl):
 *   - `{ profileId }`            → send an interest to that profile
 *   - `{ interestId, accept }`   → accept (true) / decline (false) a received one
 *
 * Both groups are optional at the type level; InterestsService enforces that
 * exactly one valid mode is present and rejects an ambiguous/empty body.
 */
export class MatchInterestDto {
  @ApiPropertyOptional({
    description: 'Send mode — the target profile (user) id to send an interest to.',
    example: '5f2b1c8e-1a2b-4c3d-9e8f-0a1b2c3d4e5f',
  })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  profileId?: string;

  @ApiPropertyOptional({
    description: 'Respond mode — the id of the received interest to accept/decline.',
    example: '9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
  })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  interestId?: string;

  @ApiPropertyOptional({
    description: 'Respond mode — true accepts, false declines. Required with interestId.',
    example: true,
  })
  @IsOptional()
  @IsBoolean()
  accept?: boolean;
}
