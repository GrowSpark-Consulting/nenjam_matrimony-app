/**
 * Entrypoint for `pnpm seed:locations`.
 *
 * Safe to run against any environment including production: idempotent,
 * additive, and confined to the three location master tables. It does not
 * read or write user_profiles, so no member's stored location can change.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import { resolve } from 'node:path';

// Same precedence as AppConfigModule / prisma.config.ts.
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { seedLocations, SEED_DATA_DIR } from './seeders/locations';
import { describeTarget } from './seeders/fake-profiles/seed-guard';

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const target = describeTarget(databaseUrl);

  console.log('');
  console.log('========================================');
  console.log('LOCATION MASTER DATA SEED');
  console.log('========================================');
  console.log(`Target : ${target.host} [${target.region}]`);
  console.log('');

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl }),
  });

  try {
    const started = Date.now();
    const report = await seedLocations(prisma, resolve(process.cwd(), SEED_DATA_DIR));
    const seconds = ((Date.now() - started) / 1000).toFixed(1);

    console.log('----------------------------------------');
    console.log(`Countries     ${report.countries}`);
    console.log(`Subdivisions  ${report.subdivisions}`);
    console.log(`Cities        ${report.cities}`);
    if (report.deactivated > 0) {
      console.log(`Deactivated   ${report.deactivated} (no longer in the dataset; not deleted)`);
    }
    console.log(`Dataset       ${report.checksum}`);
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
  console.error('LOCATION SEED FAILED');
  console.error('========================================');
  console.error(error instanceof Error ? error.message : error);
  console.error('');
  process.exit(1);
});
