import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';
import { QueueModule } from '@app/queue';
import { MailModule } from '@app/mail';
import { WeeklyDigestCron } from './cron/weekly-digest.cron';

@Module({
  imports: [
    AppConfigModule,
    PrismaModule,
    RedisModule,
    ElasticsearchModule,
    ScheduleModule.forRoot(),
    // Provides the shared BullMQ connection the mail queue registers against.
    QueueModule,
    // forRoot (producer only): the scheduler queues digests, it does not send
    // them — the worker stays the single consumer.
    MailModule.forRoot(),
  ],
  providers: [WeeklyDigestCron],
})
export class SchedulerModule {}
