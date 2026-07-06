import { Global, Module } from '@nestjs/common';
import Redis from 'ioredis';
import { AppConfigModule, AppConfigService } from '@app/config';
import { REDIS_CLIENT } from './redis.constants';
import { RedisService } from './redis.service';
import { RedisHealthService } from './redis.health';

@Global()
@Module({
  imports: [AppConfigModule],
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [AppConfigService],
      useFactory: (configService: AppConfigService) =>
        new Redis({
          host: configService.redis.host,
          port: configService.redis.port,
          password: configService.redis.password,
          lazyConnect: true,
          maxRetriesPerRequest: 1,
          retryStrategy: (times: number) =>
            times > 3 ? null : Math.min(times * 200, 2000),
        }),
    },
    RedisService,
    RedisHealthService,
  ],
  exports: [REDIS_CLIENT, RedisService, RedisHealthService],
})
export class RedisModule {}
