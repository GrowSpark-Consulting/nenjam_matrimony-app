import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { PrismaModule } from '@app/database';
import { RedisModule } from '@app/cache';
import { ElasticsearchModule } from '@app/search';
import { FirebaseModule } from '@app/firebase';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './modules/auth/auth.module';

@Module({
  imports: [
    AppConfigModule,
    PrismaModule,
    RedisModule,
    ElasticsearchModule,
    FirebaseModule,
    AuthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
