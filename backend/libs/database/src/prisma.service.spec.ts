import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppConfigService } from '@app/config';
import { PrismaService } from './prisma.service';

function errorWithCode(code: string, message = ''): Error {
  return Object.assign(new Error(message), { code });
}

function spyOnQueryRaw(
  service: PrismaService,
): jest.SpyInstance<Promise<unknown>, unknown[]> {
  const target = service as unknown as {
    $queryRaw: (...args: unknown[]) => Promise<unknown>;
  };
  return jest.spyOn(target, '$queryRaw');
}

describe('PrismaService', () => {
  const mockConfig = {
    database: {
      host: 'localhost',
      port: 5432,
      username: 'postgres',
      password: 'super-secret-password',
      name: 'app_db',
    },
  } as unknown as AppConfigService;

  async function buildService(): Promise<PrismaService> {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PrismaService,
        { provide: AppConfigService, useValue: mockConfig },
      ],
    }).compile();

    const service = module.get(PrismaService);
    jest.spyOn(service, '$connect').mockResolvedValue(undefined);
    return service;
  }

  // $connect() resolves even with no reachable database in this driver-adapter
  // setup (verified empirically), so onModuleInit uses a real `SELECT 1` via
  // $queryRaw as the actual liveness check — these tests mock that instead.

  // onModuleInit retries a failing SELECT 1 up to CONNECT_MAX_ATTEMPTS times
  // with real (2s/4s/6s) backoff between attempts, to ride out a Neon
  // cold-start blip instead of crashing the app on one transient failure.
  // Every "always fails" test below exhausts all attempts, which would
  // otherwise make these tests actually wait ~12s each (and blow past Jest's
  // 5s default timeout) — fake timers let the backoff elapse instantly.
  afterEach(() => {
    jest.useRealTimers();
  });

  it('connects successfully and logs a banner without leaking the password', async () => {
    const service = await buildService();
    spyOnQueryRaw(service).mockResolvedValue([{ '?column?': 1 }]);
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    await service.onModuleInit();

    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('DATABASE');
    expect(output).toContain('Connection  : SUCCESS');
    expect(output).not.toContain(mockConfig.database.password);

    logSpy.mockRestore();
  });

  it('retries a transient failure and succeeds without throwing once a later attempt connects', async () => {
    const service = await buildService();
    spyOnQueryRaw(service)
      .mockRejectedValueOnce(errorWithCode('ETIMEDOUT'))
      .mockRejectedValueOnce(errorWithCode('ETIMEDOUT'))
      .mockResolvedValueOnce([{ '?column?': 1 }]);
    const warnSpy = jest.spyOn(Logger.prototype, 'warn').mockImplementation();
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    jest.useFakeTimers();
    const init = service.onModuleInit();
    await jest.runAllTimersAsync();
    await expect(init).resolves.toBeUndefined();

    // Warned twice (the two failed attempts), then logged the SUCCESS banner
    // on the third — never rejected the whole app for a transient blip.
    expect(warnSpy).toHaveBeenCalledTimes(2);
    expect(
      logSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('Connection  : SUCCESS');

    warnSpy.mockRestore();
    logSpy.mockRestore();
  });

  it('logs a meaningful error and rethrows when the connection is refused', async () => {
    const service = await buildService();
    spyOnQueryRaw(service).mockRejectedValue(errorWithCode('ECONNREFUSED'));
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    jest.useFakeTimers();
    const init = service.onModuleInit();
    const assertion = expect(init).rejects.toThrow();
    await jest.runAllTimersAsync();
    await assertion;
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('unreachable');

    errorSpy.mockRestore();
  });

  it('logs a meaningful error for authentication failures (SQLSTATE 28P01)', async () => {
    const service = await buildService();
    spyOnQueryRaw(service).mockRejectedValue(errorWithCode('28P01'));
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    jest.useFakeTimers();
    const init = service.onModuleInit();
    const assertion = expect(init).rejects.toThrow();
    await jest.runAllTimersAsync();
    await assertion;
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('Authentication failed');

    errorSpy.mockRestore();
  });

  it('logs a meaningful error when the database does not exist (SQLSTATE 3D000)', async () => {
    const service = await buildService();
    spyOnQueryRaw(service).mockRejectedValue(errorWithCode('3D000'));
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    jest.useFakeTimers();
    const init = service.onModuleInit();
    const assertion = expect(init).rejects.toThrow();
    await jest.runAllTimersAsync();
    await assertion;
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('does not exist');

    errorSpy.mockRestore();
  });

  it('logs a meaningful error on connection timeout', async () => {
    const service = await buildService();
    spyOnQueryRaw(service).mockRejectedValue(errorWithCode('ETIMEDOUT'));
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    jest.useFakeTimers();
    const init = service.onModuleInit();
    const assertion = expect(init).rejects.toThrow();
    await jest.runAllTimersAsync();
    await assertion;
    expect(
      errorSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('timed out');

    errorSpy.mockRestore();
  });

  it('disconnects on module destroy', async () => {
    const service = await buildService();
    const disconnectSpy = jest
      .spyOn(service, '$disconnect')
      .mockResolvedValue(undefined);

    await service.onModuleDestroy();

    expect(disconnectSpy).toHaveBeenCalled();
  });
});
