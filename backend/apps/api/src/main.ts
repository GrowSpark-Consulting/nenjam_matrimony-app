import { NestFactory } from '@nestjs/core';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppConfigService } from '@app/config';
import { RedisService } from '@app/cache';
import { AppModule } from './app.module';
import { RedisIoAdapter } from './adapters/redis-io.adapter';

/**
 * Interactive API docs. Documents the existing API — it never changes routes or
 * shapes. Auth is a Firebase ID token: click "Authorize" and paste the token as
 * the bearer value (the same `Authorization: Bearer <token>` every client sends).
 */
function setupSwagger(app: INestApplication): void {
  const config = new DocumentBuilder()
    .setTitle('Nenjam Matrimony API')
    .setDescription(
      'Matrimonial platform API. All endpoints require a Firebase ID token — ' +
        'authorize with `Bearer <token>`.',
    )
    .setVersion('1.0')
    .addBearerAuth(
      {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'Firebase ID Token',
        description: 'Firebase ID token from the signed-in client.',
      },
      'firebase',
    )
    .addTag('Interests', 'Send / respond / withdraw / list interests')
    .addTag('Shortlist', 'Add / remove / list shortlisted profiles')
    .addTag('Notifications', 'Notification center + unread count')
    .addTag('Blocks', 'Block / unblock a member by user id')
    .addTag('Reports', 'Report a member for moderation review')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document, {
    swaggerOptions: { persistAuthorization: true },
  });
}

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableShutdownHooks();

  // Real-time WebSocket transport. The Redis adapter fans emits out across API
  // instances when Redis is available; otherwise it's a single-instance
  // in-memory adapter. Must be set before the gateways start.
  const redisAdapter = new RedisIoAdapter(app, app.get(RedisService));
  await redisAdapter.connect();
  app.useWebSocketAdapter(redisAdapter);

  setupSwagger(app);

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