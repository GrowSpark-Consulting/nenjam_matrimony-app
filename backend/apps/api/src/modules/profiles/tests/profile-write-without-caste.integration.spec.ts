import { PrismaClient } from '@app/database';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from './integration-schema-guard';

/**
 * The real write path, against a real Postgres, for the draft the current
 * onboarding flow actually produces — one with no caste and no mother tongue.
 *
 * Everything else can pass while the system is still broken end to end: the
 * Flutter form validates, the DTOs accept the payload, the service decides the
 * draft is matchable — and then Postgres rejects the INSERT because two
 * columns nothing collects are still NOT NULL. Only a real database answers
 * that, so this talks to one.
 *
 * Every statement goes through Prisma's model API rather than `$queryRaw`.
 * That is not a style preference: raw statements ignore the adapter's `schema`
 * option and run against `public`, so a spec that seeds with raw SQL writes
 * its fixtures into the production tables. `connectIsolatedPrisma` pins
 * `search_path` and asserts `current_schema()` before anything is written.
 *
 * Prisma returns `null` for SQL NULL and `''` for an empty string, so the
 * distinction this whole change turns on survives the model read.
 */
describeIntegration('user_profiles accepts a profile with no caste', () => {
  let prisma: PrismaClient;

  beforeAll(async () => {
    prisma = await connectIsolatedPrisma();
    // Re-runnable: these rows are keyed by id, so a second run would collide.
    await prisma.userProfile.deleteMany({
      where: { userId: { startsWith: 'itest-' } },
    });
    await prisma.user.deleteMany({ where: { id: { startsWith: 'itest-' } } });
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  /** A user row to hang the profile off — `user_id` is a FK. */
  const seedUser = (id: string) =>
    prisma.user.create({
      data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.com` },
    });

  it('writes the row, and stores the two absent columns as NULL', async () => {
    await seedUser('itest-user-1');

    // Exactly what writeProfileFromDraft() passes for a draft produced by the
    // current onboarding flow: caste and motherTongue omitted, every genuinely
    // required field present. No placeholder anywhere.
    const created = await prisma.userProfile.create({
      data: {
        user: { connect: { id: 'itest-user-1' } },
        firstName: 'Arjun',
        lastName: 'Krishnan',
        dob: new Date('1994-06-18T00:00:00.000Z'),
        gender: 'MALE',
        maritalStatus: 'NEVER_MARRIED',
        religion: 'Hindu',
        community: 'Vellalar',
        subCaste: 'Iyer',
        currentState: 'Gujarat',
        currentCity: 'Bhavnagar',
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });
    expect(created.id).toBeTruthy();

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'itest-user-1' },
    }))!;

    // The point of the whole change.
    expect(row.caste).toBeNull();
    expect(row.motherTongue).toBeNull();
    // Emphatically NULL, not a placeholder the code sneaked in.
    expect(row.caste).not.toBe('');
    expect(row.motherTongue).not.toBe('');

    // ...while everything the product does still require is really there.
    expect(row.gender).toBe('MALE');
    expect(row.religion).toBe('Hindu');
    expect(row.currentState).toBe('Gujarat');
    expect(row.currentCity).toBe('Bhavnagar');
    expect(row.firstName).toBe('Arjun');
    expect(row.lastName).toBe('Krishnan');
    expect(row.maritalStatus).toBe('NEVER_MARRIED');
    expect(row.dob).not.toBeNull();
    // Sub-community is optional but was given, so it is stored.
    expect(row.subCaste).toBe('Iyer');
    expect(row.community).toBe('Vellalar');
  });

  it('accepts the shape onboarding produces: no caste, no mother tongue, no sub-community', async () => {
    // The acceptance case, stated literally: a member who completes the
    // current flow answers none of these three.
    await seedUser('itest-user-4');

    await prisma.userProfile.create({
      data: {
        user: { connect: { id: 'itest-user-4' } },
        firstName: 'Priya',
        lastName: 'Sharma',
        dob: new Date('1996-11-02T00:00:00.000Z'),
        gender: 'FEMALE',
        maritalStatus: 'NEVER_MARRIED',
        religion: 'Hindu',
        community: 'Nadar',
        currentState: 'Tamil Nadu',
        currentCity: 'Chennai',
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'itest-user-4' },
    }))!;

    expect(row.caste).toBeNull();
    expect(row.motherTongue).toBeNull();
    expect(row.subCaste).toBeNull();

    expect(row.firstName).toBe('Priya');
    expect(row.lastName).toBe('Sharma');
    expect(row.dob).not.toBeNull();
    expect(row.gender).toBe('FEMALE');
    expect(row.maritalStatus).toBe('NEVER_MARRIED');
    expect(row.religion).toBe('Hindu');
    expect(row.currentState).toBe('Tamil Nadu');
    expect(row.currentCity).toBe('Chennai');
  });

  it('leaves an existing member caste and mother tongue intact', async () => {
    // The compatibility half of the migration: DROP NOT NULL widens what the
    // column accepts and must not touch a single stored value.
    await seedUser('itest-user-2');

    await prisma.userProfile.create({
      data: {
        user: { connect: { id: 'itest-user-2' } },
        firstName: 'Meera',
        lastName: 'Rajan',
        dob: new Date('1995-03-21T00:00:00.000Z'),
        gender: 'FEMALE',
        maritalStatus: 'NEVER_MARRIED',
        religion: 'Hindu',
        caste: 'Vokkaliga',
        motherTongue: 'Kannada',
        currentState: 'Karnataka',
        currentCity: 'Bangalore',
        isProfileComplete: true,
        profileCompletePct: 0,
      },
    });

    const row = (await prisma.userProfile.findUnique({
      where: { userId: 'itest-user-2' },
    }))!;
    expect(row.caste).toBe('Vokkaliga');
    expect(row.motherTongue).toBe('Kannada');
  });

  it('still rejects a row missing a genuinely required column', async () => {
    // The migration widened exactly two columns. `religion` is still NOT NULL,
    // and proving that keeps this from being read as "we made everything
    // optional".
    await seedUser('itest-user-3');

    await expect(
      prisma.userProfile.create({
        data: {
          user: { connect: { id: 'itest-user-3' } },
          firstName: 'No',
          lastName: 'Religion',
          dob: new Date('1994-01-01T00:00:00.000Z'),
          gender: 'MALE',
          maritalStatus: 'NEVER_MARRIED',
          // religion deliberately omitted — Prisma rejects it as required.
          currentState: 'Tamil Nadu',
          currentCity: 'Chennai',
          isProfileComplete: true,
          profileCompletePct: 0,
        } as never,
      }),
    ).rejects.toThrow();
  });
});
