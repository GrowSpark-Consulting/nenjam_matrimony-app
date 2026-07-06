import { NestFactory } from '@nestjs/core';
import { AppConfigService } from '@app/config';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks();
  const config = app.get(AppConfigService);
  await app.listen(config.port);
}
void bootstrap();
