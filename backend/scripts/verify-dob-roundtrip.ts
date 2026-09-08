/**
 * End-to-end verification of one date of birth, against the real database.
 *
 *   pnpm ts-node -r tsconfig-paths/register scripts/verify-dob-roundtrip.ts
 *
 * Walks the exact production path for a single profile:
 *
 *   Flutter body {"dob":"1998-08-15"}
 *     -> BasicDetailsDto + ValidationPipe (transform + class-validator)
 *     -> ProfileService's parseBirthDate()
 *     -> Prisma write into user_profiles.dob / astrology_profiles.birth_date
 *     -> read back
 *     -> Date.toISOString(), which is how GET /profiles/me serializes it
 *     -> the calendar date the Flutter client parses back out
 *
 * Every step uses the real module, not a reimplementation: the DTO is the one
 * the controller binds, and parseBirthDate is the one writeProfileFromDraft
 * calls.
 *
 * ## Everything happens inside a transaction that is ROLLED BACK
 *
 * The profile is created, read back, asserted on, and then the transaction is
 * aborted, so not one row survives. That is deliberate and it is not a weaker
 * test: the value Postgres hands back inside the transaction is the value it
 * stored, and `timestamp(3)` does not round-trip differently after a commit.
 *
 * What it avoids is real: `user_profiles` rows with `isProfileComplete = true`
 * enter the Discover feed and the matching engine, so a committed test profile
 * would be a fabricated person shown to real members. Rolling back gets the
 * verification without putting one there, and needs no cleanup pass to undo.
 *
 * Pass --commit to keep the row instead. Nothing else changes; the profile is
 * written with `isProfileComplete = false` either way so it can never enter
 * the feed.
 *
 * ## It never touches an existing row
 *
 * Only INSERTs, only for the ids it generates. No UPDATE, no DELETE, and no
 * statement that can reach a row it did not create.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { randomUUID } from 'crypto';
import { PrismaClient } from '../libs/database/generated/client';
import { BasicDetailsDto } from '../apps/api/src/modules/profiles/dto/basic-details.dto';
import {
  latestAllowedBirthDate,
  parseBirthDate,
} from '../apps/api/src/modules/profiles/validation/birth-date';

config({ path: '.env' });
config({ path: '.env.local', override: true });

const COMMIT = process.argv.includes('--commit');

/** The date a member types as 15 / 08 / 1998. */
const TYPED_DOB = '1998-08-15';

const ok = (label: string, pass: boolean, detail: string) => {
  console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${label}`);
  if (detail) console.log(`        ${detail}`);
  if (!pass) process.exitCode = 1;
  return pass;
};

/** Runs the DTO exactly as the global ValidationPipe does. */
async function throughDto(dob: unknown) {
  const dto = plainToInstance(BasicDetailsDto, {
    firstName: 'Dob',
    lastName: 'Roundtrip',
    gender: 'MALE',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Myself',
    dob,
  });
  return { dto, errors: await validate(dto) };
}

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('DATABASE_URL is not set');
  const host = url.replace(/^.*@/, '').replace(/[/?].*$/, '');

  console.log('='.repeat(72));
  console.log('DOB round-trip verification');
  console.log('='.repeat(72));
  console.log(`database host : ${host}`);
  console.log(`mode          : ${COMMIT ? 'COMMIT (row persists)' : 'ROLLBACK (nothing persists)'}`);
  console.log('');

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: url }),
  });
  await prisma.$connect();

  // ── 1. Request validation ────────────────────────────────────────
  console.log('--- 1. API request: PATCH /profiles/draft/basic-details ---');
  const body = { dob: TYPED_DOB };
  console.log(`  request body  : ${JSON.stringify(body)}`);

  const { dto, errors } = await throughDto(TYPED_DOB);
  ok('DTO accepts the date-only body', errors.length === 0,
     `validation errors: ${errors.length}`);
  ok('value stored on the DTO is date-only', dto.dob === TYPED_DOB,
     `dto.dob = ${JSON.stringify(dto.dob)}`);

  // ── 2. Rejections (no database involved) ─────────────────────────
  console.log('');
  console.log('--- 2. Rejections ---');
  const dayUnder21 = new Date(latestAllowedBirthDate(new Date()));
  dayUnder21.setUTCDate(dayUnder21.getUTCDate() + 1);
  const exactly21 = latestAllowedBirthDate(new Date()).toISOString().slice(0, 10);

  for (const [label, value] of [
    ['impossible 2003-02-29', '2003-02-29'],
    ['impossible 1998-02-31', '1998-02-31'],
    ['malformed 15/08/1998', '15/08/1998'],
    ['future date', `${new Date().getUTCFullYear() + 1}-08-15`],
    ['one day under 21', dayUnder21.toISOString().slice(0, 10)],
  ] as const) {
    const r = await throughDto(value);
    ok(`rejected: ${label}`, r.errors.length === 1,
       `message: ${r.errors[0]?.constraints?.isBirthDate ?? '(none)'}`);
  }
  const boundary = await throughDto(exactly21);
  ok(`accepted: exactly 21 today (${exactly21})`, boundary.errors.length === 0, '');

  // ── 3/4. Write, read back, serialize ─────────────────────────────
  console.log('');
  console.log('--- 3. Database write + 4. reload ---');

  const userId = `dobcheck-${randomUUID()}`;
  // Assigned inside the transaction callback; TypeScript cannot see that, so
  // it is read back through an explicit cast below.
  let observed: Observed | null = null;

  try {
    await prisma.$transaction(async (tx) => {
      await tx.user.create({
        data: {
          id: userId,
          firebaseUid: `fb-${userId}`,
          email: `${userId}@verify.invalid`,
        },
      });

      // Exactly what writeProfileFromDraft passes.
      const dob = parseBirthDate(dto.dob);
      if (!dob) throw new Error('parseBirthDate returned null');

      await tx.userProfile.create({
        data: {
          user: { connect: { id: userId } },
          firstName: 'Dob',
          lastName: 'Roundtrip',
          dob,
          gender: 'MALE',
          maritalStatus: 'NEVER_MARRIED',
          religion: 'Hindu',
          currentState: 'Tamil Nadu',
          currentCity: 'Chennai',
          // Never true: a complete profile enters the Discover feed.
          isProfileComplete: false,
          profileCompletePct: 0,
        },
      });
      await tx.astrologyProfile.create({
        data: { user: { connect: { id: userId } }, birthDate: dob },
      });

      // The raw column value, as Postgres itself renders it.
      const rawRows = await tx.$queryRawUnsafe<Array<{ t: string }>>(
        `SELECT "dob"::text AS t FROM "user_profiles" WHERE "user_id" = $1`,
        userId,
      );
      const reloaded = await tx.userProfile.findUniqueOrThrow({
        where: { userId },
      });
      const astro = await tx.astrologyProfile.findUniqueOrThrow({
        where: { userId },
      });

      observed = {
        raw: rawRows[0].t,
        iso: reloaded.dob.toISOString(),
        reload: reloaded.dob.toISOString().slice(0, 10),
        astro: astro.birthDate.toISOString(),
      };

      if (!COMMIT) throw new RollbackSignal();
    });
  } catch (error) {
    if (!(error instanceof RollbackSignal)) throw error;
  }

  const seen = observed as unknown as Observed | null;
  if (!seen) throw new Error('no observation captured');

  console.log(`  raw column value        : ${seen.raw}`);
  console.log(`  Date.toISOString()      : ${seen.iso}`);
  console.log(`  astrology birth_date    : ${seen.astro}`);
  console.log('');
  ok('stored as UTC midnight of the typed day', seen.iso === `${TYPED_DOB}T00:00:00.000Z`,
     `expected ${TYPED_DOB}T00:00:00.000Z`);
  ok('raw column carries no time component', seen.raw.endsWith(' 00:00:00'),
     `raw = ${seen.raw}`);
  ok('reload returns the same calendar date', seen.reload === TYPED_DOB,
     `reloaded ${seen.reload}, typed ${TYPED_DOB}`);
  ok('user_profiles.dob === astrology_profiles.birth_date', seen.astro === seen.iso, '');

  // ── 5. API response shape, and what Flutter parses back ──────────
  console.log('');
  console.log('--- 5. API response: GET /profiles/me ---');
  const responseBody = { dob: seen.iso };
  console.log(`  response body : ${JSON.stringify(responseBody)}`);
  // birthDateFromWire in Frontend/lib/core/utils/birth_date.dart reads the
  // leading calendar date and applies no timezone conversion.
  const flutterReads = /^(\d{4})-(\d{2})-(\d{2})/.exec(responseBody.dob);
  const displayed = flutterReads
    ? `${flutterReads[3]} / ${flutterReads[2]} / ${flutterReads[1]}`
    : '(unparseable)';
  console.log(`  Flutter shows : ${displayed}`);
  ok('Flutter renders the day that was typed', displayed === '15 / 08 / 1998', '');

  // ── Residue check ────────────────────────────────────────────────
  console.log('');
  console.log('--- residue ---');
  const survivors = await prisma.userProfile.count({ where: { userId } });
  if (COMMIT) {
    ok('row persisted, as requested by --commit', survivors === 1,
       `user_id = ${userId}`);
  } else {
    ok('transaction rolled back, nothing persisted', survivors === 0,
       `rows remaining for ${userId}: ${survivors}`);
  }

  await prisma.$disconnect();
  console.log('');
  console.log(process.exitCode ? 'RESULT: FAILURES ABOVE' : 'RESULT: all checks passed');
}

/** What the database handed back, at each layer of the round trip. */
interface Observed {
  /** `dob::text` - the column value as Postgres itself renders it. */
  raw: string;
  /** `Date.toISOString()` - how GET /profiles/me serializes it. */
  iso: string;
  /** The calendar date half of [iso]. */
  reload: string;
  /** astrology_profiles.birth_date, which must equal [iso]. */
  astro: string;
}

/** Aborts the interactive transaction without signalling a real failure. */
class RollbackSignal extends Error {
  constructor() {
    super('intentional rollback');
  }
}

void main().catch((e) => {
  console.error(e);
  process.exit(1);
});
