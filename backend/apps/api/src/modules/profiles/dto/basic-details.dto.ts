import { Transform } from 'class-transformer';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { IsBirthDate, normalizeBirthDate } from '../validation/birth-date';

// Mirrors Frontend/lib/features/registration/domain/models/profile_draft.dart -> BasicDetails (step 1)
export class BasicDetailsDto {
  @IsOptional()
  @IsString()
  firstName?: string;

  @IsOptional()
  @IsString()
  lastName?: string;

  @IsOptional()
  @IsIn(['MALE', 'FEMALE'])
  gender?: string;

  /**
   * `YYYY-MM-DD`. A calendar date, not a timestamp — see
   * `validation/birth-date.ts` for why the distinction matters and for the
   * rule this enforces (a real day, in the past, at least 21 years ago).
   *
   * `@IsDateString()` stood here and accepted every impossible, future and
   * under-age date the client had already been told to refuse, so a raw API
   * call or an older build could write one straight into `user_profiles.dob`.
   * Full ISO-8601 timestamps opening with a calendar date are still accepted,
   * because the builds that send them are in members' hands — but @Transform
   * reduces one to its calendar date before anything else sees it, so what is
   * validated and what lands in `draft_data` is always `YYYY-MM-DD`. See
   * normalizeBirthDate for why the time and offset are discarded rather than
   * applied.
   */
  @IsOptional()
  @Transform(({ value }) => normalizeBirthDate(value))
  @IsBirthDate()
  dob?: string;

  @IsOptional()
  @IsIn(['NEVER_MARRIED', 'DIVORCED', 'WIDOWED', 'AWAITING_DIVORCE'])
  maritalStatus?: string;

  @IsOptional()
  @IsString()
  profileCreatedFor?: string;
}
