import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import { AppConfigModule } from '@app/config';
import { PrismaModule, PrismaService } from '@app/database';
import { FirebaseModule, FirebaseService } from '@app/firebase';
import { ProfilesModule } from '../src/modules/profiles/profiles.module';
import type { DraftResponse } from '../src/modules/profiles/services/profile-draft.service';
import type { ProfileEntity } from '../src/modules/profiles/entities/profile.entity';

// Exercises the real HTTP -> FirebaseAuthGuard -> ProfileDraftService ->
// Prisma -> Postgres path. Only FirebaseService.verifyIdToken is mocked
// (there's no real Firebase project available in CI/dev) — everything else,
// including the DB, is real. This is what proves requirement #11 of the
// Firebase-ownership task: two authenticated users never see or affect each
// other's registration data.
describe('Profile draft ownership (e2e)', () => {
  let app: INestApplication<App>;
  let prisma: PrismaService;

  const UID_A = 'e2e-test-uid-alice';
  const UID_B = 'e2e-test-uid-bob';

  const verifyIdToken = jest.fn((token: string) => {
    if (token === 'token-alice') {
      return Promise.resolve({ uid: UID_A, email: 'alice@e2e-test.local' });
    }
    if (token === 'token-bob') {
      return Promise.resolve({ uid: UID_B, email: 'bob@e2e-test.local' });
    }
    return Promise.reject(new Error('invalid token'));
  });

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppConfigModule, PrismaModule, FirebaseModule, ProfilesModule],
    })
      .overrideProvider(FirebaseService)
      .useValue({ verifyIdToken })
      .compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    await app.init();
    prisma = moduleFixture.get(PrismaService);

    // In case a previous failed run left rows behind.
    await cleanupTestUsers();
  });

  afterAll(async () => {
    await cleanupTestUsers();
    await app.close();
  });

  async function cleanupTestUsers(): Promise<void> {
    const users = await prisma.user.findMany({
      where: { firebaseUid: { in: [UID_A, UID_B] } },
      select: { id: true },
    });
    const ids = users.map((u) => u.id);
    if (ids.length === 0) return;

    await prisma.registrationStep.deleteMany({
      where: { userId: { in: ids } },
    });
    await prisma.userProfile.deleteMany({ where: { userId: { in: ids } } });
    await prisma.astrologyProfile.deleteMany({
      where: { userId: { in: ids } },
    });
    await prisma.partnerPreference.deleteMany({
      where: { userId: { in: ids } },
    });
    await prisma.user.deleteMany({ where: { id: { in: ids } } });
  }

  it('rejects requests with no Authorization header', async () => {
    await request(app.getHttpServer()).get('/profiles/draft').expect(401);
  });

  it('rejects an invalid/unrecognized bearer token', async () => {
    await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer not-a-real-token')
      .expect(401);
  });

  it('gives a brand-new Firebase user an empty draft', async () => {
    const res = await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer token-alice')
      .expect(200);

    const body = res.body as DraftResponse;
    expect(body.data).toEqual({});
    expect(body.completionPercentage).toBe(0);
  });

  it('ignores any userId the client tries to sneak into the body', async () => {
    // forbidNonWhitelisted rejects the unknown "userId" field outright —
    // ownership can only ever come from the verified token, never the body.
    await request(app.getHttpServer())
      .patch('/profiles/draft/basic-details')
      .set('Authorization', 'Bearer token-alice')
      .send({ firstName: 'Alice', userId: UID_B })
      .expect(400);
  });

  it("isolates two users' draft data end to end (steps 1-5)", async () => {
    // Alice fills in her basic details.
    await request(app.getHttpServer())
      .patch('/profiles/draft/basic-details')
      .set('Authorization', 'Bearer token-alice')
      .send({
        firstName: 'Alice',
        lastName: 'Anderson',
        gender: 'FEMALE',
        dob: '1996-01-01',
        maritalStatus: 'NEVER_MARRIED',
      })
      .expect(200);

    // Bob signs in for the first time — his draft must be completely empty,
    // unaffected by Alice's save.
    const bobDraft = await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer token-bob')
      .expect(200);
    expect((bobDraft.body as DraftResponse).data).toEqual({});

    // Bob fills in different values for the same section.
    await request(app.getHttpServer())
      .patch('/profiles/draft/basic-details')
      .set('Authorization', 'Bearer token-bob')
      .send({
        firstName: 'Bob',
        lastName: 'Baker',
        gender: 'MALE',
        dob: '1994-06-15',
        maritalStatus: 'NEVER_MARRIED',
      })
      .expect(200);

    // Alice's data must be completely untouched by Bob's write.
    const aliceDraft = await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer token-alice')
      .expect(200);
    const aliceBasic = (aliceDraft.body as DraftResponse).data
      .basicDetails as Record<string, unknown>;
    expect(aliceBasic.firstName).toBe('Alice');
    expect(aliceBasic.lastName).toBe('Anderson');

    // And Bob's own data is exactly what he saved.
    const bobDraft2 = await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer token-bob')
      .expect(200);
    const bobBasic = (bobDraft2.body as DraftResponse).data
      .basicDetails as Record<string, unknown>;
    expect(bobBasic.firstName).toBe('Bob');
    expect(bobBasic.lastName).toBe('Baker');
  });

  it('"signing in again" (same token) continues from where the user left off', async () => {
    // A fresh request with the same token simulates a new app session for
    // the same Firebase user — no server-side session state is involved,
    // ownership is re-derived from the token every time.
    const res = await request(app.getHttpServer())
      .get('/profiles/draft')
      .set('Authorization', 'Bearer token-alice')
      .expect(200);

    const body = res.body as DraftResponse;
    const basic = body.data.basicDetails as Record<string, unknown>;
    expect(basic.firstName).toBe('Alice');
    expect(body.completedSteps).toContain(1);
  });

  it('never creates a duplicate User row for repeated sign-ins of the same UID', async () => {
    const count = await prisma.user.count({ where: { firebaseUid: UID_A } });
    expect(count).toBe(1);
  });

  it('finalizes each user into their own separate, correct UserProfile row', async () => {
    for (const [token, values] of [
      [
        'token-alice',
        {
          religion: { religion: 'Hindu', caste: 'Iyer' },
          language: { motherTongue: 'Tamil' },
          location: { city: 'Chennai', state: 'Tamil Nadu' },
          education: { qualification: 'B.E.', occupation: 'Engineer' },
          physical: { height: '165' },
        },
      ],
      [
        'token-bob',
        {
          religion: { religion: 'Hindu', caste: 'Nair' },
          language: { motherTongue: 'Malayalam' },
          location: { city: 'Kochi', state: 'Kerala' },
          education: { qualification: 'MBA', occupation: 'Manager' },
          physical: { height: '178' },
        },
      ],
    ] as const) {
      const auth = ['Authorization', `Bearer ${token}`] as const;
      await request(app.getHttpServer())
        .patch('/profiles/draft/religion-details')
        .set(...auth)
        .send(values.religion)
        .expect(200);
      await request(app.getHttpServer())
        .patch('/profiles/draft/language-details')
        .set(...auth)
        .send(values.language)
        .expect(200);
      await request(app.getHttpServer())
        .patch('/profiles/draft/location-details')
        .set(...auth)
        .send(values.location)
        .expect(200);
      await request(app.getHttpServer())
        .patch('/profiles/draft/education-details')
        .set(...auth)
        .send(values.education)
        .expect(200);
      await request(app.getHttpServer())
        .patch('/profiles/draft/physical-details')
        .set(...auth)
        .send(values.physical)
        .expect(200);
    }

    const aliceProfile = (
      await request(app.getHttpServer())
        .post('/profiles/finalize')
        .set('Authorization', 'Bearer token-alice')
        .expect(201)
    ).body as ProfileEntity;
    const bobProfile = (
      await request(app.getHttpServer())
        .post('/profiles/finalize')
        .set('Authorization', 'Bearer token-bob')
        .expect(201)
    ).body as ProfileEntity;

    expect(aliceProfile.firstName).toBe('Alice');
    expect(aliceProfile.currentCity).toBe('Chennai');
    expect(bobProfile.firstName).toBe('Bob');
    expect(bobProfile.currentCity).toBe('Kochi');
    expect(aliceProfile.id).not.toBe(bobProfile.id);
    expect(aliceProfile.userId).not.toBe(bobProfile.userId);

    // GET /profiles/me returns exactly the caller's own row, not the other's.
    const aliceMe = (
      await request(app.getHttpServer())
        .get('/profiles/me')
        .set('Authorization', 'Bearer token-alice')
        .expect(200)
    ).body as ProfileEntity;
    expect(aliceMe.firstName).toBe('Alice');
  });

  it('re-finalizing does not create a duplicate profile row (idempotent)', async () => {
    await request(app.getHttpServer())
      .post('/profiles/finalize')
      .set('Authorization', 'Bearer token-alice')
      .expect(201);

    const aliceUser = await prisma.user.findUniqueOrThrow({
      where: { firebaseUid: UID_A },
    });
    const count = await prisma.userProfile.count({
      where: { userId: aliceUser.id },
    });
    expect(count).toBe(1);
  });
});
