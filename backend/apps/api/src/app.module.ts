import { Module } from '@nestjs/common';
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
import { SupportModule } from './modules/support/support.module';
import { BlocksModule } from './modules/blocks/blocks.module';
import { ReportsModule } from './modules/reports/reports.module';

@Module({
  imports: [
    AppConfigModule,
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
    ProfilesModule,
    MatchesModule,
    InterestsModule,
    NotificationsModule,
    ChatModule,
    SettingsModule,
    SupportModule,
    BlocksModule,
    ReportsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
