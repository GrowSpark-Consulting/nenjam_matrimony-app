/**
 * Request bodies and queries of the agent-facing and member referral routes
 * (docs/agent-program/agent-api.openapi.yaml). The DTOs check shape only
 * (present, string, no extra fields); the services check the content
 * (E.164, code format, PAN, IFSC...), so the rules live in one place.
 */
import { Type } from 'class-transformer';
import {
  IsDefined,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export class OtpRequestDto {
  @IsString()
  phone!: string;
}

export class OtpVerifyDto {
  @IsString()
  challengeId!: string;

  @IsString()
  code!: string;
}

export class RefreshDto {
  @IsString()
  refreshToken!: string;
}

export class LogoutDto {
  @IsString()
  refreshToken!: string;

  /** Accepted per the contract; there are no agent push devices yet. */
  @IsOptional()
  @IsString()
  fcmToken?: string;
}

export class ApplicationDto {
  @IsString()
  name!: string;

  @IsString()
  city!: string;

  @IsString()
  state!: string;

  @IsOptional()
  @IsString()
  pan?: string;
}

export class UpiDetailsDto {
  @IsString()
  vpa!: string;
}

export class BankDetailsDto {
  @IsString()
  accountHolderName!: string;

  @IsString()
  accountNumber!: string;

  @IsString()
  ifsc!: string;
}

export class PayoutDetailsDto {
  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => UpiDetailsDto)
  upi?: UpiDetailsDto;

  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => BankDetailsDto)
  bank?: BankDetailsDto;
}

export class ReferralsQueryDto {
  @IsOptional()
  @IsString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @IsIn(['REGISTERED', 'PROFILE_COMPLETE', 'PURCHASED'])
  stage?: string;
}

export class CommissionsQueryDto {
  @IsOptional()
  @IsString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @IsIn(['ON_HOLD', 'APPROVED', 'PAID', 'CANCELLED'])
  status?: string;
}

export class PayoutsQueryDto {
  @IsOptional()
  @IsString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}

/** POST /agent/devices: the website portal has no push, so only the apps. */
export class DeviceDto {
  @IsDefined()
  @IsString()
  @Length(20, 4096)
  fcmToken!: string;

  @IsDefined()
  @IsIn(['ANDROID', 'IOS'])
  platform!: string;
}

export class ReferralCodeDto {
  @IsDefined()
  @IsString()
  code!: string;
}
