import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PlatformModule } from '../platform/platform.module';
import { SubscriptionModule } from '../subscription/subscription.module';
import { DailyJobsController } from './daily-jobs.controller';
import { DailyJobsService } from './daily-jobs.service';

/**
 * The daily job route. Features add work through PlatformModule's
 * DailyJobRegistry; this module only runs it.
 */
@Module({
  imports: [AppConfigModule, PlatformModule, SubscriptionModule],
  controllers: [DailyJobsController],
  providers: [DailyJobsService],
})
export class JobsModule {}
