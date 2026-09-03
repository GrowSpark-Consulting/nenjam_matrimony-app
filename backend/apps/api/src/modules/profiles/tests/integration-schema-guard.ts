import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@app/database';

/**
 * Connects an integration spec to its throwaway schema, and refuses to let it
 * touch production.
 *
 * There is a trap here that cost real damage once and must not be repeated.
 * The adapter's `schema` option steers Prisma's **model** queries only.
 * `$queryRaw` / `$executeRaw` ignore it entirely and run on the connection's
 * default `search_path`, which is `public` — where the production tables live.
 * A spec that seeded with raw SQL and asserted with model calls therefore
 * wrote its fixtures into production while reading an empty isolated schema,
 * and the only visible symptom was a foreign-key error that looked like a
 * test bug.
 *
 * So this does two things, and every integration spec must use it:
 *
 *  1. Pins `search_path` on the connection itself, so raw and model queries
 *     land in the same place.
 *  2. Verifies that at runtime — `current_schema()` is asserted to be the
 *     throwaway schema before a single fixture is written. If anything about
 *     the adapter's behaviour changes again, the suite fails loudly instead
 *     of quietly writing to production.
 *
 * Prefer model calls over raw SQL in specs regardless; the guard is the net,
 * not the plan.
 */

export const integrationUrl = process.env.INTEGRATION_DATABASE_URL;
export const integrationSchema = integrationUrl
  ? new URL(integrationUrl).searchParams.get('schema')
  : null;

/**
 * Whether an integration spec may run: a URL is configured, it names a
 * schema, and that schema is not `public`.
 */
export const canRunIntegration =
  Boolean(integrationUrl) &&
  integrationSchema !== null &&
  integrationSchema !== 'public';

/** `describe` when the environment is safe, `describe.skip` otherwise. */
export const describeIntegration = canRunIntegration ? describe : describe.skip;

/**
 * A client pinned to the throwaway schema for BOTH raw and model queries.
 *
 * Throws rather than returning a client if the connection resolves anywhere
 * other than the expected schema — see the class doc for why that check is
 * not paranoia.
 */
export async function connectIsolatedPrisma(): Promise<PrismaClient> {
  if (!canRunIntegration) {
    throw new Error(
      'connectIsolatedPrisma called without a safe INTEGRATION_DATABASE_URL',
    );
  }

  const prisma = new PrismaClient({
    adapter: new PrismaPg(
      {
        connectionString: integrationUrl,
        // The half the adapter's `schema` option does not cover. Without this
        // every raw statement in the spec runs against `public`.
        options: `-c search_path=${integrationSchema}`,
      },
      { schema: integrationSchema! },
    ),
  });
  await prisma.$connect();

  const [{ s }] = await prisma.$queryRawUnsafe<Array<{ s: string }>>(
    'SELECT current_schema() AS s',
  );
  if (s !== integrationSchema) {
    await prisma.$disconnect();
    throw new Error(
      `Refusing to run: raw statements would execute against "${s}", ` +
        `not the isolated schema "${integrationSchema}".`,
    );
  }

  return prisma;
}
