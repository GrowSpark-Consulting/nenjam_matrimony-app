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

  get firebase(): AppConfig['firebase'] {
    return this.configService.get('firebase', { infer: true });
  }

  get logLevel(): string {
    return this.configService.get('logLevel', { infer: true });
  }

  checkHealth(): ConfigHealth {
    const details: Record<string, boolean> = {
      envFileLoaded: Boolean(this.nodeEnv),
      port: Boolean(this.port),
      database: Boolean(this.database?.host && this.database?.name),
      redis: Boolean(this.redis?.host),
      elasticsearch: Boolean(this.elasticsearch?.node),
      smtp: Boolean(this.smtp?.host),
      jwt: Boolean(this.jwt?.secret),
      firebase: Boolean(
        this.firebase?.projectId &&
        this.firebase?.clientEmail &&
        this.firebase?.privateKey,
      ),
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
      `Database    : ${this.database.host}:${this.database.port}`,
      `Redis       : ${this.redis.host}:${this.redis.port}`,
      `Elastic     : ${this.elasticsearch.node}`,
      `SMTP        : ${this.smtp.host}:${this.smtp.port}`,
      `Firebase    : ${this.firebase.projectId || 'not configured'}`,
      '',
      `Configuration Validation ${health.status === 'ok' ? '✔' : '✘'}`,
      '=====================================',
    ].join('\n');

    this.logger.log(banner);
  }
}
