/**
 * Entrypoint for `pnpm seed:fake`.
 *
 * Guarded, idempotent, and reversible with `pnpm unseed:fake`.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import { resolve } from 'node:path';

// Same precedence as AppConfigModule / prisma.config.ts.
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { seedFakeProfiles } from './seeders/fake-profiles';
import { readStorageConfig } from './seeders/fake-profiles/fake-photos';
import { assertFakeSeedAllowed, FakeSeedBlockedError } from './seeders/fake-profiles/seed-guard';

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  const target = assertFakeSeedAllowed(databaseUrl);

  console.log('');
  console.log('========================================');
  console.log('FAKE PROFILE SEED');
  console.log('========================================');
  console.log(`Target : ${target.host} [${target.region}]`);
  console.log('');

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl! }),
  });

  // The photos live at the repository root, one level above `backend/`.
  const photosDir = resolve(process.cwd(), '..', 'photos');
  const storage = readStorageConfig(photosDir);

  try {
    const report = await seedFakeProfiles(prisma, storage);
    console.log('');
    console.log('----------------------------------------');
    console.log(`Users               ${report.users}`);
    console.log(`Profiles            ${report.profiles}`);
    console.log(`Preferences         ${report.preferences}`);
    console.log(`Registration steps  ${report.registrationSteps}`);
    console.log(`Settings            ${report.settings}`);
    console.log(
      `Photos              ${report.photos}` +
        (report.photos
          ? ` (${report.photosUploaded} uploaded, ${report.photosAlreadyPresent} already in S3)`
          : ' — S3 not configured'),
    );
    console.log(`Interests           ${report.interests}`);
    console.log(`Shortlists          ${report.shortlists}`);
    console.log(`Blocks              ${report.blocks}`);
    console.log(`Reports             ${report.reports}`);
    console.log(`Conversations       ${report.conversations}`);
    console.log(`Messages            ${report.messages}`);
    console.log(`Notifications       ${report.notifications}`);
    console.log('----------------------------------------');
    console.log('');
    console.log('Seed complete. Verify with:  pnpm verify:fake-seed');
    console.log('Remove again with:           ALLOW_FAKE_SEED=true pnpm unseed:fake');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  if (error instanceof FakeSeedBlockedError) {
    console.error('');
    console.error('REFUSING TO SEED');
    console.error('========================================');
    console.error(error.message);
    console.error('');
    process.exit(2);
  }
  console.error(error);
  process.exit(1);
});
