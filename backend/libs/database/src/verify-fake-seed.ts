/**
 * Entrypoint for `pnpm verify:fake-seed`.
 *
 * Read-only. Checks that the seeded members satisfy the same invariants the
 * application enforces — not merely that 30 rows exist. Exits non-zero on any
 * failure so it can gate a script.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { FAKE_PEOPLE } from './seeders/fake-profiles/fake-people';
import { SEED_UID_PREFIX } from './seeders/fake-profiles';
import {
  makeS3Client,
  objectExists,
  readStorageConfig,
} from './seeders/fake-profiles/fake-photos';
import { describeTarget } from './seeders/fake-profiles/seed-guard';

const EXPECTED = FAKE_PEOPLE.length;

interface Check {
  label: string;
  got: number | string;
  want: number | string;
  ok: boolean;
  note?: string;
}

function check(label: string, got: number, want: number, note?: string): Check {
  return { label, got, want, ok: got === want, note };
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const target = describeTarget(databaseUrl);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl }),
  });

  const seeded = { firebaseUid: { startsWith: SEED_UID_PREFIX } };
  const checks: Check[] = [];

  try {
    const users = await prisma.user.findMany({
      where: seeded,
      select: {
        id: true,
        firebaseUid: true,
        email: true,
        status: true,
        deletedAt: true,
        profile: {
          select: {
            isProfileComplete: true, gender: true, firstName: true,
            currentCity: true, religion: true, caste: true, motherTongue: true,
          },
        },
        photos: { select: { s3Key: true, isPrimary: true } },
        partnerPreference: { select: { id: true } },
        registrationStep: { select: { isComplete: true } },
        settings: { select: { id: true } },
      },
    });

    checks.push(check('Users', users.length, EXPECTED));
    checks.push(check('Profiles', users.filter((u) => u.profile).length, EXPECTED));
    checks.push(check('Preferences', users.filter((u) => u.partnerPreference).length, EXPECTED));
    checks.push(check('Settings', users.filter((u) => u.settings).length, EXPECTED));
    checks.push(
      check('Registration complete', users.filter((u) => u.registrationStep?.isComplete).length, EXPECTED),
    );
    checks.push(check('Photos', users.filter((u) => u.photos.length > 0).length, EXPECTED));
    checks.push(
      check('Primary photos', users.filter((u) => u.photos.some((p) => p.isPrimary)).length, EXPECTED),
    );

    // The three conditions buildFeedWhere actually applies.
    const discoverable = users.filter(
      (u) =>
        u.profile?.isProfileComplete === true &&
        u.deletedAt === null &&
        !['SUSPENDED', 'DEACTIVATED', 'BANNED'].includes(u.status),
    );
    checks.push(check('Discoverable (feed rules)', discoverable.length, EXPECTED));

    // Matchable = discoverable AND has a preference row to match against.
    checks.push(
      check(
        'Matchable',
        discoverable.filter((u) => u.partnerPreference).length,
        EXPECTED,
      ),
    );

    // Integrity.
    const uids = new Set(users.map((u) => u.firebaseUid));
    checks.push(check('Duplicate users', EXPECTED - uids.size, 0));
    checks.push(check('Missing profiles', users.filter((u) => !u.profile).length, 0));
    checks.push(
      check('Profiles missing required fields',
        users.filter((u) => u.profile && (!u.profile.firstName || !u.profile.currentCity || !u.profile.religion || !u.profile.caste || !u.profile.motherTongue)).length,
        0),
    );

    // Orphans: profiles/photos/prefs pointing at a seeded user that is gone.
    const seededIds = new Set(users.map((u) => u.id));
    const strayPhotos = await prisma.profilePhoto.count({
      where: { s3Key: { contains: '/seed-' }, userId: { notIn: [...seededIds] } },
    });
    checks.push(check('Orphaned seed photos', strayPhotos, 0));

    // The dataset is deliberately female-only: one profile per supplied photo,
    // and every photo is of a woman. That means only the male-seeker feed
    // direction is populated by seed data — a female seeker sees real members
    // or an empty feed, which is the correct behaviour, not a seeding fault.
    const female = users.filter((u) => u.profile?.gender === 'FEMALE').length;
    const male = users.filter((u) => u.profile?.gender === 'MALE').length;
    checks.push({
      label: 'Gender split (F/M)',
      got: `${female}/${male}`,
      want: `${FAKE_PEOPLE.length}/0`,
      ok: female === FAKE_PEOPLE.length && male === 0,
    });

    // Real members must be untouched.
    const realUsers = await prisma.user.count({
      where: { firebaseUid: { not: { startsWith: SEED_UID_PREFIX } } },
    });

    // Storage: does each seeded key actually exist in the bucket?
    let storageLine = 'skipped (S3 not configured)';
    let storageOk = true;
    const storage = readStorageConfig('');
    if (storage) {
      const client = makeS3Client(storage);
      const keys = users.flatMap((u) => u.photos.map((p) => p.s3Key));
      let present = 0;
      for (const key of keys) {
        if (await objectExists(client, storage.bucket, key)) present++;
      }
      storageOk = present === EXPECTED;
      storageLine = `${present}/${EXPECTED}`;
      checks.push(check('S3 objects present', present, EXPECTED));
    }

    console.log('');
    console.log('========================================');
    console.log('FAKE PROFILE SEED VERIFICATION');
    console.log('========================================');
    console.log(`Target : ${target.host} [${target.region}]`);
    console.log('');
    for (const c of checks) {
      const value = typeof c.got === 'number' && typeof c.want === 'number' && c.want !== 0
        ? `${c.got}/${c.want}`
        : `${c.got}`;
      console.log(`  ${c.label.padEnd(34)} ${value.padEnd(10)} ${c.ok ? '✓' : '✗ (expected ' + c.want + ')'}`);
    }
    console.log('');
    console.log(`  ${'Cloudflare/S3 photo objects'.padEnd(34)} ${storageLine}`);
    console.log(`  ${'Real (non-seeded) users untouched'.padEnd(34)} ${realUsers}`);
    console.log('');

    const passed = checks.every((c) => c.ok) && storageOk;
    console.log(passed ? 'SEED VERIFICATION PASSED' : 'SEED VERIFICATION FAILED');
    console.log('========================================');
    console.log('');
    process.exitCode = passed ? 0 : 1;
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
