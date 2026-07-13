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
    super({
      adapter: new PrismaPg({
        host: configService.database.host,
        port: configService.database.port,
        user: configService.database.username,
        password: configService.database.password,
        database: configService.database.name,
        // No timeout was previously set here, so a query that can't get a
        // pooled connection (pool exhausted by a leaked/idle-in-transaction
        // session) or that gets stuck behind a row lock would wait
        // indefinitely with no error — exactly the "hangs forever, no crash"
        // symptom this fixes: both now fail fast with a clear Postgres error
        // instead of hanging past Dio's client-side timeout.
        connectionTimeoutMillis: 10_000,
        statement_timeout: 10_000,
      }),
      // TEMPORARY DEBUG LOGGING — surfaces exact SQL + timing for the
      // PATCH /profiles/draft/* hang investigation. Remove once resolved.
      log: ['query', 'warn', 'error'],
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
    const { host, port, name } = this.configService.database;

    this.logger.log(
      [
        '=====================================',
        'DATABASE',
        '',
        `Host        : ${host}`,
        `Port        : ${port}`,
        `Database    : ${name}`,
        'Connection  : SUCCESS',
        `Latency     : ${latencyMs} ms`,
        '',
        '=====================================',
      ].join('\n'),
    );
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
