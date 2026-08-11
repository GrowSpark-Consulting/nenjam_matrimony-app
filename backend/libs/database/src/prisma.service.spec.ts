import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import type { Pool } from 'pg';
import { AppConfigService } from '@app/config';
import { PrismaService, withConnectRetry } from './prisma.service';

// Captures the options PrismaService actually builds its pg.Pool with, so the
// pooling behaviour can be asserted rather than inferred. The real Pool is
// still constructed (it connects lazily, so nothing is dialled here).
jest.mock('pg', () => {
  const actual = jest.requireActual<typeof import('pg')>('pg');
  const captured: Array<Record<string, unknown>> = [];
  class SpyPool extends actual.Pool {
    constructor(options: Record<string, unknown>) {
      captured.push(options);
      super(options);
    }
  }
  return { ...actual, Pool: SpyPool, __capturedPoolOptions: captured };
});

const capturedPoolOptions = (
  jest.requireMock('pg') as { __capturedPoolOptions: Array<Record<string, unknown>> }
).__capturedPoolOptions;

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

  it('never holds an idle connection open indefinitely', async () => {
    await buildService();
    const options = capturedPoolOptions.at(-1);

    // pg-pool only arms the idle timer when the pool is ABOVE `min`
    // (`if (idleTimeoutMillis && this._isAboveMin())`). A non-zero `min`
    // therefore means the last connection never gets an idle timer and is held
    // open forever, until the server or an intermediary drops it — which
    // surfaces as "Connection terminated unexpectedly" on the next request.
    expect(options?.min).toBe(0);
    // Bounded is the whole point — an unbounded idle connection is the bug.
    // The ceiling keeps it inside the conventional five-minute serverless
    // suspend window so we remain the side that closes.
    expect(options?.idleTimeoutMillis).toBeGreaterThan(0);
    expect(options?.idleTimeoutMillis).toBeLessThan(300_000);
    // TCP keepalives are what actually detect a socket that died silently
    // (laptop suspend, network change) rather than being closed cleanly.
    expect(options?.keepAlive).toBe(true);
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

describe('withConnectRetry', () => {
  const logger = { warn: jest.fn() } as unknown as Logger;

  /**
   * Stands in for a pg.Pool, mirroring the one behaviour that matters here:
   * pg-pool's own `query()` acquires its client via `this.connect(cb)`, so when
   * the proxy wraps `connect` the acquisition inside a query is wrapped too.
   */
  function fakePool(connectImpl: () => Promise<unknown>) {
    const stats = { connectAttempts: 0, sqlDispatches: 0 };
    const pool = {
      connect: () => {
        stats.connectAttempts++;
        return connectImpl();
      },
      query(text: string): Promise<string> {
        return new Promise((resolve, reject) => {
          (this as unknown as {
            connect: (cb: (err?: Error, client?: { query: (t: string) => Promise<string>; release: () => void }) => void) => void;
          }).connect((err, client) => {
            if (err || !client) return reject(err);
            stats.sqlDispatches++;
            client.query(text).then(resolve, reject);
          });
        });
      },
    };
    return { pool: pool as unknown as Pool, stats };
  }

  const okClient = {
    query: (text: string) => Promise.resolve(`ran:${text}`),
    release: () => undefined,
  };

  afterEach(() => {
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it('retries a connection that was reset while the compute woke, then succeeds', async () => {
    let attempt = 0;
    const { pool, stats } = fakePool(() => {
      attempt++;
      return attempt < 3
        ? Promise.reject(errorWithCode('ECONNRESET', 'read ECONNRESET'))
        : Promise.resolve(okClient);
    });

    jest.useFakeTimers();
    const result = withConnectRetry(pool, logger).query('SELECT 1');
    await jest.runAllTimersAsync();

    await expect(result).resolves.toBe('ran:SELECT 1');
    expect(stats.connectAttempts).toBe(3);
    // The statement was only ever sent once — the retries all happened before
    // anything reached the server.
    expect(stats.sqlDispatches).toBe(1);
  });

  it('never re-sends a statement that was already dispatched', async () => {
    // The connection is acquired fine; the query itself then fails with an
    // error that *looks* transient. Retrying here could re-apply a write whose
    // reply was merely lost, so it must not happen.
    const { pool, stats } = fakePool(() =>
      Promise.resolve({
        query: () => Promise.reject(errorWithCode('ECONNRESET', 'Connection terminated unexpectedly')),
        release: () => undefined,
      }),
    );

    await expect(withConnectRetry(pool, logger).query('INSERT INTO t VALUES (1)')).rejects.toThrow(
      'Connection terminated unexpectedly',
    );
    expect(stats.sqlDispatches).toBe(1);
    expect(stats.connectAttempts).toBe(1);
  });

  it('does not retry a non-transient failure such as bad credentials', async () => {
    const { pool, stats } = fakePool(() =>
      Promise.reject(errorWithCode('28P01', 'password authentication failed')),
    );

    await expect(withConnectRetry(pool, logger).connect()).rejects.toThrow(
      'password authentication failed',
    );
    expect(stats.connectAttempts).toBe(1);
  });

  it('gives up after a bounded number of attempts rather than retrying forever', async () => {
    const { pool, stats } = fakePool(() =>
      Promise.reject(errorWithCode('ECONNRESET', 'read ECONNRESET')),
    );

    jest.useFakeTimers();
    const result = withConnectRetry(pool, logger).connect();
    const assertion = expect(result).rejects.toThrow('read ECONNRESET');
    await jest.runAllTimersAsync();
    await assertion;

    expect(stats.connectAttempts).toBe(3);
  });

  it('leaves every other pool member working', async () => {
    const { pool } = fakePool(() => Promise.resolve(okClient));
    const proxied = withConnectRetry(pool, logger);

    await expect(proxied.query('SELECT now()')).resolves.toBe('ran:SELECT now()');
    await expect(proxied.connect()).resolves.toBe(okClient);
  });
});
