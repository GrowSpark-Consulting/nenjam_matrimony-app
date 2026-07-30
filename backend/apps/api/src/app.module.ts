import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';
import { FirebaseModule } from '@app/firebase';
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
