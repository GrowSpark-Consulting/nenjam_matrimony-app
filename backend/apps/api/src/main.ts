import { NestFactory } from '@nestjs/core';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import compression from 'compression';
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

  // Every response this API sends is JSON, which compresses extremely well:
  // measured on real rows from this database, a 20-profile feed page is 11,163
  // bytes raw and 1,575 gzipped (86% smaller), a 30-message chat page 7,474 →
  // 1,414 (81%), a notifications page 4,909 → 1,208 (75%). The clients are
  // phones on Indian mobile networks, where bytes on the wire dominate
  // perceived latency far more than server time does.
  //
  // `threshold` leaves small bodies alone — below roughly a TCP segment,
  // compressing costs CPU and a header for no fewer packets.
  app.use(compression({ threshold: 1024 }));

  // Real-time WebSocket transport. The Redis adapter fans emits out across API
  // instances when Redis is available; otherwise it's a single-instance
  // in-memory adapter. Must be set before the gateways start.
  const redisAdapter = new RedisIoAdapter(app, app.get(RedisService));
  await redisAdapter.connect();
  app.useWebSocketAdapter(redisAdapter);

  const configForCors = app.get(AppConfigService);

  // Building the OpenAPI document walks every controller, route and DTO in the
  // app. That is pure startup cost for a page nobody opens in production, so
  // it is dev-only — which also stops the schema being served publicly.
  if (configForCors.isDevelopment) {
    setupSwagger(app);
  }

  // Browsers block cross-origin XHR/fetch by default (native/mobile builds
  // never hit this — only the Flutter web build does). CORS_ORIGINS (comma-
  // separated) is the explicit allowlist for whatever domain(s) the frontend
  // is actually deployed to; nothing here is a hardcoded domain. Left unset,
  // this falls back to reflecting the request origin in development (today's
  // behavior) and rejecting all cross-origin requests in production/staging —
  // fail-closed until an allowlist is configured, never fail-open.
  const { origins: allowedOrigins } = configForCors.cors;
  app.enableCors({
    origin:
      allowedOrigins.length > 0 ? allowedOrigins : configForCors.isDevelopment,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-App-Version',
      'Accept',
    ],
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

  console.log(`🚀 API running on http://0.0.0.0:${config.port}`);
}

void bootstrap();
