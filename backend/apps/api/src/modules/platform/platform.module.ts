import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { IdentifierHashService } from './identifier-hash.service';
import { DailyJobRegistry } from './jobs/daily-job.registry';
import { OtpService } from './otp/otp.service';
import { PlatformSettingsService } from './settings/platform-settings.service';

/**
 * Shared building blocks other features use: platform settings, identifier
 * hashing, one-time sign-in codes and the daily job registry. No routes of
 * its own — the settings admin API lives in AdminModule, the daily job route
 * in JobsModule.
 */
@Module({
  // AppConfigModule is not global: hashing and OTP read their config from it.
  imports: [AppConfigModule],
  providers: [
    PlatformSettingsService,
    IdentifierHashService,
    OtpService,
    DailyJobRegistry,
  ],
  exports: [
    PlatformSettingsService,
    IdentifierHashService,
    OtpService,
    DailyJobRegistry,
  ],
})
export class PlatformModule {}
