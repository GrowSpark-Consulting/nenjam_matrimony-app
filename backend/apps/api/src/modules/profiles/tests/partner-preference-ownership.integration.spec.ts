import { PrismaClient } from '@app/database';
import type { PrismaService } from '@app/database';
import { ProfileRepository } from '../repositories/profile.repository';
import { PreferenceRepository } from '../../matches/repositories/preference.repository';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from './integration-schema-guard';

/**
 * Who owns partner_preferences, against a real Postgres.
 *
 * Two code paths write this table: PUT /discover/preferences (through
 * PreferenceRepository.upsert) and the profile save, which re-materialises
 * the registration draft (through ProfileRepository.createPartnerPreference-
 * IfMissing). The profile save used to be an upsert too, so every profile
 * edit reset the member's saved preferences to their registration answers.
 *
 * Unit tests can only assert which method is called. Whether
 * `INSERT … ON CONFLICT DO NOTHING` really leaves an existing row alone is a
 * property of the database, so this asks one. Uses the real repositories on
 * an isolated schema; every statement is a model call (see
 * integration-schema-guard.ts for why that matters).
 */
describeIntegration('partner preference ownership', () => {
  let prisma: PrismaClient;
  let profiles: ProfileRepository;
  let preferences: PreferenceRepository;

  const IDS = ['itest-pref-1', 'itest-pref-2', 'itest-pref-3'];

  beforeAll(async () => {
    prisma = await connectIsolatedPrisma();
    profiles = new ProfileRepository(prisma as unknown as PrismaService);
    preferences = new PreferenceRepository(prisma as unknown as PrismaService);
    // Re-runnable: partner_preferences cascades from users.
    await prisma.user.deleteMany({ where: { id: { in: IDS } } });
    for (const id of IDS) {
      await prisma.user.create({
        data: { id, firebaseUid: `fb-${id}`, email: `${id}@example.com` },
      });
    }
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: { in: IDS } } });
    await prisma?.$disconnect();
  });

  /** What writeProfileFromDraft passes for a stale registration draft. */
  const STALE_DRAFT = {
    minAge: 18,
    maxAge: 22,
    minHeightCm: 140,
    maxHeightCm: 210,
    preferredReligions: ['Christian'],
    preferredCastes: ['Any Caste'],
    minIncomeLakhs: null,
    preferredCities: [],
    preferredStates: [],
    preferredEducation: [],
    preferredOccupations: [],
    preferredMotherTongues: [],
    maritalStatusPref: [],
    extendedPreferences: {},
  };

  it('Case 1 — a profile save leaves preferences saved through the API unchanged', async () => {
    await preferences.upsert('itest-pref-1', {
      userId: 'itest-pref-1',
      minAge: 26,
      maxAge: 30,
      preferredReligions: ['Hindu'],
    });
    const before = await prisma.partnerPreference.findUniqueOrThrow({
      where: { userId: 'itest-pref-1' },
    });

    const created = await profiles.createPartnerPreferenceIfMissing(
      'itest-pref-1',
      STALE_DRAFT,
    );

    const after = await prisma.partnerPreference.findUniqueOrThrow({
      where: { userId: 'itest-pref-1' },
    });
    expect(created).toBe(false);
    expect(after.minAge).toBe(26);
    expect(after.maxAge).toBe(30);
    expect(after.preferredReligions).toEqual(['Hindu']);
    // Not even touched: updatedAt would move on any UPDATE.
    expect(after).toEqual(before);
  });

  it('Case 2 — creates the row from the draft when none exists', async () => {
    const created = await profiles.createPartnerPreferenceIfMissing(
      'itest-pref-2',
      { ...STALE_DRAFT, minAge: 24, maxAge: 29, preferredReligions: ['Hindu'] },
    );

    const row = await prisma.partnerPreference.findUniqueOrThrow({
      where: { userId: 'itest-pref-2' },
    });
    expect(created).toBe(true);
    expect(row.minAge).toBe(24);
    expect(row.maxAge).toBe(29);
    expect(row.preferredReligions).toEqual(['Hindu']);
  });

  it('Case 3 — a first-time "caste no bar" choice creates the row, and the API can still edit it', async () => {
    const created = await profiles.createPartnerPreferenceIfMissing(
      'itest-pref-3',
      { ...STALE_DRAFT, minAge: 18, maxAge: 45, preferredReligions: [] },
    );
    expect(created).toBe(true);

    let row = await prisma.partnerPreference.findUniqueOrThrow({
      where: { userId: 'itest-pref-3' },
    });
    expect(row.preferredCastes).toEqual(['Any Caste']);

    // The Preferences API remains the row's writer after the seed.
    await preferences.upsert('itest-pref-3', {
      userId: 'itest-pref-3',
      maxAge: 32,
    });
    // ...and a later profile save does not undo that edit.
    await profiles.createPartnerPreferenceIfMissing(
      'itest-pref-3',
      STALE_DRAFT,
    );

    row = await prisma.partnerPreference.findUniqueOrThrow({
      where: { userId: 'itest-pref-3' },
    });
    expect(row.maxAge).toBe(32);
    expect(row.preferredCastes).toEqual(['Any Caste']);
  });
});
