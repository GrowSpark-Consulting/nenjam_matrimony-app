import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';
import { FirebaseModule } from '@app/firebase';
import { QueueModule } from '@app/queue';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ProfilesModule } from './modules/profiles/profiles.module';
import { MatchesModule } from './modules/matches/matches.module';
import { InterestsModule } from './modules/interests/interests.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { ChatModule } from './modules/chat/chat.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { SettingsModule } from './modules/settings/settings.module';
import { UsersModule } from './modules/users/users.module';
import { SupportModule } from './modules/support/support.module';
import { BlocksModule } from './modules/blocks/blocks.module';
import { ReportsModule } from './modules/reports/reports.module';
import { FeedCacheModule } from './modules/matches/cache/feed-cache.module';
import { throttlerConfig } from './throttling';

@Module({
  imports: [
    AppConfigModule,
    // Rate limiting for the whole REST surface — see ./throttling.ts for why
    // the tiers are what they are. Registered as an APP_GUARD below so it
    // covers every route by default rather than only the ones someone
    // remembered to annotate.
    ThrottlerModule.forRoot(throttlerConfig),
    PrismaModule,
    RedisModule,
    ElasticsearchModule,
    FirebaseModule,
    // Provides the shared BullMQ connection that MailModule's
    // registerQueue() resolves against.
    QueueModule,
    // MailModule is deliberately NOT imported here. Its only consumer in this
    // app is EmailDispatchService, which lives in NotificationsModule and
    // imports it there. Importing it in both places instantiated MailModule
    // twice (verified: "MailModule dependencies initialized" x2), producing two
    // EmailQueue instances and one extra Redis connection per API replica.
    // Harmless functionally — both write to the same queue — but wasteful
    // against a managed Redis connection cap.
    RealtimeModule,
    // Feed invalidation (version + feed.invalidate). @Global — see the module.
    FeedCacheModule,
    ProfilesModule,
    MatchesModule,
    InterestsModule,
    NotificationsModule,
    ChatModule,
    SettingsModule,
    UsersModule,
    SupportModule,
    BlocksModule,
    ReportsModule,
  ],
  controllers: [AppController],
  providers: [
    AppService,
    // Global: every route is rate limited unless it opts into a different
    // tier with @Throttle. Applying this per-controller instead would mean a
    // new endpoint ships unprotected by default, which is the failure mode
    // worth designing out.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
