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
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  profileId?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  interestId?: string;

  @IsOptional()
  @IsBoolean()
  accept?: boolean;
}
