import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { IdentifierHashService } from './identifier-hash.service';
import { OtpService } from './otp/otp.service';
import { PlatformSettingsService } from './settings/platform-settings.service';

/**
 * Shared building blocks other features use: platform settings, identifier
 * hashing and one-time sign-in codes. No routes of its own — the settings
 * admin API lives in AdminModule.
 */
@Module({
  // AppConfigModule is not global: hashing and OTP read their config from it.
  imports: [AppConfigModule],
  providers: [PlatformSettingsService, IdentifierHashService, OtpService],
  exports: [PlatformSettingsService, IdentifierHashService, OtpService],
})
export class PlatformModule {}
