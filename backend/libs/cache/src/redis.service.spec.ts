import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppConfigService } from '@app/config';
import { REDIS_CLIENT } from './redis.constants';
import { RedisService } from './redis.service';

type Handler = (...args: unknown[]) => void;

function buildMockClient() {
  const handlers: Record<string, Handler> = {};
  return {
    on: jest.fn((event: string, handler: Handler) => {
      handlers[event] = handler;
    }),
    connect: jest.fn(),
    ping: jest.fn(),
    quit: jest.fn(),
    emit(event: string, ...args: unknown[]) {
      handlers[event]?.(...args);
    },
  };
}

type MockClient = ReturnType<typeof buildMockClient>;

describe('RedisService', () => {
  const mockConfig = {
    redis: { host: 'localhost', port: 6379, password: undefined },
  } as unknown as AppConfigService;

  async function buildService(client: MockClient): Promise<RedisService> {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        RedisService,
        { provide: REDIS_CLIENT, useValue: client },
        { provide: AppConfigService, useValue: mockConfig },
      ],
    }).compile();

    return module.get(RedisService);
  }

  it('connects, pings, and logs a banner on success', async () => {
    const client = buildMockClient();
    client.connect.mockResolvedValue(undefined);
    client.ping.mockResolvedValue('PONG');
    const service = await buildService(client);
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    await service.onModuleInit();

    expect(client.connect).toHaveBeenCalled();
    expect(client.ping).toHaveBeenCalled();
    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('REDIS');
    expect(output).toContain('Connection  : SUCCESS');

    logSpy.mockRestore();
  });

  // ioredis's connect() rejects with a generic "Connection is closed." error
  // carrying no code — the real reason only arrives via the 'error' event.
  // Verified empirically; this test guards that we surface the real cause.
  it('uses the real error from the error event, not the generic connect() rejection', async () => {
    const client = buildMockClient();
    const realError = Object.assign(new Error('connect ECONNREFUSED'), {
      code: 'ECONNREFUSED',
    });
    client.connect.mockImplementation(() => {
      client.emit('error', realError);
      return Promise.reject(new Error('Connection is closed.'));
    });
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(realError);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('unreachable');

    errorSpy.mockRestore();
  });

  it('fails startup when PING does not succeed', async () => {
    const client = buildMockClient();
    client.connect.mockResolvedValue(undefined);
    const realError = Object.assign(new Error('timeout'), {
      code: 'ETIMEDOUT',
    });
    client.ping.mockImplementation(() => {
      client.emit('error', realError);
      return Promise.reject(new Error('Connection is closed.'));
    });
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(realError);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('timed out');

    errorSpy.mockRestore();
  });

  it('classifies authentication failures from the Redis protocol error message', async () => {
    const client = buildMockClient();
    client.connect.mockResolvedValue(undefined);
    const authError = new Error('NOAUTH Authentication required.');
    client.ping.mockImplementation(() => {
      client.emit('error', authError);
      return Promise.reject(new Error('Connection is closed.'));
    });
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(authError);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('authentication failed');

    errorSpy.mockRestore();
  });

  it('classifies an invalid host as a DNS failure', async () => {
    const client = buildMockClient();
    const dnsError = Object.assign(new Error('getaddrinfo ENOTFOUND bogus'), {
      code: 'ENOTFOUND',
    });
    client.connect.mockImplementation(() => {
      client.emit('error', dnsError);
      return Promise.reject(new Error('Connection is closed.'));
    });
    const service = await buildService(client);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    await expect(service.onModuleInit()).rejects.toBe(dnsError);
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('Invalid Redis host');

    errorSpy.mockRestore();
  });

  it('quits the client on module destroy', async () => {
    const client = buildMockClient();
    client.quit.mockResolvedValue(undefined);
    const service = await buildService(client);

    await service.onModuleDestroy();

    expect(client.quit).toHaveBeenCalled();
  });
});
