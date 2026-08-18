import type { RedisService } from '@app/cache';
import { ProfileService } from './profile.service';
import type { ProfileRepository } from '../repositories/profile.repository';
import type { PhotoRepository } from '../repositories/photo.repository';
import type { ProfileDraftService } from './profile-draft.service';
import type { ProfileCompletionService } from './profile-completion.service';
import { ProfileCompletionEntity } from '../entities/profile-completion.entity';

// A draft whose sections satisfy every mandatory (NOT NULL) field.
const COMPLETE_DRAFT = {
  basicDetails: {
    firstName: 'Shaaz',
    lastName: 'Alfaiz',
    gender: 'MALE',
    dob: '2000-01-01',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Self',
  },
  religionDetails: {
    religion: 'Muslim',
    caste: 'Sheikh',
    subCaste: 'Siddiqui',
    community: 'Sunni',
  },
  languageDetails: {
    motherTongue: 'Urdu',
    languagesKnown: ['Urdu', 'English'],
  },
  locationDetails: {
    country: 'India',
    state: 'Karnataka',
    city: 'Bangalore',
    area: 'Indiranagar',
    pinCode: '560038',
    nativePlace: 'Bangalore',
  },
  educationDetails: {
    qualification: 'B.Tech',
    occupation: 'Software Engineer',
  },
  physicalDetails: { height: `5'9"`, weight: '68 kg', disability: 'None' },
  partnerPreference: {},
};

function buildService(draftData: Record<string, unknown>) {
  const upsertProfile = jest.fn().mockResolvedValue({});
  const profileRepository = {
    upsertProfile,
    upsertAstrologyProfile: jest.fn().mockResolvedValue(undefined),
    upsertPartnerPreference: jest.fn().mockResolvedValue(undefined),
    markComplete: jest.fn().mockResolvedValue(undefined),
    // recalculateAndPersistCompletion reads these; return benign shapes.
    findProfileByUserId: jest.fn().mockResolvedValue({ bio: null }),
    findPartnerPreference: jest.fn().mockResolvedValue(null),
    findAstrologyProfile: jest.fn().mockResolvedValue(null),
    updateProfileCompletePct: jest.fn().mockResolvedValue(undefined),
  } as unknown as ProfileRepository;

  const photoRepository = {
    findAllForUser: jest.fn().mockResolvedValue([]),
  } as unknown as PhotoRepository;

  const draftService = {
    getDraft: jest.fn().mockResolvedValue({ data: draftData }),
  } as unknown as ProfileDraftService;

  // Scoring itself is covered by profile-completion.service.spec.ts — these
  // tests only care that syncMatchableFromDraft materialises the profile,
  // so a benign completion result is enough here.
  const completionService = {
    calculate: jest.fn().mockResolvedValue(
      Object.assign(new ProfileCompletionEntity(), {
        percentage: 0,
        completedSections: [],
        missingSections: [],
        breakdown: [],
        verificationBreakdown: [],
      }),
    ),
  } as unknown as ProfileCompletionService;

  const emailDispatch = {
    sendWelcome: jest.fn().mockResolvedValue(undefined),
  };
  const service = new ProfileService(
    profileRepository,
    photoRepository,
    draftService,
    completionService,
    emailDispatch as never,
      // Redis is only used to drop the cached feed context; a not-ready client
      // makes every call a no-op, which is exactly what these tests want.
      { getClient: () => ({ status: 'end' }) } as unknown as RedisService,
    );
  return { service, upsertProfile, emailDispatch };
}

describe('ProfileService.syncMatchableFromDraft', () => {
  it('materialises a matchable profile once all mandatory fields are present', async () => {
    const { service, upsertProfile } = buildService(COMPLETE_DRAFT);

    await service.syncMatchableFromDraft('user-1');

    expect(upsertProfile).toHaveBeenCalledTimes(1);
    // Eligible profiles are flagged matchable so buildFeedWhere includes them.
    expect(upsertProfile.mock.calls[0][1]).toMatchObject({
      isProfileComplete: true,
      gender: 'MALE',
    });
  });

  it('is a no-op while any mandatory field is still missing (no premature row)', async () => {
    // Same draft, but the city (a NOT NULL column, Step 4) hasn't been
    // entered yet. Physical (Step 6) is deliberately NOT used for this case
    // — it's skippable and no longer part of the mandatory-fields gate.
    const incomplete = {
      ...COMPLETE_DRAFT,
      locationDetails: {},
    };
    const { service, upsertProfile } = buildService(incomplete);

    await service.syncMatchableFromDraft('user-1');

    expect(upsertProfile).not.toHaveBeenCalled();
  });

  it('never throws — a materialisation failure must not fail the step save', async () => {
    const { service, upsertProfile } = buildService(COMPLETE_DRAFT);
    upsertProfile.mockRejectedValueOnce(new Error('db down'));

    await expect(
      service.syncMatchableFromDraft('user-1'),
    ).resolves.toBeUndefined();
  });
});
