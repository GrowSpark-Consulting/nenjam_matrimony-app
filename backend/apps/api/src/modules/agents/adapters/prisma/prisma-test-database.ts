/**
 * Test support for the database-gated adapter specs (`*.db-spec.ts`). Never
 * imported by production code.
 *
 * These specs write to, and truncate, a real database, so they only ever run
 * against a throwaway LOCAL Postgres. The URL comes from
 * `AGENT_PRISMA_TEST_DATABASE_URL`; anything but `localhost` / `127.0.0.1`
 * is refused before a connection is opened. The repo's `prisma.config.ts`
 * and `.env` files are never read here.
 */
import { PrismaPg } from '@prisma/adapter-pg';
import { Pool } from 'pg';
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

export interface TestDatabase {
  prisma: PrismaClient;
  close(): Promise<void>;
}

export function openTestDatabase(): TestDatabase {
  const url = requireLocalTestDatabaseUrl();
  // Printed once per suite so the target is always visible in the output.
  console.log(`[agent-db-tests] database: ${maskDatabaseUrl(url)}`);
  const pool = new Pool({ connectionString: url, max: 5 });
  const prisma = new PrismaClient({ adapter: new PrismaPg(pool) });
  return {
    prisma,
    close: async () => {
      await prisma.$disconnect();
      await pool.end();
    },
  };
}

/** Empties the agent tables (plus the test users and the audit rows the specs write). */
export async function truncateAgentTables(prisma: PrismaClient) {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "agents", "referral_codes", "referral_attributions", "agent_refresh_tokens", "agent_payout_details", "agent_applicants", "referral_code_attempts", "users", "audit_logs" CASCADE',
  );
}
