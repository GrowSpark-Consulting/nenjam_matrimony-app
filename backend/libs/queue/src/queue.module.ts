import { Global, Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { AppConfigModule, AppConfigService } from '@app/config';
import { buildBullMqConnection } from './bullmq-connection.factory';
import { DEFAULT_JOB_OPTIONS } from './queue.constants';

/**
 * Root BullMQ wiring, shared by every app that produces or consumes jobs.
 *
 * Global so `BullModule.registerQueue(...)` in a feature module inherits this
 * connection without each one re-declaring `forRoot`.
 */
@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      imports: [AppConfigModule],
      inject: [AppConfigService],
      useFactory: (configService: AppConfigService) => ({
        connection: buildBullMqConnection(configService),
        defaultJobOptions: DEFAULT_JOB_OPTIONS,
      }),
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
