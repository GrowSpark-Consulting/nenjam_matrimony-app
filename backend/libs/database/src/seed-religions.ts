/**
 * Entrypoint for `pnpm seed:religions`.
 *
 * Safe to run against any environment including production: idempotent,
 * additive, and confined to the two religion master tables. It does not read
 * or write user_profiles, so no member's religion or community can change.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import { resolve } from 'node:path';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { seedReligions, RELIGION_SEED_FILE } from './seeders/religions';
import { describeTarget } from './seeders/fake-profiles/seed-guard';

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const target = describeTarget(databaseUrl);

  console.log('');
  console.log('========================================');
  console.log('RELIGION MASTER DATA SEED');
  console.log('========================================');
  console.log(`Target : ${target.host} [${target.region}]`);
  console.log('');

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl }),
  });

  try {
    const started = Date.now();
    const report = await seedReligions(
      prisma,
      resolve(process.cwd(), RELIGION_SEED_FILE),
    );
    const seconds = ((Date.now() - started) / 1000).toFixed(1);

    console.log('----------------------------------------');
    console.log(`Religions     ${report.religions}`);
    console.log(`Communities   ${report.communities}`);
    if (report.deactivated > 0) {
      console.log(`Deactivated   ${report.deactivated} (no longer offered; not deleted)`);
    }
    console.log('----------------------------------------');
    console.log('');
    console.log(
      report.unchanged
        ? `Already up to date — nothing changed (${seconds}s).`
        : `Seed complete in ${seconds}s.`,
    );
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error('');
  console.error('RELIGION SEED FAILED');
  console.error('========================================');
  console.error(error instanceof Error ? error.message : error);
  console.error('');
  process.exit(1);
});
