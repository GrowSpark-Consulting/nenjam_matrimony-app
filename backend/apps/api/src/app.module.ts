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
import { SettingsModule } from './modules/settings/settings.module';

@Module({
  imports: [
    AppConfigModule,
    PrismaModule,
    RedisModule,
    ElasticsearchModule,
    FirebaseModule,
    ProfilesModule,
    MatchesModule,
    SettingsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
