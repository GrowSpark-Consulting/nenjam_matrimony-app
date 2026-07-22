import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { AppConfigService } from '@app/config';
import { PrismaClient } from '../generated/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);

  constructor(private readonly configService: AppConfigService) {
    const db = configService.database;
    // Prefer a full connection string when provided (shared Neon/managed
    // Postgres — carries its own `sslmode`, so SSL is handled by the driver).
    // Fall back to the discrete host/port/... fields for a local Postgres.
    const poolConfig = db.url
      ? { connectionString: db.url }
      : {
          host: db.host,
          port: db.port,
          user: db.username,
          password: db.password,
          database: db.name,
        };
    super({
      adapter: new PrismaPg({
        ...poolConfig,
        // Without a timeout, a query that can't get a pooled connection (pool
        // exhausted by a leaked/idle-in-transaction session) or that's stuck
        // behind a row lock would wait indefinitely with no error — the "hangs
        // forever, no crash" symptom. Both now fail fast with a clear Postgres
        // error instead of hanging past Dio's client-side timeout.
        connectionTimeoutMillis: 10_000,
        statement_timeout: 10_000,
      }),
      log: ['warn', 'error'],
    });
  }

  async onModuleInit(): Promise<void> {
    // $connect() alone does not verify real connectivity with the driver-adapter
    // + query-compiler engine used here: it resolves successfully even with no
    // database reachable at all. A real query is the only reliable liveness check.
    await this.$connect();

    const start = Date.now();
    try {
      await this.$queryRaw`SELECT 1`;
    } catch (error) {
      this.logger.error(
        `Database connection failed: ${this.describeConnectionError(error)}`,
      );
      throw error;
    }

    const latencyMs = Date.now() - start;
    const target = this.describeTarget();

    this.logger.log(
      [
        '=====================================',
        'DATABASE',
        '',
        `Host        : ${target.host}`,
        `Port        : ${target.port}`,
        `Database    : ${target.name}`,
        'Connection  : SUCCESS',
        `Latency     : ${latencyMs} ms`,
        '',
        '=====================================',
      ].join('\n'),
    );
  }

  /** Where we're actually connected — parsed from DATABASE_URL when set, so the
   *  boot banner never misreports the discrete (fallback) host/port/name. */
  private describeTarget(): { host: string; port: number | string; name: string } {
    const { host, port, name, url } = this.configService.database;
    if (url) {
      try {
        const u = new URL(url);
        return {
          host: u.hostname,
          port: u.port || 5432,
          name: u.pathname.replace(/^\//, '') || name,
        };
      } catch {
        // Fall through to discrete fields if the URL is unparseable.
      }
    }
    return { host, port, name };
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }

  private describeConnectionError(error: unknown): string {
    const code = this.extractErrorCode(error);
    const message = error instanceof Error ? error.message : String(error);

    switch (code) {
      case 'ECONNREFUSED':
      case 'ENOTFOUND':
        return `Database is unreachable at ${this.configService.database.host}:${this.configService.database.port}. Is PostgreSQL running?`;
      case 'ETIMEDOUT':
        return 'Connection to the database timed out.';
      // PostgreSQL SQLSTATE 28P01: invalid_password
      case '28P01':
        return `Authentication failed for user "${this.configService.database.username}". Check DATABASE_USER/DATABASE_PASSWORD.`;
      // PostgreSQL SQLSTATE 3D000: invalid_catalog_name (database does not exist)
      case '3D000':
        return `Database "${this.configService.database.name}" does not exist. Create it before starting the app.`;
      default:
        return message || 'Unknown database connection error.';
    }
  }

  private extractErrorCode(error: unknown): string | undefined {
    if (error && typeof error === 'object' && 'code' in error) {
      const code = (error as { code?: unknown }).code;
      return typeof code === 'string' ? code : undefined;
    }
    return undefined;
  }
}
