import { Global, Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';

/**
 * Real-time WebSocket delivery. @Global so any domain module can inject
 * RealtimeGateway to emit after a commit without repeating imports —
 * FirebaseService / PrismaService / RedisService the gateway depends on are all
 * global too. The gateway holds no request state, so a single shared instance
 * is correct.
 */
@Global()
@Module({
  providers: [RealtimeGateway],
  exports: [RealtimeGateway],
})
export class RealtimeModule {}
