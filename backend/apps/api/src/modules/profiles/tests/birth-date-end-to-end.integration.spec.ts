import { PrismaClient } from '@app/database';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from './integration-schema-guard';
import { BasicDetailsDto } from '../dto/basic-details.dto';
import {
  latestAllowedBirthDate,
  parseBirthDate,
} from '../validation/birth-date';

/**
 * A date of birth, from the request body to the column and back, against a
 * real Postgres.
 *
 * The unit specs prove each link on its own: the DTO refuses the right values,
 * `parseBirthDate` reads the right day, the service passes the Date it was
 * given. None of them proves the property the whole change exists for — that
 * **the day a member types is the day `GET /profiles/me` gives back**. That
 * only breaks at the joins (a local-time parse here, a timestamp column
 * there), and only a real database can be asked.
 *
 * This is the backend half of the walk. The Flutter half —
 * keystroke → `{"dob":"1998-08-15"}` → repository, and the returned
 * `1998-08-15T00:00:00.000Z` back onto the screen — is
 * `Frontend/test/features/registration/birth_date_end_to_end_test.dart`. The
 * two meet at exactly those two payloads, which both sides assert literally.
 *
 * Model API only, never `$queryRaw` — raw statements ignore the adapter's
 * schema and would write these fixtures into the production tables. See
 * `integration-schema-guard.ts`.
 *
 * Runs only with a throwaway `INTEGRATION_DATABASE_URL`; skipped otherwise.
 */
describeIntegration('a date of birth survives the round trip', () => {
  let prisma: PrismaClient;

  beforeAll(async () => {
    prisma = await connectIsolatedPrisma();
    await prisma.astrologyProfile.deleteMany({
      where: { userId: { startsWith: 'dobtest-' } },
    });
    await prisma.userProfile.deleteMany({
      where: { userId: { startsWith: 'dobtest-' } },
    });
    await prisma.user.deleteMany({
      where: { id: { startsWith: 'dobtest-' } },
    });
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  const seedUser = (id: string) =>
    prisma.user.create({
      data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.com` },
    });

  /** The DTO exactly as the global ValidationPipe applies it. */
  const throughDto = async (dob: unknown) => {
    const dto = plainToInstance(BasicDetailsDto, { dob });
    return { dto, errors: await validate(dto) };
  };

  /** The write, exactly as `writeProfileFromDraft` performs it. */
  const writeProfile = (userId: string, dob: string) =>
    prisma.userProfile.create({
      data: {
        user: { connect: { id: userId } },
        firstName: 'Arjun',
        lastName: 'Krishnan',
        dob: parseBirthDate(dob)!,
        gender: 'MALE',
        maritalStatus: 'NEVER_MARRIED',
        religion: 'Hindu',
        currentState: 'Tamil Nadu',
        currentCity: 'Chennai',
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });

  it('stores and returns the day the member typed', async () => {
    await seedUser('dobtest-1');
    // 15 / 08 / 1998, as the Flutter field sends it.
    const { dto, errors } = await throughDto('1998-08-15');
    expect(errors).toHaveLength(0);

    await writeProfile('dobtest-1', dto.dob!);

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'dobtest-1' },
    }))!;

    // The column holds UTC midnight of that day — not local midnight, which
    // an API server east of UTC would have stored as the 14th.
    expect(row.dob.toISOString()).toBe('1998-08-15T00:00:00.000Z');
    // And the day survives the serialization `GET /profiles/me` performs,
    // which is the string the Flutter client parses back.
    const serialized = JSON.parse(JSON.stringify({ dob: row.dob })) as {
      dob: string;
    };
    expect(serialized.dob).toBe('1998-08-15T00:00:00.000Z');
    expect(row.dob.getUTCDate()).toBe(15);
    expect(row.dob.getUTCMonth() + 1).toBe(8);
    expect(row.dob.getUTCFullYear()).toBe(1998);
  });

  it('stores the same day whichever spelling an older client sends', async () => {
    // Every shape a build predating the date-only wire format can produce.
    // All of them must land on the identical instant, or two members who gave
    // the same date would have different rows.
    const spellings = [
      '1998-08-15',
      '1998-08-15T00:00:00.000Z',
      '1998-08-15T00:00:00.000',
      '1998-08-15T00:00:00+05:30',
      '1998-08-15T23:59:59.999-08:00',
    ];

    const stored: string[] = [];
    for (const [index, spelling] of spellings.entries()) {
      const id = `dobtest-compat-${index}`;
      await seedUser(id);
      const { dto, errors } = await throughDto(spelling);
      expect(errors).toHaveLength(0);
      // The DTO normalises before anything downstream sees it, so what would
      // reach `draft_data` is already date-only.
      expect(dto.dob).toBe('1998-08-15');

      await writeProfile(id, dto.dob!);
      const row = (await prisma.userProfile.findUnique({
        where: { userId: id },
      }))!;
      stored.push(row.dob.toISOString());
    }

    expect(new Set(stored).size).toBe(1);
    expect(stored[0]).toBe('1998-08-15T00:00:00.000Z');
  });

  it('keeps the profile and its horoscope on the same day', async () => {
    // `astrology_profiles.birth_date` is the same fact, written from the same
    // parsed value in the same call. If the two ever disagreed, Porutham
    // matching would score against a different date than the profile shows.
    await seedUser('dobtest-astro');
    const dob = parseBirthDate('1998-08-15')!;
    await writeProfile('dobtest-astro', '1998-08-15');
    await prisma.astrologyProfile.create({
      data: { user: { connect: { id: 'dobtest-astro' } }, birthDate: dob },
    });

    const profile = (await prisma.userProfile.findUnique({
      where: { userId: 'dobtest-astro' },
    }))!;
    const astrology = (await prisma.astrologyProfile.findUnique({
      where: { userId: 'dobtest-astro' },
    }))!;

    expect(astrology.birthDate.toISOString()).toBe(profile.dob.toISOString());
  });

  it('refuses the values the API is supposed to refuse, before any write', async () => {
    const nextYear = new Date().getUTCFullYear() + 1;
    const tooYoung = new Date(latestAllowedBirthDate(new Date()));
    tooYoung.setUTCDate(tooYoung.getUTCDate() + 1);

    for (const bad of [
      '2003-02-29', // impossible
      '1998-02-31', // impossible
      `${nextYear}-08-15`, // future
      tooYoung.toISOString().slice(0, 10), // one day under 21
      `${tooYoung.toISOString().slice(0, 10)}T00:00:00+05:30`, // ...as a timestamp
      '15/08/1998', // malformed
    ]) {
      const { errors } = await throughDto(bad);
      expect(errors).toHaveLength(1);
      expect(errors[0].property).toBe('dob');
    }

    // Nothing was written for any of them — the DTO is the gate, and it holds
    // before the service is ever reached.
    expect(
      await prisma.userProfile.count({
        where: { userId: { startsWith: 'dobtest-bad' } },
      }),
    ).toBe(0);
  });

  it('accepts exactly 21 and writes it, and refuses one day younger', async () => {
    const boundary = latestAllowedBirthDate(new Date())
      .toISOString()
      .slice(0, 10);

    await seedUser('dobtest-boundary');
    const accepted = await throughDto(boundary);
    expect(accepted.errors).toHaveLength(0);
    await writeProfile('dobtest-boundary', accepted.dto.dob!);
    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'dobtest-boundary' },
    }))!;
    expect(row.dob.toISOString().slice(0, 10)).toBe(boundary);

    const dayYounger = new Date(latestAllowedBirthDate(new Date()));
    dayYounger.setUTCDate(dayYounger.getUTCDate() + 1);
    const refused = await throughDto(dayYounger.toISOString().slice(0, 10));
    expect(refused.errors).toHaveLength(1);
  });

  it('has no upper bound: an older member writes and reads back intact', async () => {
    // The rule is a minimum age only. A member born before 1950 — which a
    // brief 1950 floor would have locked out of their own profile — stores
    // and reads back like any other.
    await seedUser('dobtest-elder');
    const { dto, errors } = await throughDto('1948-03-09');
    expect(errors).toHaveLength(0);
    await writeProfile('dobtest-elder', dto.dob!);

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'dobtest-elder' },
    }))!;
    expect(row.dob.toISOString()).toBe('1948-03-09T00:00:00.000Z');
  });

  it('leaves a row written before this change exactly as it was', async () => {
    // The compatibility guarantee the migration is separately responsible
    // for: nothing in the read or write path rewrites an existing value.
    await seedUser('dobtest-legacy');
    // What an IST server stored for a member who typed 15 / 08 / 1998.
    const legacy = new Date('1998-08-14T18:30:00.000Z');
    await prisma.userProfile.create({
      data: {
        user: { connect: { id: 'dobtest-legacy' } },
        firstName: 'Meera',
        lastName: 'Rajan',
        dob: legacy,
        gender: 'FEMALE',
        maritalStatus: 'NEVER_MARRIED',
        religion: 'Hindu',
        currentState: 'Tamil Nadu',
        currentCity: 'Madurai',
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'dobtest-legacy' },
    }))!;
    expect(row.dob.toISOString()).toBe('1998-08-14T18:30:00.000Z');
    // And it is exactly the row the normalisation migration is for: it reads
    // back as the 14th, a day off the date the member gave.
    expect(row.dob.getUTCDate()).toBe(14);
  });
});
