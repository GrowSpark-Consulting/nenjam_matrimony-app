/**
 * Entrypoint for `pnpm unseed:fake`.
 *
 * Removes every row this seeder created and nothing else. It exists because
 * the fake members live in the database the whole team shares, so there has to
 * be a clean way back out.
 *
 * Safety: the delete is scoped by `firebaseUid startsWith 'seed-fake-user-'`,
 * a namespace no real Firebase UID can occupy. Profiles, photos, preferences,
 * settings, registration steps, messages, notifications, blocks and reports
 * are all removed by the schema's ON DELETE CASCADE from User, so deleting the
 * users is sufficient — and cannot reach a real member.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import {
  DeleteObjectsCommand,
} from '@aws-sdk/client-s3';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { SEED_UID_PREFIX } from './seeders/fake-profiles';
import { makeS3Client, readStorageConfig } from './seeders/fake-profiles/fake-photos';
import { assertFakeSeedAllowed, FakeSeedBlockedError } from './seeders/fake-profiles/seed-guard';

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  const target = assertFakeSeedAllowed(databaseUrl);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl! }),
  });

  try {
    const users = await prisma.user.findMany({
      where: { firebaseUid: { startsWith: SEED_UID_PREFIX } },
      select: { id: true, photos: { select: { s3Key: true } } },
    });

    console.log('');
    console.log('========================================');
    console.log('FAKE PROFILE UNSEED');
    console.log('========================================');
    console.log(`Target : ${target.host} [${target.region}]`);
    console.log(`Found  : ${users.length} seeded members`);
    console.log('');

    if (users.length === 0) {
      console.log('Nothing to remove.');
      console.log('');
      return;
    }

    // S3 objects first: if this fails we still have the DB rows naming them.
    const keys = users.flatMap((u) => u.photos.map((p) => p.s3Key));
    const storage = readStorageConfig('');
    if (storage && keys.length > 0) {
      const client = makeS3Client(storage);
      await client.send(
        new DeleteObjectsCommand({
          Bucket: storage.bucket,
          Delete: { Objects: keys.map((Key) => ({ Key })) },
        }),
      );
      console.log(`Deleted ${keys.length} S3 objects.`);
    }

    const { count } = await prisma.user.deleteMany({
      where: { firebaseUid: { startsWith: SEED_UID_PREFIX } },
    });

    const remainingReal = await prisma.user.count();
    console.log(`Deleted ${count} seeded members (cascade removed their profiles,`);
    console.log('photos, preferences, settings, messages and notifications).');
    console.log('');
    console.log(`Real users remaining: ${remainingReal}`);
    console.log('========================================');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  if (error instanceof FakeSeedBlockedError) {
    console.error('');
    console.error('REFUSING TO RUN');
    console.error(error.message);
    console.error('');
    process.exit(2);
  }
  console.error(error);
  process.exit(1);
});
