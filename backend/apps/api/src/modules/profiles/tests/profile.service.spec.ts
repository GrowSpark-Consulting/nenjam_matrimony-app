import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { ProfileDraftService } from '../services/profile-draft.service';
import { ProfileService } from '../services/profile.service';
import { ProfileEntity } from '../entities/profile.entity';
import { PhotoEntity } from '../entities/photo.entity';
import { PartnerPreferenceEntity } from '../entities/partner-preference.entity';
import { AstrologyProfileEntity } from '../entities/astrology-profile.entity';
import { DraftResponse } from '../services/profile-draft.service';

function buildProfile(overrides: Partial<ProfileEntity> = {}): ProfileEntity {
  const entity = new ProfileEntity();
  Object.assign(entity, {
    id: 'profile-1',
    userId: 'user-1',
    firstName: 'Arjun',
    lastName: 'Sundar',
    dob: new Date('1997-01-01'),
    gender: 'MALE',
    maritalStatus: 'NEVER_MARRIED',
    religion: 'Hindu',
    caste: 'Iyer',
    subCaste: null,
    motherTongue: 'Tamil',
    heightCm: 178,
    weightKg: null,
    annualIncomeLakhs: null,
    highestEducation: "Bachelor's",
    educationDetails: null,
    profession: 'Product Designer',
    employerName: null,
    currentCity: 'Chennai',
    currentState: 'Tamil Nadu',
    nativeCity: null,
    bio: null,
    dietaryHabits: null,
    smokingHabits: null,
    drinkingHabits: null,
    physicalStatus: null,
    familyType: null,
    familyStatus: null,
    fatherOccupation: null,
    motherOccupation: null,
    siblings: null,
    isProfileComplete: true,
    profileCompletePct: 0,
    photos: undefined,
    partnerPreference: undefined,
    astrology: undefined,
    completion: undefined,
    ...overrides,
  });
  return entity;
}

function buildPhoto(overrides: Partial<PhotoEntity> = {}): PhotoEntity {
  const entity = new PhotoEntity();
  Object.assign(entity, {
    id: 'photo-1',
    userId: 'user-1',
    s3Key: 'users/user-1/photo-1.jpg',
    cdnUrl: 'https://cdn.example.com/users/user-1/photo-1.jpg',
    isPrimary: true,
    order: 0,
    isApproved: false,
    ...overrides,
  });
  return entity;
}

function buildPartnerPreference(): PartnerPreferenceEntity {
  const entity = new PartnerPreferenceEntity();
  Object.assign(entity, {
    id: 'pref-1',
    userId: 'user-1',
    minAge: 24,
    maxAge: 30,
    minHeightCm: 150,
    maxHeightCm: 180,
    preferredReligions: ['Hindu'],
    preferredCastes: [],
    minIncomeLakhs: null,
    preferredCities: [],
    preferredStates: [],
    preferredEducation: [],
    maritalStatusPref: [],
  });
  return entity;
}

function buildAstrologyProfile(): AstrologyProfileEntity {
  const entity = new AstrologyProfileEntity();
  Object.assign(entity, {
    id: 'astro-1',
    userId: 'user-1',
    birthDate: new Date('1997-01-01'),
    birthTime: '10:30',
    birthPlace: 'Chennai',
    rasi: 'Mesham',
    nakshatra: 'Ashwini',
    lagnam: null,
    gotram: null,
    dosham: 'NONE',
  });
  return entity;
}

describe('ProfileService', () => {
  function buildService(overrides?: {
    findProfileByUserId?: jest.Mock;
    upsertProfile?: jest.Mock;
    upsertAstrologyProfile?: jest.Mock;
    upsertPartnerPreference?: jest.Mock;
    findPartnerPreference?: jest.Mock;
    findAstrologyProfile?: jest.Mock;
    markComplete?: jest.Mock;
    updateProfileCompletePct?: jest.Mock;
    findAllForUser?: jest.Mock;
    getDraft?: jest.Mock;
  }) {
    const profileRepository = {
      findProfileByUserId: overrides?.findProfileByUserId ?? jest.fn(),
      upsertProfile: overrides?.upsertProfile ?? jest.fn(),
      upsertAstrologyProfile: overrides?.upsertAstrologyProfile ?? jest.fn(),
      upsertPartnerPreference:
        overrides?.upsertPartnerPreference ?? jest.fn(),
      findPartnerPreference:
        overrides?.findPartnerPreference ?? jest.fn().mockResolvedValue(null),
      findAstrologyProfile:
        overrides?.findAstrologyProfile ?? jest.fn().mockResolvedValue(null),
      markComplete: overrides?.markComplete ?? jest.fn(),
      updateProfileCompletePct:
        overrides?.updateProfileCompletePct ?? jest.fn(),
    } as unknown as ProfileRepository;

    const photoRepository = {
      findAllForUser:
        overrides?.findAllForUser ?? jest.fn().mockResolvedValue([]),
    } as unknown as PhotoRepository;

    const draftService = {
      getDraft: overrides?.getDraft ?? jest.fn(),
    } as unknown as ProfileDraftService;

    return new ProfileService(profileRepository, photoRepository, draftService);
  }

  describe('getOwn', () => {
    it('throws NotFoundException when the profile has not been finalized', async () => {
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(null),
      });

      await expect(service.getOwn('user-1')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('assembles photos, partnerPreference, astrology, and completion', async () => {
      const service = buildService({
        findProfileByUserId: jest
          .fn()
          .mockResolvedValue(buildProfile({ bio: 'Loves long walks.' })),
        findAllForUser: jest.fn().mockResolvedValue([buildPhoto()]),
        findPartnerPreference: jest
          .fn()
          .mockResolvedValue(buildPartnerPreference()),
        findAstrologyProfile: jest
          .fn()
          .mockResolvedValue(buildAstrologyProfile()),
      });

      const result = await service.getOwn('user-1');

      expect(result.photos).toHaveLength(1);
      expect(result.partnerPreference).not.toBeNull();
      expect(result.astrology).not.toBeNull();
      expect(result.completion.percentage).toBe(100);
      expect(result.completion.missingSections).toEqual([]);
    });

    it('reports missing optional sections when photos/about/preferences/astrology are absent', async () => {
      const service = buildService({
        findProfileByUserId: jest
          .fn()
          .mockResolvedValue(buildProfile({ bio: null })),
        findAllForUser: jest.fn().mockResolvedValue([]),
        findPartnerPreference: jest.fn().mockResolvedValue(null),
        findAstrologyProfile: jest.fn().mockResolvedValue(null),
      });

      const result = await service.getOwn('user-1');

      // basicInfo, religionCommunity, location, careerEducation are always
      // true once a profile row exists (enforced at finalize()) — only the
      // 4 optional sections are missing here.
      expect(result.completion.missingSections.sort()).toEqual(
        ['about', 'astrology', 'partnerPreference', 'photos'].sort(),
      );
      expect(result.completion.percentage).toBe(50);
    });
  });

  describe('finalize', () => {
    function buildValidDraft(
      overrides: Record<string, Record<string, unknown>> = {},
    ): DraftResponse {
      return {
        currentStep: 10,
        totalSteps: 12,
        completedSteps: [1, 2, 3, 4, 5, 6],
        isComplete: false,
        completionPercentage: 100,
        data: {
          basicDetails: {
            firstName: 'Arjun',
            lastName: 'Sundar',
            gender: 'MALE',
            dob: '1997-01-01',
          },
          religionDetails: { religion: 'Hindu', caste: 'Iyer' },
          languageDetails: { motherTongue: 'Tamil' },
          locationDetails: { city: 'Chennai', state: 'Tamil Nadu' },
          educationDetails: {
            qualification: "Bachelor's",
            occupation: 'Product Designer',
          },
          physicalDetails: { height: '178 cm' },
          ...overrides,
        },
      };
    }

    it('throws BadRequestException when required fields are missing', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({ basicDetails: {} }),
        ),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('upserts the profile and persists a freshly-computed completion percentage', async () => {
      const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
      const updateProfileCompletePct = jest.fn().mockResolvedValue(undefined);
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile,
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        updateProfileCompletePct,
      });

      const result = await service.finalize('user-1');

      expect(upsertProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          firstName: 'Arjun',
          lastName: 'Sundar',
          currentCity: 'Chennai',
        }),
      );
      // finalize() must not trust the hardcoded 100 it used to write —
      // the persisted value has to come from the real recomputation.
      expect(updateProfileCompletePct).toHaveBeenCalledWith(
        'user-1',
        result.completion.percentage,
      );
      expect(result.profileCompletePct).toBe(result.completion.percentage);
    });

    it('does not upsert astrology when no horoscope fields were provided', async () => {
      const upsertAstrologyProfile = jest.fn();
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        upsertAstrologyProfile,
      });

      await service.finalize('user-1');

      expect(upsertAstrologyProfile).not.toHaveBeenCalled();
    });

    it('upserts astrology when horoscope fields are present', async () => {
      const upsertAstrologyProfile = jest.fn();
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            horoscopeDetails: { birthPlace: 'Chennai', rashi: 'Mesham' },
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        upsertAstrologyProfile,
      });

      await service.finalize('user-1');

      expect(upsertAstrologyProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({ birthPlace: 'Chennai', rasi: 'Mesham' }),
      );
    });

    it('maps the previously-dropped wizard fields into the profile columns', async () => {
      const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            religionDetails: {
              religion: 'Hindu',
              caste: 'Iyer',
              community: 'Brahmin',
              denomination: 'Smartha',
            },
            languageDetails: {
              motherTongue: 'Tamil',
              languagesKnown: ['Tamil', 'English'],
            },
            locationDetails: {
              city: 'Chennai',
              state: 'Tamil Nadu',
              country: 'India',
              area: 'Anna Nagar',
              pinCode: '600040',
            },
            lifestyleDetails: {
              fitness: 'Regular',
              hobbies: ['Reading', 'Cricket'],
            },
            familyDetails: { familyValues: 'Traditional' },
          }),
        ),
        upsertProfile,
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await service.finalize('user-1');

      expect(upsertProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          community: 'Brahmin',
          denomination: 'Smartha',
          languagesKnown: ['Tamil', 'English'],
          country: 'India',
          area: 'Anna Nagar',
          pinCode: '600040',
          fitness: 'Regular',
          hobbies: ['Reading', 'Cricket'],
          familyValues: 'Traditional',
        }),
      );
    });

    it('maps partner-preference occupation/mother-tongue prefs as arrays', async () => {
      const upsertPartnerPreference = jest.fn();
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            partnerPreference: {
              occupationPref: 'Engineer, Doctor',
              motherTonguePref: 'Tamil, Telugu',
            },
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        upsertPartnerPreference,
      });

      await service.finalize('user-1');

      expect(upsertPartnerPreference).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          preferredOccupations: ['Engineer', 'Doctor'],
          preferredMotherTongues: ['Tamil', 'Telugu'],
        }),
      );
    });

    it('falls back to star when nakshatra is not provided, and persists horoscopeAvailable', async () => {
      const upsertAstrologyProfile = jest.fn();
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            horoscopeDetails: {
              star: 'Ashwini',
              horoscopeAvailable: true,
            },
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        upsertAstrologyProfile,
      });

      await service.finalize('user-1');

      expect(upsertAstrologyProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          nakshatra: 'Ashwini',
          horoscopeAvailable: true,
        }),
      );
    });

    it('prefers nakshatra over star when both are provided', async () => {
      const upsertAstrologyProfile = jest.fn();
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            horoscopeDetails: { nakshatra: 'Bharani', star: 'Ashwini' },
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        upsertAstrologyProfile,
      });

      await service.finalize('user-1');

      expect(upsertAstrologyProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({ nakshatra: 'Bharani' }),
      );
    });
  });
});
