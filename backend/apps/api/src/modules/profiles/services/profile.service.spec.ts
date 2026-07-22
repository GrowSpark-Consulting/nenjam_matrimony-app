import { ProfileService } from './profile.service';
import type { ProfileRepository } from '../repositories/profile.repository';
import type { PhotoRepository } from '../repositories/photo.repository';
import type { ProfileDraftService } from './profile-draft.service';

// A draft whose sections satisfy every mandatory (NOT NULL) field.
const COMPLETE_DRAFT = {
  basicDetails: {
    firstName: 'Shaaz',
    lastName: 'Alfaiz',
    gender: 'MALE',
    dob: '2000-01-01',
    maritalStatus: 'NEVER_MARRIED',
  },
  religionDetails: { religion: 'Muslim', caste: 'Sheikh' },
  languageDetails: { motherTongue: 'Urdu' },
  locationDetails: { city: 'Bangalore', state: 'Karnataka' },
  educationDetails: { qualification: 'B.Tech', occupation: 'Software Engineer' },
  physicalDetails: { height: `5'9"` },
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

  const service = new ProfileService(
    profileRepository,
    photoRepository,
    draftService,
  );
  return { service, upsertProfile };
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
    // Same draft, but the height (a NOT NULL column) hasn't been entered yet.
    const incomplete = {
      ...COMPLETE_DRAFT,
      physicalDetails: {},
    };
    const { service, upsertProfile } = buildService(incomplete);

    await service.syncMatchableFromDraft('user-1');

    expect(upsertProfile).not.toHaveBeenCalled();
  });

  it('never throws — a materialisation failure must not fail the step save', async () => {
    const { service, upsertProfile } = buildService(COMPLETE_DRAFT);
    (upsertProfile as jest.Mock).mockRejectedValueOnce(new Error('db down'));

    await expect(service.syncMatchableFromDraft('user-1')).resolves.toBeUndefined();
  });
});
