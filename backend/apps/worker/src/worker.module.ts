import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';
import { QueueModule } from '@app/queue';
import { MailModule } from '@app/mail';

@Module({
  imports: [
    AppConfigModule,
    PrismaModule,
    RedisModule,
    ElasticsearchModule,
    // QueueModule must precede any module calling BullModule.registerQueue —
    // it provides the shared connection those registrations resolve against.
    QueueModule,
    // forWorker (not forRoot): this is the process that actually consumes the
    // queue, renders templates and talks to the provider.
    MailModule.forWorker(),
  ],
})
export class WorkerModule {}
