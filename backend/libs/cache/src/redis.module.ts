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
      useFactory: (configService: AppConfigService) => {
        const { url, host, port, username, password, db } = configService.redis;

        // Options shared by both connection modes — unchanged from before.
        const sharedOptions = {
          lazyConnect: true,
          maxRetriesPerRequest: 1,
          retryStrategy: (times: number) =>
            times > 3 ? null : Math.min(times * 200, 2000),
        };

        // Managed Redis (e.g. Redis Cloud) via a single connection string.
        // ioredis auto-detects TLS from the scheme (redis:// vs rediss://)
        // when given a URL directly, so no separate TLS option is needed.
        // Takes precedence over the discrete fields, mirroring how
        // DATABASE_URL takes precedence over the discrete DATABASE_* fields.
        if (url) {
          return new Redis(url, sharedOptions);
        }

        // Local Redis/Memurai (or any host/port deployment) — unchanged.
        return new Redis({
          host,
          port,
          username,
          password,
          db,
          ...sharedOptions,
        });
      },
    },
    RedisService,
    RedisHealthService,
  ],
  exports: [REDIS_CLIENT, RedisService, RedisHealthService],
})
export class RedisModule {}
