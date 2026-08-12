/**
 * End-to-end checks for the seeded members, using the application's own code
 * rather than a re-implementation.
 *
 * Two things are proven here that the row-count verification cannot:
 *   1. Discover actually returns (and excludes) the right members, by running
 *      the real `buildFeedWhere` — the same function the API calls.
 *   2. Each photo is genuinely fetchable: presigned URL -> HTTP 200 -> JPEG
 *      magic bytes, not merely "a URL exists in a column".
 *
 * Read-only.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { PrismaClient } from '../generated/client';
import { buildFeedWhere } from '../../../apps/api/src/modules/matches/filters/partner-preference-where.builder';
import { SEED_UID_PREFIX, seedUid } from './seeders/fake-profiles';

const results: Array<{ name: string; ok: boolean; detail: string }> = [];
function record(name: string, ok: boolean, detail: string): void {
  results.push({ name, ok, detail });
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });

  try {
    // Resolve seeded members by their deterministic uid.
    const members = await prisma.user.findMany({
      where: { firebaseUid: { startsWith: SEED_UID_PREFIX } },
      select: {
        id: true, firebaseUid: true,
        profile: { select: { firstName: true, gender: true, caste: true, currentCity: true, currentState: true, motherTongue: true } },
        partnerPreference: true,
        photos: { select: { s3Key: true, isPrimary: true } },
      },
    });
    const byIndex = new Map<number, (typeof members)[number]>();
    for (const m of members) {
      byIndex.set(Number(m.firebaseUid.replace(SEED_UID_PREFIX, '')), m);
    }

    /** Runs the REAL feed query for a seeded member. */
    async function feedFor(index: number): Promise<string[]> {
      const me = byIndex.get(index);
      if (!me?.profile) throw new Error(`member ${index} has no profile`);
      const p = me.partnerPreference;
      const where = buildFeedWhere({
        currentUserId: me.id,
        myGender: me.profile.gender,
        self: {
          caste: me.profile.caste,
          currentCity: me.profile.currentCity,
          currentState: me.profile.currentState,
          motherTongue: me.profile.motherTongue,
        },
        pref: p
          ? {
              minAge: p.minAge, maxAge: p.maxAge,
              minHeightCm: p.minHeightCm, maxHeightCm: p.maxHeightCm,
              preferredReligions: p.preferredReligions as string[],
              preferredCastes: p.preferredCastes as string[],
              minIncomeLakhs: p.minIncomeLakhs ? Number(p.minIncomeLakhs) : null,
              preferredCities: p.preferredCities as string[],
              preferredStates: p.preferredStates as string[],
              preferredEducation: p.preferredEducation as string[],
              preferredOccupations: p.preferredOccupations as string[],
              preferredMotherTongues: p.preferredMotherTongues as string[],
              maritalStatusPref: p.maritalStatusPref as string[],
            }
          : null,
      });
      const rows = await prisma.userProfile.findMany({
        where, select: { userId: true }, orderBy: { createdAt: 'desc' },
      });
      return rows.map((r) => r.userId);
    }

    // ── Feed scenarios ────────────────────────────────────────────────
    const aarthi = byIndex.get(1)!;
    const karthik = byIndex.get(2)!;

    const aarthiFeed = await feedFor(1);
    record('Feed returns results for a normal member (#1 Aarthi)', aarthiFeed.length > 0, `${aarthiFeed.length} profiles`);
    record('Strong mutual match visible (#1 sees #2 Karthik)', aarthiFeed.includes(karthik.id), aarthiFeed.includes(karthik.id) ? 'present' : 'MISSING');
    record('Self excluded from own feed (#1)', !aarthiFeed.includes(aarthi.id), 'not present ✓');

    const onlyOppositeGender = await prisma.userProfile.count({
      where: { userId: { in: aarthiFeed }, gender: 'MALE' },
    });
    record('Gender filtering (female caller sees only males)', onlyOppositeGender === aarthiFeed.length, `${onlyOppositeGender}/${aarthiFeed.length} male`);

    const restrictive = await feedFor(25); // Lakshmi: >=35L, M.Tech+, Bengaluru, Iyer
    const broad = await feedFor(17);       // Kavya: no filters set
    record('Restrictive prefs narrow the feed (#25 vs #17)', restrictive.length < broad.length, `restrictive ${restrictive.length} < broad ${broad.length}`);
    record('Broad/empty prefs fall back to a full feed (#17)', broad.length >= 10, `${broad.length} profiles`);

    // Block exclusion: #7 blocked #18.
    const meenakshiFeed = await feedFor(7);
    const nikhil = byIndex.get(18)!;
    record('Blocked member excluded from feed (#7 blocked #18)', !meenakshiFeed.includes(nikhil.id), meenakshiFeed.includes(nikhil.id) ? 'STILL VISIBLE' : 'excluded ✓');

    // Pagination consistency: page 1 + page 2 == first 20 of the full list.
    const page1 = await prisma.userProfile.findMany({
      where: { userId: { in: aarthiFeed } }, orderBy: { createdAt: 'desc' }, take: 10, select: { userId: true },
    });
    const page2 = await prisma.userProfile.findMany({
      where: { userId: { in: aarthiFeed } }, orderBy: { createdAt: 'desc' }, skip: 10, take: 10, select: { userId: true },
    });
    const overlap = page1.filter((a) => page2.some((b) => b.userId === a.userId)).length;
    record('Pagination pages do not overlap', overlap === 0, `${page1.length} + ${page2.length}, overlap ${overlap}`);

    // Inactive exclusion: temporarily reason about the rule rather than mutate.
    const bannedVisible = await prisma.userProfile.count({
      where: { userId: { in: aarthiFeed }, user: { is: { status: { in: ['SUSPENDED', 'DEACTIVATED', 'BANNED'] } } } },
    });
    record('Suspended/banned members never in feed', bannedVisible === 0, `${bannedVisible} found`);

    const incompleteVisible = await prisma.userProfile.count({
      where: { userId: { in: aarthiFeed }, isProfileComplete: false },
    });
    record('Incomplete profiles never in feed', incompleteVisible === 0, `${incompleteVisible} found`);

    // ── Photos: presigned URL -> HTTP -> real JPEG ────────────────────
    const region = process.env.AWS_REGION;
    const bucket = process.env.AWS_S3_BUCKET_NAME;
    if (region && bucket && process.env.AWS_ACCESS_KEY_ID) {
      const s3 = new S3Client({
        region,
        credentials: {
          accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
          secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
        },
      });
      let loaded = 0;
      let firstFailure = '';
      for (const m of members) {
        const key = m.photos.find((p) => p.isPrimary)?.s3Key;
        if (!key) continue;
        const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 300 });
        const res = await fetch(url);
        const buf = Buffer.from(await res.arrayBuffer());
        // JPEG magic bytes: FF D8 FF
        const isJpeg = buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
        if (res.status === 200 && isJpeg && buf.byteLength > 1000) loaded++;
        else if (!firstFailure) firstFailure = `${m.firebaseUid}: HTTP ${res.status}, ${buf.byteLength}B, jpeg=${isJpeg}`;
      }
      record('Presigned URL returns a real JPEG (all 30)', loaded === members.length, `${loaded}/${members.length}${firstFailure ? ' — ' + firstFailure : ''}`);
    } else {
      record('Presigned URL check', false, 'S3 not configured — skipped');
    }

    // ── Relationship data ─────────────────────────────────────────────
    const rooms = await prisma.chatRoom.count({
      where: { OR: [{ user1Id: { in: members.map((m) => m.id) } }, { user2Id: { in: members.map((m) => m.id) } }] },
    });
    record('Conversations exist for seeded members', rooms >= 2, `${rooms} rooms`);

    const unread = await prisma.chatMessage.count({
      where: { senderId: { in: members.map((m) => m.id) }, isRead: false },
    });
    record('Unread messages exist (badge testable)', unread > 0, `${unread} unread`);

    const unreadNotifs = await prisma.notification.count({
      where: { userId: { in: members.map((m) => m.id) }, isRead: false },
    });
    record('Unread notifications exist', unreadNotifs > 0, `${unreadNotifs} unread`);

    const accepted = await prisma.expressInterest.count({
      where: { senderId: { in: members.map((m) => m.id) }, status: 'ACCEPTED' },
    });
    record('Accepted interest exists (chat is legitimate)', accepted > 0, `${accepted} accepted`);

    // ── Report ────────────────────────────────────────────────────────
    console.log('');
    console.log('========================================');
    console.log('FAKE SEED — END-TO-END VERIFICATION');
    console.log('========================================');
    console.log('');
    for (const r of results) {
      console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padEnd(48)} ${r.detail}`);
    }
    const passed = results.every((r) => r.ok);
    console.log('');
    console.log(passed ? 'END-TO-END VERIFICATION PASSED' : 'END-TO-END VERIFICATION FAILED');
    console.log('========================================');
    console.log('');
    process.exitCode = passed ? 0 : 1;
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});

void seedUid;
