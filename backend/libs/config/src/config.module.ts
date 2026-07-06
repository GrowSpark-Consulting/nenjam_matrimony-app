import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import configuration from './configuration';
import { validationSchema } from './validation';
import { AppConfigService } from './config.service';

const NODE_ENV = process.env.NODE_ENV ?? 'development';

@Module({
  imports: [
    ConfigModule.forRoot({
  isGlobal: true,
  cache: true,
  expandVariables: true,
  envFilePath: ['.env'],
  load: [configuration],
  validationSchema,
  validationOptions: {
    abortEarly: false,
  },
}),
  ],
  providers: [AppConfigService],
  exports: [AppConfigService],
})
export class AppConfigModule {}
