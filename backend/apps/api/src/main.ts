import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableShutdownHooks();

  const configForCors = app.get(AppConfigService);
  // Browsers block cross-origin XHR/fetch by default (native/mobile builds
  // never hit this — only the Flutter web build does). No production origin
  // allowlist exists yet since there's no deployed environment — reflect
  // the request origin in dev, tighten this once one exists.
  app.enableCors({
    origin: configForCors.isDevelopment ? true : false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-App-Version', 'Accept'],
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  const config = app.get(AppConfigService);

  await app.listen(config.port, '0.0.0.0');

  console.log(
    `🚀 API running on http://0.0.0.0:${config.port}`,
  );
}

void bootstrap();