import { NotFoundException } from '@nestjs/common';
import { PrismaClient } from '@app/database';
import type { PrismaService } from '@app/database';
import type { S3Service } from '@app/storage';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { FeedRepository } from '../repositories/feed.repository';
import { ProfileLookupService } from '../services/profile-lookup.service';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';

/**
 * `GET /discover/profiles/:userId` — the Profile Detail screen's source —
 * end to end against a REAL Postgres: the real repository, mapper and lookup
 * service, with only S3 signing stubbed (no photos are seeded).
 *
 * Proves what the unit spec cannot: that the Prisma select actually reaches
 * the persisted family / fitness / astrology / partner-preference columns,
 * that unfilled columns come back empty rather than defaulted, and that the
 * feed's visibility rules refuse a blocked, declined, deleted or hidden member
 * before any detail column is read.
 *
 * Isolated by schema and skipped unless `INTEGRATION_DATABASE_URL` names a
 * throwaway one — never `public`. The schema must have the migrations applied.
 */
describeIntegration('Profile detail lookup, against Postgres', () => {
  let prisma: PrismaClient;
  let service: ProfileLookupService;

  const VIEWER = 'itest-detail-viewer';
  const FULL = 'itest-detail-full';
  const EMPTY = 'itest-detail-empty';
  const ALL = [VIEWER, FULL, EMPTY];

  async function seedUser(
    id: string,
    gender: 'MALE' | 'FEMALE',
    profile: Record<string, unknown> = {},
  ) {
    await prisma.user.create({
      data: {
        id,
        firebaseUid: `${id}-uid`,
        email: `${id}@example.invalid`,
        profile: {
          create: {
            firstName: id,
            lastName: 'Fixture',
            dob: new Date('1995-03-21T00:00:00.000Z'),
            gender,
            religion: 'Hindu',
            currentCity: 'Chennai',
            currentState: 'Tamil Nadu',
            isProfileComplete: true,
            ...profile,
          },
        },
      },
    });
  }

  async function cleanup() {
    await prisma.user.deleteMany({ where: { id: { in: ALL } } });
  }

  beforeAll(async () => {
    prisma = await connectIsolatedPrisma();
    const db = prisma as unknown as PrismaService;
    service = new ProfileLookupService(
      new FeedRepository(db),
      new ProfileFeedMapper({
        isConfigured: () => false,
      } as unknown as S3Service),
    );
    await cleanup();

    await seedUser(VIEWER, 'MALE');
    await seedUser(FULL, 'FEMALE', {
      fatherName: 'Itest Father',
      fatherOccupation: 'Itest Farmer',
      motherName: 'Itest Mother',
      familyType: 'Itest Nuclear',
      familyStatus: 'Itest Middle Class',
      siblingDetails: [
        { relation: 'BROTHER', name: 'Itest Hidden Sibling' },
        { relation: 'SISTER' },
      ],
      fitness: 'Itest Yoga',
      bio: 'Itest bio.',
      hobbies: ['Itest Chess'],
    });
    await prisma.astrologyProfile.create({
      data: {
        userId: FULL,
        birthDate: new Date('1995-03-21T00:00:00.000Z'),
        birthTime: '05:55',
        birthPlace: 'Itest Hidden Town',
        rasi: 'Itest Kumbha',
        nakshatra: 'Itest Sathayam',
        dosham: 'CHEVVAI',
        horoscopeAvailable: true,
      },
    });
    await prisma.partnerPreference.create({
      data: {
        userId: FULL,
        minAge: 28,
        maxAge: null,
        preferredReligions: ['Hindu'],
        preferredStates: ['Tamil Nadu'],
        maritalStatusPref: ['NEVER_MARRIED'],
      },
    });
    // Finalized, but filled in nothing beyond the mandatory steps.
    await seedUser(EMPTY, 'FEMALE');
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$disconnect();
  });

  it('returns the persisted detail values exactly', async () => {
    const result = await service.getVisibleProfile(VIEWER, FULL);

    expect(result.bio).toBe('Itest bio.');
    // The real user_profiles.created_at, not a client-side "now".
    const row = await prisma.userProfile.findUnique({
      where: { userId: FULL },
      select: { createdAt: true },
    });
    expect(result.joinedAt).toBe(row!.createdAt.toISOString());
    expect(result.hobbies).toEqual(['Itest Chess']);
    expect(result.detail.family).toEqual({
      fatherName: 'Itest Father',
      fatherOccupation: 'Itest Farmer',
      motherName: 'Itest Mother',
      motherOccupation: '',
      familyType: 'Itest Nuclear',
      familyValues: '',
      familyStatus: 'Itest Middle Class',
      brothers: 1,
      sisters: 1,
    });
    expect(result.detail.fitness).toBe('Itest Yoga');
    expect(result.detail.horoscope).toEqual({
      rasi: 'Itest Kumbha',
      nakshatra: 'Itest Sathayam',
      dosham: 'Chevvai',
      horoscopeAvailable: true,
    });
    expect(result.detail.partnerPreference).toMatchObject({
      minAge: 28,
      maxAge: null,
      religions: ['Hindu'],
      states: ['Tamil Nadu'],
      castes: [],
      maritalStatuses: ['Never Married'],
    });

    // Stored, but never put on the wire.
    const wire = JSON.stringify(result);
    expect(wire).not.toContain('Itest Hidden Sibling');
    expect(wire).not.toContain('Itest Hidden Town');
    expect(wire).not.toContain('05:55');
  });

  it('leaves every unfilled field empty instead of defaulting it', async () => {
    const { detail, bio, hobbies } = await service.getVisibleProfile(
      VIEWER,
      EMPTY,
    );
    expect(bio).toBe('');
    expect(hobbies).toEqual([]);
    expect(Object.values(detail.family).every((v) => v === '' || v === 0)).toBe(
      true,
    );
    expect(detail.fitness).toBe('');
    expect(detail.horoscope).toEqual({
      rasi: '',
      nakshatra: '',
      dosham: '',
      horoscopeAvailable: false,
    });
    expect(detail.partnerPreference).toBeNull();
  });

  it('reflects an update and leaves unrelated fields unchanged', async () => {
    await prisma.userProfile.update({
      where: { userId: FULL },
      data: { fatherOccupation: 'Itest Teacher' },
    });
    const { detail } = await service.getVisibleProfile(VIEWER, FULL);
    expect(detail.family.fatherOccupation).toBe('Itest Teacher');
    expect(detail.family.fatherName).toBe('Itest Father');
    expect(detail.fitness).toBe('Itest Yoga');
    expect(detail.horoscope.rasi).toBe('Itest Kumbha');
  });

  describe('refuses a profile the viewer may not see', () => {
    const expect404 = () =>
      expect(service.getVisibleProfile(VIEWER, FULL)).rejects.toBeInstanceOf(
        NotFoundException,
      );

    it('across a block, in either direction', async () => {
      for (const [blockerId, blockedUserId] of [
        [VIEWER, FULL],
        [FULL, VIEWER],
      ]) {
        await prisma.userBlock.create({ data: { blockerId, blockedUserId } });
        await expect404();
        await prisma.userBlock.deleteMany({ where: { blockerId } });
      }
    });

    it('across a declined interest', async () => {
      await prisma.expressInterest.create({
        data: { senderId: VIEWER, receiverId: FULL, status: 'DECLINED' },
      });
      await expect404();
      await prisma.expressInterest.deleteMany({ where: { senderId: VIEWER } });
    });

    it('for a soft-deleted or suspended account', async () => {
      await prisma.user.update({
        where: { id: FULL },
        data: { deletedAt: new Date() },
      });
      await expect404();
      await prisma.user.update({
        where: { id: FULL },
        data: { deletedAt: null, status: 'SUSPENDED' },
      });
      await expect404();
      await prisma.user.update({
        where: { id: FULL },
        data: { status: 'PENDING_VERIFICATION' },
      });
    });

    it('for an unfinalized profile, and for a same-gender viewer', async () => {
      await prisma.userProfile.update({
        where: { userId: FULL },
        data: { isProfileComplete: false },
      });
      await expect404();
      await prisma.userProfile.update({
        where: { userId: FULL },
        data: { isProfileComplete: true },
      });
      await expect(
        service.getVisibleProfile(EMPTY, FULL),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('is visible again once every restriction is lifted', async () => {
      await expect(
        service.getVisibleProfile(VIEWER, FULL),
      ).resolves.toMatchObject({ id: FULL });
    });
  });
});
