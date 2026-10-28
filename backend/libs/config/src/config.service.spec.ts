import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { AppConfigService } from './config.service';
import { AppConfig } from './configuration';

describe('AppConfigService', () => {
  const mockConfig: AppConfig = {
    nodeEnv: 'development',
    port: 3000,
    websocketPort: 3001,
    database: {
      host: 'localhost',
      port: 5432,
      username: 'postgres',
      password: 'super-secret-password',
      name: 'app',
    },
    redis: { host: 'localhost', port: 6379 },
    elasticsearch: { node: 'http://localhost:9200' },
    smtp: { host: 'localhost', port: 1025, user: '', password: '' },
    jwt: { secret: 'a-very-long-secret-value' },
    cors: { origins: [] },
    mail: {
      provider: 'noop',
      from: 'Nenjam Matrimony <no-reply@example.com>',
      appUrl: 'https://example.com',
      supportEmail: 'support@example.com',
    },
    firebase: {},
    storage: {},
    faceVerification: {
      enabled: false,
      region: 'ap-south-1',
      credentialsTtlSeconds: 900,
      minLivenessConfidence: 90,
      minMatchSimilarity: 90,
      maxAttemptsPerDay: 3,
      globalDailyCap: 500,
    },
    logLevel: 'debug',
    fallback: {
      enabled: true,
      ageRelaxStep1: 2,
      ageRelaxStep2: 5,
      maxTier: 10,
    },
    psychology: { enabled: true, timeoutMs: 800, retakeCooldownDays: 7 },
    membership: { enforcementMode: 'shadow' },
    razorpay: {},
    admin: {},
  };

  async function buildService(
    overrides: Partial<AppConfig> = {},
  ): Promise<AppConfigService> {
    const config = { ...mockConfig, ...overrides };
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AppConfigService,
        {
          provide: ConfigService,
          useValue: {
            get: (key: keyof AppConfig) => config[key],
          },
        },
      ],
    }).compile();

    return module.get(AppConfigService);
  }

  it('exposes typed getters matching the loaded configuration', async () => {
    const service = await buildService();

    expect(service.nodeEnv).toBe('development');
    expect(service.port).toBe(3000);
    expect(service.database.host).toBe('localhost');
    expect(service.database.port).toBe(5432);
    expect(service.redis.host).toBe('localhost');
    expect(service.smtp.host).toBe('localhost');
    expect(service.jwt.secret).toBe('a-very-long-secret-value');
  });

  it('derives isProduction/isDevelopment from nodeEnv', async () => {
    const dev = await buildService();
    expect(dev.isDevelopment).toBe(true);
    expect(dev.isProduction).toBe(false);

    const prod = await buildService({ nodeEnv: 'production' });
    expect(prod.isProduction).toBe(true);
    expect(prod.isDevelopment).toBe(false);
  });

  it('reports a healthy status when all sections are populated', async () => {
    const service = await buildService();
    const health = service.checkHealth();

    expect(health.status).toBe('ok');
    expect(Object.values(health.details).every(Boolean)).toBe(true);
  });

  it('reports an error status when a required section is missing', async () => {
    const service = await buildService({ jwt: { secret: '' } });
    expect(service.checkHealth().status).toBe('error');
  });

  it('never includes secret values in the health check details', async () => {
    const service = await buildService();
    const health = service.checkHealth();

    expect(JSON.stringify(health)).not.toContain(mockConfig.jwt.secret);
    expect(JSON.stringify(health)).not.toContain(mockConfig.database.password);
  });

  it('treats a REDIS_URL-only configuration as healthy and describes it in the banner', async () => {
    const service = await buildService({
      redis: {
        host: '',
        port: NaN,
        url: 'rediss://default:secret@redis-cloud.example.com:6379',
      },
    });
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    const health = service.checkHealth();
    service.onModuleInit();

    expect(health.details.redis).toBe(true);
    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('redis-cloud.example.com:6379 (via REDIS_URL)');
    expect(output).not.toContain('secret');

    logSpy.mockRestore();
  });

  it('logs the startup banner without leaking secrets', async () => {
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();
    const service = await buildService();

    service.onModuleInit();

    expect(logSpy).toHaveBeenCalled();
    const loggedOutput = logSpy.mock.calls
      .map((call) => String(call[0]))
      .join('\n');

    expect(loggedOutput).toContain('Configuration Loaded');
    expect(loggedOutput).toContain('Configuration Validation ✔');
    expect(loggedOutput).not.toContain(mockConfig.jwt.secret);
    expect(loggedOutput).not.toContain(mockConfig.database.password);

    logSpy.mockRestore();
  });
});
