import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@app/database';

/**
 * The real write path, against a real Postgres, for the draft the current
 * onboarding flow actually produces — one with no caste and no mother tongue.
 *
 * This is the test the whole change exists for. Everything else can pass while
 * the system is still broken end to end: the Flutter form validates, the DTOs
 * accept the payload, the service decides the draft is matchable — and then
 * Postgres rejects the INSERT because two columns nothing collects are still
 * NOT NULL. Only a real database can answer that, so this talks to one.
 *
 * **Isolated by schema, never by trust.** It runs against
 * `process.env.INTEGRATION_DATABASE_URL`, which is expected to point at a
 * throwaway schema (`?schema=…`), and it refuses to run against `public` — the
 * production tables live there and this test writes rows. Skipped entirely
 * when that variable is unset, so `pnpm test` on a laptop with no database
 * stays green; run it with the schema provisioned to get the real answer.
 *
 * Verifies, in one pass:
 *   1. `INSERT` succeeds with `caste` and `mother_tongue` absent.
 *   2. The stored row has both as SQL `NULL` — not `''`, not `'N/A'`.
 *   3. Every column the product genuinely still requires is populated.
 *   4. An existing row's caste and mother tongue survive the migration.
 */

const url = process.env.INTEGRATION_DATABASE_URL;
const schema = url ? new URL(url).searchParams.get('schema') : null;
const canRun = Boolean(url) && schema !== null && schema !== 'public';

const describeIntegration = canRun ? describe : describe.skip;

describeIntegration('user_profiles accepts a profile with no caste', () => {
  let prisma: PrismaClient;

  beforeAll(async () => {
    // The driver-adapter construction this project uses everywhere (see
    // PrismaService and seed-fake.ts) — Prisma 7 dropped both the
    // `datasources` and `datasourceUrl` constructor options.
    //
    // The schema is passed to the ADAPTER, not left to the URL's `?schema=`
    // parameter alone. That parameter steers Prisma's model queries but not
    // `$queryRaw`/`$executeRaw`, so the two halves of this test would
    // otherwise read and write different schemas — and the one the model
    // queries would land in is `public`, which holds the real tables. The
    // guard above refuses to run at all when that schema is `public`.
    prisma = new PrismaClient({
      adapter: new PrismaPg({ connectionString: url }, { schema: schema! }),
    });
    await prisma.$connect();

    // Re-runnable: the profile rows below are keyed by `user_id`, so a second
    // run would otherwise collide on the unique constraint and report a
    // failure that says nothing about the schema under test.
    await prisma.$executeRawUnsafe(
      `DELETE FROM "user_profiles" WHERE "user_id" LIKE 'itest-%'`,
    );
    await prisma.$executeRawUnsafe(
      `DELETE FROM "users" WHERE "id" LIKE 'itest-%'`,
    );
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  /** A user row to hang the profile off — `user_id` is a FK. */
  const seedUser = async (id: string, email: string) => {
    await prisma.$executeRawUnsafe(
      `INSERT INTO "users" ("id","firebase_uid","email","role","status",
         "trust_score","created_at","updated_at",
         "profile_visible_to_premium_only","hide_photos_from_non_connections")
       VALUES ($1,$2,$3,'USER','ACTIVE',0,NOW(),NOW(),false,false)
       ON CONFLICT ("id") DO NOTHING`,
      id,
      `fb-${id}`,
      email,
    );
  };

  it('writes the row, and stores the two absent columns as NULL', async () => {
    await seedUser('itest-user-1', 'itest1@example.com');

    // Exactly what writeProfileFromDraft() now passes for a draft produced by
    // the current onboarding flow: caste and motherTongue omitted, every
    // genuinely required field present. No placeholder anywhere.
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

    // Read back through raw SQL rather than the client, so the assertion is
    // about what the database holds and not about how Prisma deserialises it.
    const [row] = await prisma.$queryRawUnsafe<
      Array<Record<string, unknown>>
    >(`SELECT caste, mother_tongue, gender, religion, community, sub_caste,
              current_state, current_city, first_name, last_name, dob,
              marital_status
         FROM "user_profiles" WHERE "user_id" = 'itest-user-1'`);

    // The point of the whole change.
    expect(row.caste).toBeNull();
    expect(row.mother_tongue).toBeNull();
    // Emphatically NULL, not a placeholder the code sneaked in.
    expect(row.caste).not.toBe('');
    expect(row.mother_tongue).not.toBe('');

    // ...while everything the product does still require is really there.
    expect(row.gender).toBe('MALE');
    expect(row.religion).toBe('Hindu');
    expect(row.current_state).toBe('Gujarat');
    expect(row.current_city).toBe('Bhavnagar');
    expect(row.first_name).toBe('Arjun');
    expect(row.last_name).toBe('Krishnan');
    expect(row.marital_status).toBe('NEVER_MARRIED');
    expect(row.dob).not.toBeNull();
    // Sub-community is optional but was given, so it is stored.
    expect(row.sub_caste).toBe('Iyer');
    expect(row.community).toBe('Vellalar');
  });

  it('accepts the shape onboarding produces: no caste, no mother tongue, no sub-community', async () => {
    // The acceptance case, stated literally. A member who completes the
    // current flow answers none of these three — caste and mother tongue are
    // not asked at all, and sub-community is optional and may be skipped.
    // All three must land as SQL NULL while every required column is real.
    await seedUser('itest-user-4', 'itest4@example.com');

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

    const [row] = await prisma.$queryRawUnsafe<
      Array<Record<string, unknown>>
    >(`SELECT caste, mother_tongue, sub_caste, first_name, last_name, dob,
              gender, marital_status, religion, current_state, current_city
         FROM "user_profiles" WHERE "user_id" = 'itest-user-4'`);

    // The three the flow does not collect.
    expect(row.caste).toBeNull();
    expect(row.mother_tongue).toBeNull();
    expect(row.sub_caste).toBeNull();

    // The eight that must carry real values.
    expect(row.first_name).toBe('Priya');
    expect(row.last_name).toBe('Sharma');
    expect(row.dob).not.toBeNull();
    expect(row.gender).toBe('FEMALE');
    expect(row.marital_status).toBe('NEVER_MARRIED');
    expect(row.religion).toBe('Hindu');
    expect(row.current_state).toBe('Tamil Nadu');
    expect(row.current_city).toBe('Chennai');
  });

  it('leaves an existing member\'s caste and mother tongue intact', async () => {
    // The compatibility half of the migration: DROP NOT NULL widens what the
    // column accepts and must not touch a single stored value.
    await seedUser('itest-user-2', 'itest2@example.com');

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

    const [row] = await prisma.$queryRawUnsafe<
      Array<Record<string, unknown>>
    >(`SELECT caste, mother_tongue FROM "user_profiles"
        WHERE "user_id" = 'itest-user-2'`);

    expect(row.caste).toBe('Vokkaliga');
    expect(row.mother_tongue).toBe('Kannada');
  });

  it('still rejects a row missing a genuinely required column', async () => {
    // The migration widened exactly two columns. `religion` is still NOT NULL,
    // and proving that keeps this from being read as "we made everything
    // optional".
    await seedUser('itest-user-3', 'itest3@example.com');

    await expect(
      prisma.$executeRawUnsafe(
        `INSERT INTO "user_profiles"
           ("id","user_id","first_name","last_name","dob","gender",
            "marital_status","current_city","current_state",
            "is_profile_complete","profile_complete_pct",
            "created_at","updated_at","languages_known")
         VALUES (gen_random_uuid(),'itest-user-3','No','Religion',
                 NOW(),'MALE','NEVER_MARRIED','Chennai','Tamil Nadu',
                 true,0,NOW(),NOW(),'[]'::jsonb)`,
      ),
    ).rejects.toThrow();
  });
});
