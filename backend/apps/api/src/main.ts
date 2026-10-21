import { NestFactory } from '@nestjs/core';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import type { NestExpressApplication } from '@nestjs/platform-express';
import compression from 'compression';
import helmet from 'helmet';
import { AppConfigService } from '@app/config';
import { RedisService } from '@app/cache';
import { AppModule } from './app.module';
import { RedisIoAdapter } from './adapters/redis-io.adapter';
import { corsOriginOption } from './adapters/cors-origin';

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
  // Typed as the Express application so `set('trust proxy', ...)` below is
  // reachable — the platform is already Express, this only names it.
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  app.enableShutdownHooks();

  // Standard security response headers: HSTS, X-Content-Type-Options,
  // Referrer-Policy, frame denial and friends. There were none before.
  //
  // The Content-Security-Policy default is disabled deliberately. This process
  // serves a JSON API plus the Swagger UI, and helmet's default CSP breaks the
  // latter's inline scripts and styles. A CSP protects a browser rendering
  // *our* HTML; the only HTML here is dev-only docs. Turn it back on if this
  // process ever serves an application UI.
  //
  // `crossOriginResourcePolicy` is relaxed to same-site because profile photos
  // are fetched by the Flutter client directly from S3 presigned URLs, not
  // proxied through here — the stricter same-origin default buys nothing and
  // risks blocking legitimate cross-origin reads.
  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginResourcePolicy: { policy: 'same-site' },
    }),
  );

  // Rate limiting counts per client IP. Behind Railway (or any load balancer)
  // every request otherwise appears to originate from the proxy's single
  // address, which would put the entire userbase in one shared bucket and make
  // the limits fire for everyone at once. Trusting one proxy hop makes
  // `req.ip` the real client again.
  app.set('trust proxy', 1);

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
  const appConfig = app.get(AppConfigService);
  const redisAdapter = new RedisIoAdapter(app, app.get(RedisService), {
    allowedOrigins: appConfig.cors.origins,
    isDevelopment: appConfig.isDevelopment,
  });
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
    origin: corsOriginOption({
      allowedOrigins,
      isDevelopment: configForCors.isDevelopment,
    }),
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
