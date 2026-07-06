import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';

@Module({
  imports: [AppConfigModule, PrismaModule, RedisModule, ElasticsearchModule],
})
export class WorkerModule {}
