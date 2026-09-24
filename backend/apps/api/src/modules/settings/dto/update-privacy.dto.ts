import { IsBoolean, IsOptional } from 'class-validator';

/**
 * Body for `PATCH /settings/privacy`. Every field is optional so a caller can
 * toggle one preference at a time; an omitted field is left unchanged. The
 * global ValidationPipe runs `whitelist` + `forbidNonWhitelisted`, so any key
 * other than the ones declared here is rejected with a 400 — in particular a
 * client cannot send an `isPremium` of its own.
 *
 * Both features are open to every member while `ALLOW_FREE_PRIVACY_CONTROLS`
 * is on. Otherwise they are premium-only: switching one ON without an active
 * premium subscription is a 403. Switching one OFF is always allowed.
 */
export class UpdatePrivacyDto {
  @IsOptional()
  @IsBoolean()
  hideMyProfile?: boolean;

  @IsOptional()
  @IsBoolean()
  hidePhotosFromNonConnections?: boolean;

  /** @deprecated Old name for `hideMyProfile`, still accepted from app builds
   *  that send it. Ignored when `hideMyProfile` is also present. */
  @IsOptional()
  @IsBoolean()
  profileVisibleToPremiumOnly?: boolean;
}
