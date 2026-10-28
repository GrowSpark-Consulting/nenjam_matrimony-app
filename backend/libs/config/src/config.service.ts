import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from './configuration';

export interface ConfigHealth {
  status: 'ok' | 'error';
  details: Record<string, boolean>;
}

@Injectable()
export class AppConfigService implements OnModuleInit {
  private readonly logger = new Logger(AppConfigService.name);

  constructor(private readonly configService: ConfigService<AppConfig, true>) {}

  get nodeEnv(): string {
    return this.configService.get('nodeEnv', { infer: true });
  }

  get isProduction(): boolean {
    return this.nodeEnv === 'production';
  }

  get isDevelopment(): boolean {
    return this.nodeEnv === 'development';
  }

  get port(): number {
    return this.configService.get('port', { infer: true });
  }

  get websocketPort(): number {
    return this.configService.get('websocketPort', { infer: true });
  }

  get database(): AppConfig['database'] {
    return this.configService.get('database', { infer: true });
  }

  get redis(): AppConfig['redis'] {
    return this.configService.get('redis', { infer: true });
  }

  get elasticsearch(): AppConfig['elasticsearch'] {
    return this.configService.get('elasticsearch', { infer: true });
  }

  get smtp(): AppConfig['smtp'] {
    return this.configService.get('smtp', { infer: true });
  }

  get jwt(): AppConfig['jwt'] {
    return this.configService.get('jwt', { infer: true });
  }

  get cors(): AppConfig['cors'] {
    return this.configService.get('cors', { infer: true });
  }

  get firebase(): AppConfig['firebase'] {
    return this.configService.get('firebase', { infer: true });
  }

  get mail(): AppConfig['mail'] {
    return this.configService.get('mail', { infer: true });
  }

  get storage(): AppConfig['storage'] {
    return this.configService.get('storage', { infer: true });
  }

  get faceVerification(): AppConfig['faceVerification'] {
    return this.configService.get('faceVerification', { infer: true });
  }

  get logLevel(): string {
    return this.configService.get('logLevel', { infer: true });
  }

  get fallback(): AppConfig['fallback'] {
    return this.configService.get('fallback', { infer: true });
  }

  get psychology(): AppConfig['psychology'] {
    return this.configService.get('psychology', { infer: true });
  }

  get membership(): AppConfig['membership'] {
    return this.configService.get('membership', { infer: true });
  }

  get razorpay(): AppConfig['razorpay'] {
    return this.configService.get('razorpay', { infer: true });
  }

  checkHealth(): ConfigHealth {
    const details: Record<string, boolean> = {
      envFileLoaded: Boolean(this.nodeEnv),
      port: Boolean(this.port),
      database: Boolean(this.database?.host && this.database?.name),
      redis: Boolean(this.redis?.url || this.redis?.host),
      elasticsearch: Boolean(this.elasticsearch?.node),
      smtp: Boolean(this.smtp?.host),
      jwt: Boolean(this.jwt?.secret),
    };

    const status = Object.values(details).every(Boolean) ? 'ok' : 'error';
    return { status, details };
  }

  onModuleInit(): void {
    const health = this.checkHealth();

    const banner = [
      '=====================================',
      'Configuration Loaded',
      '',
      `Environment : ${this.nodeEnv}`,
      `Port        : ${this.port}`,
      `Database    : ${this.describeDatabaseTarget()}`,
      `Redis       : ${this.describeRedisTarget()}`,
      `Elastic     : ${this.elasticsearch.node}`,
      `SMTP        : ${this.smtp.host}:${this.smtp.port}`,
      '',
      `Configuration Validation ${health.status === 'ok' ? '✔' : '✘'}`,
      '=====================================',
    ].join('\n');

    this.logger.log(banner);
  }

  /** Shows the real DB endpoint in the boot banner: the DATABASE_URL host when
   *  set (shared Neon/managed Postgres), otherwise the discrete host:port. */
  private describeDatabaseTarget(): string {
    const { host, port, url } = this.database;
    if (url) {
      try {
        const u = new URL(url);
        return `${u.hostname}:${u.port || 5432} (via DATABASE_URL)`;
      } catch {
        /* fall through */
      }
    }
    return `${host}:${port}`;
  }

  /** Shows the real Redis endpoint in the boot banner: the REDIS_URL host
   *  when set (e.g. Redis Cloud), otherwise the discrete host:port. */
  private describeRedisTarget(): string {
    const { host, port, url } = this.redis;
    if (url) {
      try {
        const u = new URL(url);
        return `${u.hostname}:${u.port || 6379} (via REDIS_URL)`;
      } catch {
        /* fall through */
      }
    }
    return `${host}:${port}`;
  }
}
