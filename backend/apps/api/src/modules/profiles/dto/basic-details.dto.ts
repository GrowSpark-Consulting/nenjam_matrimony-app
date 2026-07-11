import { IsDateString, IsIn, IsOptional, IsString } from 'class-validator';

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

  @IsOptional()
  @IsDateString()
  dob?: string;

  @IsOptional()
  @IsIn(['NEVER_MARRIED', 'DIVORCED', 'WIDOWED', 'AWAITING_DIVORCE'])
  maritalStatus?: string;

  @IsOptional()
  @IsString()
  profileCreatedFor?: string;
}
