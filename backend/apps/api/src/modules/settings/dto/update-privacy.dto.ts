import { IsBoolean, IsOptional } from 'class-validator';

/**
 * Body for `PATCH /settings/privacy`. Every field is optional so a caller can
 * toggle one preference at a time; an omitted field is left unchanged. The
 * global ValidationPipe runs `whitelist` + `forbidNonWhitelisted`, so any key
 * other than the two declared here is rejected with a 400.
 */
export class UpdatePrivacyDto {
  @IsOptional()
  @IsBoolean()
  profileVisibleToPremiumOnly?: boolean;

  @IsOptional()
  @IsBoolean()
  hidePhotosFromNonConnections?: boolean;
}
