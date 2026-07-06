import { NestFactory } from '@nestjs/core';
import { AppConfigService } from '@app/config';
import { WebsocketModule } from './websocket.module';

async function bootstrap() {
  const app = await NestFactory.create(WebsocketModule);
  app.enableShutdownHooks();
  const config = app.get(AppConfigService);
  await app.listen(config.websocketPort);
}
void bootstrap();
