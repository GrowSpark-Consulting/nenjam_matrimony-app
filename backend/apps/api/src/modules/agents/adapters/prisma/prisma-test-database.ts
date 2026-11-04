/**
 * Test support for the database-gated adapter specs (`*.db-spec.ts`). Never
 * imported by production code.
 *
 * These specs write to a real database, so they only ever run against a
 * throwaway LOCAL Postgres. The URL comes from `AGENT_PRISMA_TEST_DATABASE_URL`;
 * anything but `localhost` / `127.0.0.1` is refused before a connection is
 * opened. The repo's `prisma.config.ts` and `.env` files are never read here.
 *
 * **Isolation.** The URL names a TEMPLATE database that already has every
 * migration applied. It is never connected to by a spec and never written to.
 * Each test (`reset()`) gets its own fresh database created from it
 * (`CREATE DATABASE ... TEMPLATE ...`), and the previous one is dropped. The
 * money tables are append-only and refuse TRUNCATE (see the commission
 * migration), so nothing here empties a table: a spec starts from a clean
 * copy, and the copy is dropped when it is done.
 */
import { PrismaPg } from '@prisma/adapter-pg';
import { Client, Pool } from 'pg';
import { PrismaClient } from '@app/database';

export const TEST_DATABASE_ENV = 'AGENT_PRISMA_TEST_DATABASE_URL';

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1']);

/** The URL with any credentials hidden, safe to print. */
export function maskDatabaseUrl(url: string): string {
  return url.replace(/\/\/[^@/]*@/, '//***@');
}

/**
 * Returns the test database URL, or throws: when the variable is missing
 * (the specs must be asked for explicitly) or when the host is not local.
 */
export function requireLocalTestDatabaseUrl(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const url = env[TEST_DATABASE_ENV];
  if (!url) {
    throw new Error(
      `${TEST_DATABASE_ENV} is not set. These specs need a throwaway LOCAL Postgres with the migrations applied; see docs/agent-program/agent-prisma-db-tests.md.`,
    );
  }
  let host: string;
  try {
    host = new URL(url).hostname;
  } catch {
    throw new Error(`${TEST_DATABASE_ENV} is not a valid URL.`);
  }
  if (!LOCAL_HOSTS.has(host)) {
    throw new Error(
      `REFUSED: ${TEST_DATABASE_ENV} points at host "${host}". Only localhost or 127.0.0.1 is allowed.`,
    );
  }
  return url;
}

/** The same server and credentials, another database. */
export function withDatabase(url: string, database: string): string {
  const parsed = new URL(url);
  parsed.pathname = `/${database}`;
  return parsed.toString();
}

const SAFE_NAME = /^[a-z0-9_]+$/;

export interface TestDatabase {
  /** The client for the CURRENT fresh database; it follows `reset()`. */
  prisma: PrismaClient;
  /** Drops the current database and starts the next test from a clean copy of the template. */
  reset(): Promise<void>;
  /** Drops the current database and disconnects. */
  close(): Promise<void>;
}

const handles = new WeakMap<object, TestDatabase>();

export function openTestDatabase(): TestDatabase {
  const templateUrl = requireLocalTestDatabaseUrl();
  const templateName = decodeURIComponent(
    new URL(templateUrl).pathname.replace(/^\//, ''),
  );
  if (!SAFE_NAME.test(templateName)) {
    throw new Error(
      `${TEST_DATABASE_ENV} must name a database with only lower-case letters, digits and underscores.`,
    );
  }
  // Printed once per suite so the target is always visible in the output.
  console.log(`[agent-db-tests] template: ${maskDatabaseUrl(templateUrl)}`);

  const adminUrl = withDatabase(templateUrl, 'postgres');
  const admin = async (sql: string) => {
    const client = new Client({ connectionString: adminUrl });
    await client.connect();
    try {
      await client.query(sql);
    } finally {
      await client.end();
    }
  };

  let counter = 0;
  let current: { name: string; pool: Pool; prisma: PrismaClient } | null = null;

  const dropCurrent = async () => {
    if (current === null) return;
    const { name, pool, prisma } = current;
    current = null;
    await prisma.$disconnect();
    await pool.end();
    await admin(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
  };

  const create = async () => {
    counter += 1;
    const name = `${templateName}_t${process.pid}_${counter}`;
    if (!SAFE_NAME.test(name)) throw new Error('Unsafe test database name.');
    await admin(`CREATE DATABASE "${name}" TEMPLATE "${templateName}"`);
    const pool = new Pool({
      connectionString: withDatabase(templateUrl, name),
      max: 5,
    });
    current = {
      name,
      pool,
      prisma: new PrismaClient({ adapter: new PrismaPg(pool) }),
    };
  };

  // The spec files hold `prisma` in a constant, so it is a stand-in that
  // always forwards to the current database's client.
  const prisma = new Proxy({} as PrismaClient, {
    get(_target, property) {
      if (current === null) {
        throw new Error(
          'No test database yet: call reset() in beforeEach before using prisma.',
        );
      }
      const value = Reflect.get(current.prisma, property) as unknown;
      if (typeof value !== 'function') return value as never;
      const method = value as (...args: unknown[]) => unknown;
      return method.bind(current.prisma) as never;
    },
  });

  const handle: TestDatabase = {
    prisma,
    reset: async () => {
      await dropCurrent();
      await create();
    },
    close: dropCurrent,
  };
  handles.set(prisma, handle);
  return handle;
}

/**
 * Starts the next test from a clean copy of the template. Call it where a
 * spec used to empty its tables. Never truncates anything.
 */
export async function freshTestDatabase(prisma: PrismaClient): Promise<void> {
  const handle = handles.get(prisma);
  if (!handle) throw new Error('prisma was not made by openTestDatabase().');
  await handle.reset();
}
