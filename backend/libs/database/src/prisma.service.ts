import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { Pool, type PoolClient } from 'pg';
import { AppConfigService } from '@app/config';
import { PrismaClient } from '../generated/client';

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Socket-level failures where the connection never became usable, so nothing
 *  was sent to the server. Deliberately excludes "timeout exceeded when trying
 *  to connect", which means the pool is saturated — retrying that just delays a
 *  real capacity problem past Prisma's transaction maxWait. */
const TRANSIENT_CONNECT_ERRORS = new Set([
  'ECONNRESET',
  'ECONNREFUSED',
  'ETIMEDOUT',
  'EPIPE',
]);

function isTransientConnectError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const code = (error as NodeJS.ErrnoException).code;
  if (typeof code === 'string' && TRANSIENT_CONNECT_ERRORS.has(code)) {
    return true;
  }
  return error.message.startsWith('Connection terminated');
}

/**
 * Wraps a Pool so that *acquiring* a connection is retried, while the SQL that
 * follows is not.
 *
 * That boundary is the point. Neon suspends an idle compute, and the first
 * connection attempt after a wake can be reset mid-handshake (observed:
 * `read ECONNRESET` on a cold pool). Retrying there is free of side effects
 * because no statement has reached the server yet. Retrying a query that was
 * already dispatched is a different matter — the server may have applied a
 * write and lost only the reply, so a retry could duplicate it. This never
 * does that.
 *
 * `pool.query()` internally calls `this.connect(...)`, and because the adapter
 * holds this proxy, that internal call resolves through the trap too — so
 * plain queries and transactions both get the retry, and neither gets its
 * statements re-sent.
 */
export function withConnectRetry(pool: Pool, logger: Logger): Pool {
  const MAX_ATTEMPTS = 3;
  const RETRY_DELAY_MS = 250;

  const acquire = async (): Promise<PoolClient> => {
    for (let attempt = 1; ; attempt++) {
      try {
        return await pool.connect();
      } catch (error) {
        if (attempt >= MAX_ATTEMPTS || !isTransientConnectError(error)) throw error;
        logger.warn(
          `Database connection attempt ${attempt}/${MAX_ATTEMPTS} was dropped (${
            error instanceof Error ? error.message : String(error)
          }); retrying.`,
        );
        await sleep(RETRY_DELAY_MS * attempt);
      }
    }
  };

  return new Proxy(pool, {
    get(target, prop) {
      if (prop !== 'connect') {
        // Read against `target` so getters (idleCount, totalCount, ...) run on
        // the real pool. Methods come back unbound either way, so when they are
        // invoked on this proxy their internal `this.connect(...)` is trapped.
        return Reflect.get(target, prop, target);
      }
      return function connect(
        cb?: (err?: Error, client?: PoolClient, release?: (err?: Error) => void) => void,
      ) {
        if (typeof cb !== 'function') return acquire();
        acquire().then(
          (client) => cb(undefined, client, client.release.bind(client)),
          (error: Error) => cb(error, undefined, () => {}),
        );
        return undefined;
      };
    },
  });
}

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
    // We construct the pg.Pool explicitly (rather than letting PrismaPg build
    // it internally) so we can tune pool sizing for a high-latency managed
    // Postgres (Neon) — see the min / idleTimeoutMillis rationale below.
    const pool = new Pool({
      ...poolConfig,
      // Without a timeout, a query that can't get a pooled connection (pool
      // exhausted by a leaked/idle-in-transaction session) or that's stuck
      // behind a row lock would wait indefinitely with no error — the "hangs
      // forever, no crash" symptom. Both now fail fast with a clear Postgres
      // error instead of hanging past Dio's client-side timeout.
      connectionTimeoutMillis: 10_000,
      statement_timeout: 10_000,
      // node-postgres defaults to idleTimeoutMillis: 10_000 with no minimum
      // pool size, so it destroys every idle client 10s after the last query
      // and reopens a fresh TCP+TLS connection on the next one. Real usage
      // never fires requests faster than 10s apart — a user takes tens of
      // seconds to fill in a registration step — so in practice almost every
      // request paid that reconnect cost, which is where the reported 5+s
      // "Continue" delay came from. We therefore hold idle connections open
      // for a while, but strictly less time than the server will tolerate.
      //
      // `min` MUST stay 0. pg-pool only arms the idle timer when the pool is
      // above `min` (`if (idleTimeoutMillis && this._isAboveMin())`), so
      // `min: 1` meant the last connection got no idle timer at all and was
      // held open FOREVER. Whenever that socket then died — a laptop
      // suspending, a network change, a server-side restart — the pool never
      // learned, and handed the dead socket to the next request, which failed
      // with "Connection terminated unexpectedly". Bounding the idle time is
      // what fixes that; the exact bound is a latency trade.
      //
      // 4 minutes, chosen from measurement rather than taste. A pooled
      // connection here survives at least 30 minutes idle (tested: 135ms after
      // 900s, 240ms after 1800s), while reconnecting after a long quiet spell
      // costs ~850ms, so closing too eagerly makes the first request after
      // every lull noticeably slower. Four minutes keeps the connection warm
      // across an ordinary pause in activity, still lets go well inside the
      // conventional five-minute serverless suspend window, and never lets a
      // connection sit unbounded again.
      min: 0,
      idleTimeoutMillis: 240_000,
      // Backstop for a connection that stays busy enough to dodge the idle
      // timer but goes stale behind Neon's pooler: recycle it every 30min.
      maxLifetimeSeconds: 1_800,
      // TCP keepalives so an idle-but-not-yet-expired connection is not
      // silently dropped by NAT//firewall on the long path to the region.
      keepAlive: true,
      keepAliveInitialDelayMillis: 10_000,
    });
    const resilientPool = withConnectRetry(pool, new Logger(PrismaService.name));
    super({
      adapter: new PrismaPg(resilientPool),
      // Prisma's defaults (maxWait 2s, timeout 5s) are too tight for a managed
      // Postgres reached over the public internet, and the failure is
      // deterministic rather than flaky: opening a fresh connection to Neon
      // from here measures 2.4-2.6s (5 samples: 2575/2415/2473/2471/2428 ms),
      // every one of them over the 2s budget. `min: 1` above keeps exactly one
      // connection warm, so the moment two requests overlap the second must
      // open a new one — and any $transaction on that path fails with P2028
      // "Unable to start a transaction in the given time" before the
      // connection is even ready. It was reproduced on message send.
      //
      // maxWait sits deliberately ABOVE the pool's connectionTimeoutMillis
      // (10s) so the pool's own, more specific error surfaces instead of
      // Prisma giving up first on a connection that was still coming.
      transactionOptions: {
        maxWait: 12_000,
        timeout: 15_000,
      },
      log: [
        { emit: 'stdout', level: 'warn' },
        { emit: 'stdout', level: 'error' },
      ],
    });

    // pg-pool reports a *background* failure (an idle client whose socket the
    // server closed) by `pool.emit('error', ...)`. EventEmitter throws when
    // 'error' has no listener, so without this a routine Neon suspend would
    // surface as an uncaught exception and take the process down rather than
    // discarding one connection. The client is already removed from the pool
    // by the time this fires, so logging is the correct response.
    pool.on('error', (error: Error) => {
      this.logger.warn(
        `Idle database connection dropped (${error.message}); it has been discarded from the pool.`,
      );
    });
  }

  // Managed Postgres (Neon) auto-suspends an idle compute; waking it can
  // intermittently exceed a single connection attempt's window (observed:
  // "Connection terminated due to connection timeout" on a cold start that
  // succeeds a moment later). Without a retry, that one transient blip took
  // the whole app down at boot. 4 attempts with linear backoff (2s/4s/6s)
  // rides out the wake-up; a genuinely misconfigured DB still fails fast
  // after ~12s instead of hanging indefinitely.
  private static readonly CONNECT_MAX_ATTEMPTS = 4;
  private static readonly CONNECT_RETRY_DELAY_MS = 2_000;

  async onModuleInit(): Promise<void> {
    // $connect() alone does not verify real connectivity with the driver-adapter
    // + query-compiler engine used here: it resolves successfully even with no
    // database reachable at all. A real query is the only reliable liveness check.
    await this.$connect();

    const start = Date.now();
    await this.queryWithRetry();

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

  private async queryWithRetry(): Promise<void> {
    for (let attempt = 1; attempt <= PrismaService.CONNECT_MAX_ATTEMPTS; attempt++) {
      try {
        await this.$queryRaw`SELECT 1`;
        return;
      } catch (error) {
        if (attempt === PrismaService.CONNECT_MAX_ATTEMPTS) {
          this.logger.error(
            `Database connection failed: ${this.describeConnectionError(error)}`,
          );
          throw error;
        }
        this.logger.warn(
          `Database connection attempt ${attempt}/${PrismaService.CONNECT_MAX_ATTEMPTS} failed, retrying: ${this.describeConnectionError(error)}`,
        );
        await sleep(PrismaService.CONNECT_RETRY_DELAY_MS * attempt);
      }
    }
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
