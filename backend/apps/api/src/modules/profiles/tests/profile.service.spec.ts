import type { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import type { PrismaService } from '@app/database';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { ProfileDraftService } from '../services/profile-draft.service';
import { S3Service } from '@app/storage';
import { ProfileService } from '../services/profile.service';
import { ProfileCompletionService } from '../services/profile-completion.service';
import { ProfileEntity } from '../entities/profile.entity';
import { PhotoEntity } from '../entities/photo.entity';
import { PartnerPreferenceEntity } from '../entities/partner-preference.entity';
import { AstrologyProfileEntity } from '../entities/astrology-profile.entity';
import { ProfileCompletionEntity } from '../entities/profile-completion.entity';
import { DraftResponse } from '../services/profile-draft.service';

function buildCompletion(
  overrides: Partial<ProfileCompletionEntity> = {},
): ProfileCompletionEntity {
  return Object.assign(new ProfileCompletionEntity(), {
    percentage: 42,
    completedSections: ['registration'],
    missingSections: ['photos'],
    breakdown: [],
    verificationBreakdown: [],
    ...overrides,
  });
}

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
    calculate?: jest.Mock;
    sendWelcome?: jest.Mock;
    s3?: Partial<S3Service>;
  }) {
    const profileRepository = {
      findProfileByUserId: overrides?.findProfileByUserId ?? jest.fn(),
      upsertProfile: overrides?.upsertProfile ?? jest.fn(),
      upsertAstrologyProfile: overrides?.upsertAstrologyProfile ?? jest.fn(),
      upsertPartnerPreference: overrides?.upsertPartnerPreference ?? jest.fn(),
      findPartnerPreference:
        overrides?.findPartnerPreference ?? jest.fn().mockResolvedValue(null),
      findAstrologyProfile:
        overrides?.findAstrologyProfile ?? jest.fn().mockResolvedValue(null),
      markComplete: overrides?.markComplete ?? jest.fn(),
      updateProfileCompletePct:
        overrides?.updateProfileCompletePct ?? jest.fn(),
    } as unknown as ProfileRepository;

    const photoRepository = {
      // Default: one photo present. Harmless either way — finalize() does
      // NOT gate on photo count (see 'does not throw when no photo has
      // been uploaded' below) — this only affects the "photos" 12%
      // completion slice tests care about.
      findAllForUser:
        overrides?.findAllForUser ??
        jest.fn().mockResolvedValue([buildPhoto()]),
    } as unknown as PhotoRepository;

    const draftService = {
      getDraft: overrides?.getDraft ?? jest.fn(),
    } as unknown as ProfileDraftService;

    // Scoring math is covered by profile-completion.service.spec.ts — these
    // tests only care that ProfileService plumbs the result through
    // unchanged and persists its percentage.
    const completionService = {
      calculate:
        overrides?.calculate ?? jest.fn().mockResolvedValue(buildCompletion()),
    } as unknown as ProfileCompletionService;

    return new ProfileService(
      profileRepository,
      photoRepository,
      draftService,
      completionService,
      {
        sendWelcome:
          overrides?.sendWelcome ?? jest.fn().mockResolvedValue(undefined),
      } as never,
      // Feed invalidation is fire-and-forget bookkeeping after a successful
      // write; these tests assert the write, not the cache signalling.
      { invalidate: jest.fn(), invalidatePair: jest.fn() } as unknown as FeedInvalidationService,
      // S3 stub reporting "not configured", so getOwn()'s presigning step
      // is a no-op and photo `cdnUrl`s reach these assertions exactly as the
      // repository returned them — these tests are about profile assembly,
      // not URL signing (see photo.service.spec.ts for that).
      (overrides?.s3 ?? {
        isConfigured: () => false,
      }) as unknown as S3Service,
    );
  }

  describe('getOwn', () => {
    it('throws NotFoundException when the profile has not been finalized', async () => {
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(null),
      });

      await expect(service.getOwn('user-1')).rejects.toThrow(NotFoundException);
    });

    it('assembles photos, partnerPreference, astrology, and the completion score from ProfileCompletionService', async () => {
      const completion = buildCompletion({ percentage: 87 });
      const calculate = jest.fn().mockResolvedValue(completion);
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
        calculate,
      });

      const result = await service.getOwn('user-1');

      expect(result.photos).toHaveLength(1);
      expect(result.partnerPreference).not.toBeNull();
      expect(result.astrology).not.toBeNull();
      // getOwn never recomputes its own score — it trusts whatever
      // ProfileCompletionService (the single authoritative calculator)
      // returns, verbatim.
      expect(result.completion).toBe(completion);
      expect(calculate).toHaveBeenCalledWith('user-1', undefined);
    });

    it('passes a prefetched draft through to ProfileCompletionService instead of triggering its own fetch', async () => {
      const calculate = jest.fn().mockResolvedValue(buildCompletion());
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        calculate,
      });
      const draftData = { basicDetails: { firstName: 'Arjun' } };

      await service.getOwn('user-1', undefined, undefined, draftData);

      expect(calculate).toHaveBeenCalledWith('user-1', draftData);
    });

    // Regression: the stored `cdn_url` column holds S3Service.getObjectUrl()
    // — a durable reference to an object in a PRIVATE bucket, which answers
    // 403 when a client actually fetches it. GET /profiles/me read the rows
    // straight from PhotoRepository and returned those URLs verbatim, so
    // every photo on the profile response was unloadable, while
    // GET /profiles/me/photos (PhotoService.list) presigned correctly.
    it('presigns photo URLs rather than returning the stored private-bucket URL', async () => {
      const getPresignedGetUrl = jest
        .fn()
        .mockResolvedValue('https://s3.example.com/signed?sig=abc');
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        findAllForUser: jest.fn().mockResolvedValue([buildPhoto()]),
        s3: { isConfigured: () => true, getPresignedGetUrl },
      });

      const result = await service.getOwn('user-1');

      expect(getPresignedGetUrl).toHaveBeenCalledWith('users/user-1/photo-1.jpg');
      expect(result.photos[0].cdnUrl).toBe('https://s3.example.com/signed?sig=abc');
    });

    // getOwn() also answers the client's "do I have a finalized profile?"
    // routing check, so a storage outage must not turn it into a 500 that
    // strands the member outside the app.
    it('falls back to the stored rows when presigning fails', async () => {
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        findAllForUser: jest.fn().mockResolvedValue([buildPhoto()]),
        s3: {
          isConfigured: () => true,
          getPresignedGetUrl: jest.fn().mockRejectedValue(new Error('s3 down')),
        },
      });

      const result = await service.getOwn('user-1');

      expect(result.photos).toHaveLength(1);
      expect(result.photos[0].cdnUrl).toBe(
        'https://cdn.example.com/users/user-1/photo-1.jpg',
      );
    });

    // finalize() hands its already-fetched rows in to save a re-SELECT; those
    // are raw repository rows too, so they need the same treatment.
    it('presigns prefetched photos as well', async () => {
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        s3: {
          isConfigured: () => true,
          getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed/1'),
        },
      });

      const result = await service.getOwn('user-1', undefined, [buildPhoto()]);

      expect(result.photos[0].cdnUrl).toBe('https://signed/1');
    });
  });

  describe('recalculateCompletionIfMaterialized', () => {
    it('persists the freshly-computed percentage when the profile already exists', async () => {
      const updateProfileCompletePct = jest.fn().mockResolvedValue(undefined);
      const calculate = jest
        .fn()
        .mockResolvedValue(buildCompletion({ percentage: 55 }));
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        updateProfileCompletePct,
        calculate,
      });

      await service.recalculateCompletionIfMaterialized('user-1');

      expect(updateProfileCompletePct).toHaveBeenCalledWith('user-1', 55);
    });

    it('silently no-ops when the profile has not been finalized yet (photo uploaded pre-mandatory-completion)', async () => {
      const updateProfileCompletePct = jest.fn();
      const service = buildService({
        findProfileByUserId: jest.fn().mockResolvedValue(null),
        updateProfileCompletePct,
      });

      await expect(
        service.recalculateCompletionIfMaterialized('user-1'),
      ).resolves.toBeUndefined();
      expect(updateProfileCompletePct).not.toHaveBeenCalled();
    });

    it("swallows unexpected errors too — a recalculation failure must never fail the caller's own action", async () => {
      const service = buildService({
        findProfileByUserId: jest.fn().mockRejectedValue(new Error('db down')),
      });

      await expect(
        service.recalculateCompletionIfMaterialized('user-1'),
      ).resolves.toBeUndefined();
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
        completionBreakdown: [],
        verificationBreakdown: [],
        requiredFields: [],
        registrationComplete: false,
        data: {
          basicDetails: {
            firstName: 'Arjun',
            lastName: 'Sundar',
            gender: 'MALE',
            maritalStatus: 'NEVER_MARRIED',
            profileCreatedFor: 'Self',
            dob: '1997-01-01',
          },
          religionDetails: {
            religion: 'Hindu',
            caste: 'Iyer',
            subCaste: 'Vadama',
            community: 'Brahmin',
          },
          languageDetails: {
            motherTongue: 'Tamil',
            languagesKnown: ['Tamil', 'English'],
          },
          locationDetails: {
            country: 'India',
            state: 'Tamil Nadu',
            city: 'Chennai',
            area: 'Anna Nagar',
            pinCode: '600040',
            nativePlace: 'Madurai',
          },
          educationDetails: {
            qualification: "Bachelor's",
            college: 'Anna University',
            occupation: 'Product Designer',
            company: 'Acme Corp',
            employmentType: 'Private',
            annualIncome: '10-15 Lakhs',
            workLocation: 'Chennai',
          },
          physicalDetails: {
            height: '178 cm',
            weight: '70 kg',
            disability: 'None',
          },
          ...overrides,
        },
      };
    }

    it('throws BadRequestException when required fields are missing', async () => {
      const service = buildService({
        getDraft: jest
          .fn()
          .mockResolvedValue(buildValidDraft({ basicDetails: {} })),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('queues the welcome email once the profile is finalized', async () => {
      const sendWelcome = jest.fn().mockResolvedValue(undefined);
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        sendWelcome,
      });

      await service.finalize('user-1');

      expect(sendWelcome).toHaveBeenCalledWith('user-1');
    });

    it('queues NO welcome email when finalize is rejected', async () => {
      // The registration never completed, so there is nothing to welcome them to.
      const sendWelcome = jest.fn().mockResolvedValue(undefined);
      const service = buildService({
        getDraft: jest
          .fn()
          .mockResolvedValue(buildValidDraft({ basicDetails: {} })),
        sendWelcome,
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
      expect(sendWelcome).not.toHaveBeenCalled();
    });

    it('still finalizes when queuing the welcome email fails', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        sendWelcome: jest.fn().mockRejectedValue(new Error('redis down')),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('finalizes without Sub Caste — it is optional now', async () => {
      // Sub-community is offered on the "Let's build your Profile" step but
      // never required (`sub_caste` is a nullable column), so demanding it at
      // finalize time would make the contract unsatisfiable for every profile
      // the current signup flow produces.
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            religionDetails: {
              religion: 'Hindu',
              caste: 'Iyer',
              community: 'Brahmin',
            },
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('finalizes with neither caste nor mother tongue', async () => {
      // The shape onboarding actually produces now. Both columns are nullable
      // as of migration 20260903120000; a finalize that rejected this would
      // block every member the current flow can create.
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            religionDetails: { religion: 'Hindu', community: 'Brahmin' },
            languageDetails: {},
          }),
        ),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('throws BadRequestException when Religion is the literal "Other" placeholder', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            religionDetails: {
              religion: 'Other',
              caste: 'Iyer',
              subCaste: 'Vadama',
              community: 'Brahmin',
            },
          }),
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

    it('stores the date of birth as the calendar date it names', async () => {
      const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile,
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await service.finalize('user-1');

      // UTC midnight of 1 January 1997 — not local midnight, which is what
      // `new Date('1997-01-01T00:00:00.000')` used to produce and which an
      // API server east of UTC stored as 31 December 1996.
      expect(upsertProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          dob: new Date('1997-01-01T00:00:00.000Z'),
        }),
      );
    });

    it('reads a legacy zone-less draft timestamp for the day it names', async () => {
      // What builds of the app before the date-only wire format wrote into
      // `draft_data`, and what is therefore still sitting in stored drafts.
      const draft = buildValidDraft();
      (draft.data.basicDetails as Record<string, unknown>).dob =
        '1997-01-01T00:00:00.000';
      const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(draft),
        upsertProfile,
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await service.finalize('user-1');

      expect(upsertProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          dob: new Date('1997-01-01T00:00:00.000Z'),
        }),
      );
    });

    it('refuses a draft whose stored date of birth names no calendar date', async () => {
      // Unreachable through the DTO, which rejects it on the way in — but a
      // draft written before that check existed can still hold one, and a
      // clear 400 beats Prisma rejecting an `Invalid Date` later.
      const draft = buildValidDraft();
      (draft.data.basicDetails as Record<string, unknown>).dob = '1997-02-31';
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(draft),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
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
              subCaste: 'Vadama',
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
              nativePlace: 'Madurai',
            },
            lifestyleDetails: {
              eatingHabit: 'Vegetarian',
              smoking: 'No',
              drinking: 'No',
              fitness: 'Regular',
              hobbies: ['Reading', 'Cricket'],
              aboutMe: 'Loves long walks.',
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
              rashi: 'Mesham',
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
            horoscopeDetails: {
              rashi: 'Mesham',
              nakshatra: 'Bharani',
              star: 'Ashwini',
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
        expect.objectContaining({ nakshatra: 'Bharani' }),
      );
    });

    it('does not throw when no profile photo has been uploaded — photos are skippable and must never block finalize', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(buildValidDraft()),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        findAllForUser: jest.fn().mockResolvedValue([]),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('throws when Physical is partially filled instead of skipped or completed', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            physicalDetails: { height: '178 cm' }, // weight, disability missing
          }),
        ),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('does not throw when Physical is left entirely empty (skipped)', async () => {
      const service = buildService({
        getDraft: jest
          .fn()
          .mockResolvedValue(buildValidDraft({ physicalDetails: {} })),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('throws when Education is partially filled instead of skipped or completed', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            educationDetails: { qualification: "Bachelor's" }, // occupation, college, etc. missing
          }),
        ),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('does not throw when Education is left entirely empty (skipped)', async () => {
      const service = buildService({
        getDraft: jest
          .fn()
          .mockResolvedValue(buildValidDraft({ educationDetails: {} })),
        upsertProfile: jest.fn().mockResolvedValue(buildProfile()),
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await expect(service.finalize('user-1')).resolves.toBeDefined();
    });

    it('throws when Lifestyle is partially filled instead of skipped or completed', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            lifestyleDetails: { eatingHabit: 'Vegetarian' }, // rest missing
          }),
        ),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('throws when Horoscope is touched but Rashi is missing', async () => {
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            horoscopeDetails: { birthPlace: 'Chennai' }, // no rashi
          }),
        ),
      });

      await expect(service.finalize('user-1')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('maps structured Father/Mother/Sibling records onto the profile columns', async () => {
      const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
      const service = buildService({
        getDraft: jest.fn().mockResolvedValue(
          buildValidDraft({
            familyDetails: {
              father: { name: 'Suresh', age: 58, occupation: 'Engineer' },
              mother: { name: 'Lakshmi', age: 54, occupation: 'Teacher' },
              siblings: [
                {
                  relation: 'BROTHER',
                  name: 'Karthik',
                  age: 30,
                  occupation: 'Doctor',
                },
                {
                  relation: 'SISTER',
                  name: 'Divya',
                  age: 26,
                  occupation: 'Designer',
                },
              ],
              familyStatus: 'Middle Class',
            },
          }),
        ),
        upsertProfile,
        findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
      });

      await service.finalize('user-1');

      expect(upsertProfile).toHaveBeenCalledWith(
        'user-1',
        expect.objectContaining({
          fatherName: 'Suresh',
          fatherAge: 58,
          fatherOccupation: 'Engineer',
          motherName: 'Lakshmi',
          motherAge: 54,
          motherOccupation: 'Teacher',
          siblings: 2,
          siblingDetails: [
            {
              relation: 'BROTHER',
              name: 'Karthik',
              age: 30,
              occupation: 'Doctor',
            },
            {
              relation: 'SISTER',
              name: 'Divya',
              age: 26,
              occupation: 'Designer',
            },
          ],
        }),
      );
    });

    // Regression coverage for a production bug: Step 5 (Education & Career)
    // and Step 6 (Physical Details) are both skippable, but UserProfile's
    // heightCm/highestEducation/profession columns were NOT NULL — so
    // finalize() crashed with a Prisma "Argument `highestEducation` is
    // missing" validation error for the single most common path through
    // this whole feature: a user who only fills the mandatory Steps 1-4.
    // Fixed by making those 3 columns nullable (see schema.prisma) and
    // writing real `null`, never a placeholder like `0`/`''`/`'Other'`.
    //
    // These tests wire a REAL ProfileCompletionService (not the mocked one
    // buildService() uses elsewhere in this file) so the asserted
    // percentages are actually computed, not just echoed back from a mock —
    // the mocked-completion tests above only prove ProfileService plumbs a
    // result through; these prove the number itself is right for this
    // exact scenario.
    describe('skippable Step 5/6 persistence (regression)', () => {
      // [photoCount] drives BOTH the photo repository's findAllForUser and
      // countForUser (the "photos" 12% completion slice) consistently — in
      // real Postgres they're the same profile_photos rows, so a test that
      // gave them different counts would assert something that can't
      // actually happen. Default 1: most tests below don't care about the
      // photos slice one way or the other, so they default to earning it —
      // see each test's own comment for the resulting total, and (A') above
      // for the explicit photoCount: 0 proof that finalize() never requires
      // a photo to succeed.
      function buildServiceWithRealCompletion(overrides: {
        getDraft: jest.Mock;
        upsertProfile: jest.Mock;
        findProfileByUserId: jest.Mock;
        photoCount?: number;
      }) {
        const photoCount = overrides.photoCount ?? 1;
        const updateProfileCompletePct = jest.fn();
        const profileRepository = {
          upsertProfile: overrides.upsertProfile,
          upsertAstrologyProfile: jest.fn(),
          upsertPartnerPreference: jest.fn(),
          markComplete: jest.fn(),
          findProfileByUserId: overrides.findProfileByUserId,
          findPartnerPreference: jest.fn().mockResolvedValue(null),
          findAstrologyProfile: jest.fn().mockResolvedValue(null),
          updateProfileCompletePct,
          // Not called on this path: recalculateAndPersistCompletion is
          // given the just-finalized draftData directly (see finalize()),
          // so ProfileCompletionService never has to re-fetch the step.
          getOrCreateRegistrationStep: jest.fn(),
        } as unknown as ProfileRepository;

        const photoRepository = {
          findAllForUser: jest
            .fn()
            .mockResolvedValue(
              Array.from({ length: photoCount }, () => buildPhoto()),
            ),
          countForUser: jest.fn().mockResolvedValue(photoCount),
        } as unknown as PhotoRepository;

        const prisma = {
          user: { findUnique: jest.fn().mockResolvedValue({ phone: null }) },
          kycVerification: { findMany: jest.fn().mockResolvedValue([]) },
          userQuizResponse: { count: jest.fn().mockResolvedValue(0) },
        } as unknown as PrismaService;

        const completionService = new ProfileCompletionService(
          prisma,
          profileRepository,
          photoRepository,
        );

        const draftService = {
          getDraft: overrides.getDraft,
        } as unknown as ProfileDraftService;

        const service = new ProfileService(
          profileRepository,
          photoRepository,
          draftService,
          completionService,
          { sendWelcome: jest.fn().mockResolvedValue(undefined) } as never,
      // Feed invalidation is fire-and-forget bookkeeping after a successful
      // write; these tests assert the write, not the cache signalling.
      { invalidate: jest.fn(), invalidatePair: jest.fn() } as unknown as FeedInvalidationService,
      // S3 stub reporting "not configured", so getOwn()'s presigning step
      // is a no-op and photo `cdnUrl`s reach these assertions exactly as the
      // repository returned them — these tests are about profile assembly,
      // not URL signing (see photo.service.spec.ts for that).
      { isConfigured: () => false } as unknown as S3Service,
    );
        return { service, updateProfileCompletePct };
      }

      it('(A) Steps 1-4 complete, Step 5 skipped -> finalize succeeds (no crash) with education contributing 0%', async () => {
        // buildServiceWithRealCompletion defaults to 1 photo (unrelated to
        // this test's point — see the dedicated 0-photo regression test
        // below for proof finalize() doesn't require one), so this earns
        // the photos 12% too — total here is 20 (mandatory) + 12 (photos)
        // = 32, not the pure 20 the spec describes for "mandatory only".
        // That exact "20%, no photo yet" scenario is the real
        // first-failure point in production (syncMatchableFromDraft fires
        // — and used to crash — the moment Step 4 is saved, long before
        // any photo exists) and is covered precisely by test (B) below and
        // by profile-completion.service.spec.ts's "awards exactly 20 once
        // all four mandatory steps are complete" test.
        const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
        const { service } = buildServiceWithRealCompletion({
          getDraft: jest
            .fn()
            .mockResolvedValue(
              buildValidDraft({ educationDetails: {}, physicalDetails: {} }),
            ),
          upsertProfile,
          findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        });

        const result = await service.finalize('user-1');

        // 12 of the 21 registration items: the eleven Steps 1-4 answer (six
        // basic, religion, community, country, state, city) plus the photo.
        // round(60 * 12/21) = 34. Skipping Step 5 costs the education answers
        // themselves now, not a separate module.
        expect(result.completion.percentage).toBe(34);
        // There is no separate 'education' module any more — its answers are
        // registration fields. Their absence shows as an incomplete
        // registration slice, named field by field.
        expect(result.completion.registrationComplete).toBe(false);
        expect(
          result.completion.requiredFields
            .filter((f) => !f.isComplete)
            .map((f) => f.id),
        ).toEqual(
          expect.arrayContaining(['qualification', 'college', 'company']),
        );
      });

      it("(A') Steps 1-4 complete, Steps 5-13 all skipped, no photo, mobile unverified -> finalize succeeds", async () => {
        // The exact scenario from the final access rule: only Steps 1-4
        // are mandatory. Nothing else — not a photo, not any verification
        // — may block finalize() or keep the user off Discover.
        const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
        const { service } = buildServiceWithRealCompletion({
          getDraft: jest
            .fn()
            .mockResolvedValue(
              buildValidDraft({ educationDetails: {}, physicalDetails: {} }),
            ),
          upsertProfile,
          findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
          photoCount: 0,
        });

        const result = await service.finalize('user-1');

        // 11 of 21 items — no photo either. round(60 * 11/21) = 31. What
        // this regression guards is unchanged: finalize SUCCEEDS and the
        // member is marked complete regardless of the number.
        expect(result.completion.percentage).toBe(31);
        expect(result.completion.completedSections).toEqual([]);
        expect(result.completion.registrationComplete).toBe(false);
        expect(upsertProfile).toHaveBeenCalledWith(
          'user-1',
          expect.objectContaining({ isProfileComplete: true }),
        );
      });

      it('(B) Step 5 partially entered mid-wizard must not earn its 10% even though the partial value is persisted', async () => {
        // finalize() itself rejects a partial Education (see the "throws
        // when Education is partially filled" test above) — but
        // syncMatchableFromDraft(), which runs on every wizard step save,
        // does not enforce that same validity check (by design — see its
        // own doc comment), so a partial value CAN reach
        // writeProfileFromDraft() before the user ever reaches Review. That
        // write must not crash (nullable columns) and must not earn credit
        // for an incomplete section (completion is derived from draftData's
        // validity, not from whatever ended up in the columns).
        const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
        const { service, updateProfileCompletePct } =
          buildServiceWithRealCompletion({
            getDraft: jest.fn(),
            upsertProfile,
            findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
            // No photo yet — this is syncMatchableFromDraft, fired the
            // moment Step 4 is saved, well before Step 12 (Photos).
            photoCount: 0,
          });
        const partialDraft = {
          basicDetails: {
            firstName: 'Arjun',
            lastName: 'Sundar',
            gender: 'MALE',
            maritalStatus: 'NEVER_MARRIED',
            profileCreatedFor: 'Self',
            dob: '1997-01-01',
          },
          religionDetails: {
            religion: 'Hindu',
            caste: 'Iyer',
            subCaste: 'Vadama',
            community: 'Brahmin',
          },
          languageDetails: {
            motherTongue: 'Tamil',
            languagesKnown: ['Tamil'],
          },
          locationDetails: {
            country: 'India',
            state: 'Tamil Nadu',
            city: 'Chennai',
            area: 'Anna Nagar',
            pinCode: '600040',
            nativePlace: 'Madurai',
          },
          // Touched but invalid — qualification only, no occupation/etc.
          educationDetails: { qualification: "Bachelor's" },
        };

        await expect(
          service.syncMatchableFromDraft('user-1', partialDraft),
        ).resolves.toBeUndefined();

        expect(upsertProfile).toHaveBeenCalledWith(
          'user-1',
          expect.objectContaining({
            highestEducation: "Bachelor's",
            profession: null,
          }),
        );
        // 12 of 21: the eleven from Steps 1-4 plus `qualification`, which
        // this partial draft does supply. round(60 * 12/21) = 34. The other
        // six work answers are still missing, which is what a partially
        // entered Step 5 means.
        expect(updateProfileCompletePct).toHaveBeenCalledWith('user-1', 34);
      });

      it('(C) Steps 1-4 complete + valid Step 5 -> finalize succeeds (education contributing its 10%)', async () => {
        // Same default-photo caveat as test (A) — buildServiceWithRealCompletion's
        // default 1 photo means this lands at 42, not the pure 30 the spec
        // describes for "mandatory + Education" alone; see the pure-30 case
        // right below via syncMatchableFromDraft (no photo requirement).
        const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
        const { service } = buildServiceWithRealCompletion({
          getDraft: jest
            .fn()
            .mockResolvedValue(buildValidDraft({ physicalDetails: {} })),
          upsertProfile,
          findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        });

        const result = await service.finalize('user-1');

        // 18 of 21 items: Steps 1-4's eleven, the six education answers, and
        // the photo. Height, diet and workIndustry are still blank.
        // round(60 * 18/21) = 51.
        expect(result.completion.percentage).toBe(51);
        // Supplying Step 5 completes those registration fields rather than a
        // module of their own.
        expect(
          result.completion.requiredFields
            .filter((f) => !f.isComplete)
            .map((f) => f.id),
        ).toEqual(['height', 'diet', 'workIndustry']);
      });

      it("(C') Steps 1-4 complete + valid Step 5, no photo yet -> education earns its 10%", async () => {
        const upsertProfile = jest.fn().mockResolvedValue(buildProfile());
        const { service, updateProfileCompletePct } =
          buildServiceWithRealCompletion({
            getDraft: jest.fn(),
            upsertProfile,
            findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
            photoCount: 0,
          });
        const draftWithValidEducation = {
          basicDetails: {
            firstName: 'Arjun',
            lastName: 'Sundar',
            gender: 'MALE',
            maritalStatus: 'NEVER_MARRIED',
            profileCreatedFor: 'Self',
            dob: '1997-01-01',
          },
          religionDetails: {
            religion: 'Hindu',
            caste: 'Iyer',
            subCaste: 'Vadama',
            community: 'Brahmin',
          },
          languageDetails: {
            motherTongue: 'Tamil',
            languagesKnown: ['Tamil'],
          },
          locationDetails: {
            country: 'India',
            state: 'Tamil Nadu',
            city: 'Chennai',
            area: 'Anna Nagar',
            pinCode: '600040',
            nativePlace: 'Madurai',
          },
          educationDetails: {
            qualification: "Bachelor's",
            college: 'Anna University',
            occupation: 'Engineer',
            company: 'Acme Corp',
            employmentType: 'Private',
            annualIncome: '10',
            workLocation: 'Chennai',
          },
        };

        await service.syncMatchableFromDraft('user-1', draftWithValidEducation);

        // 17 of 21 items — the same seventeen answers, no photo.
        // round(60 * 17/21) = 49.
        expect(updateProfileCompletePct).toHaveBeenCalledWith('user-1', 49);
      });

      it('(D) no fake/default education or height values are ever persisted when skipped', async () => {
        const upsertProfile = jest
          .fn<Promise<ProfileEntity>, [string, Record<string, unknown>]>()
          .mockResolvedValue(buildProfile());
        const { service } = buildServiceWithRealCompletion({
          getDraft: jest
            .fn()
            .mockResolvedValue(
              buildValidDraft({ educationDetails: {}, physicalDetails: {} }),
            ),
          upsertProfile,
          findProfileByUserId: jest.fn().mockResolvedValue(buildProfile()),
        });

        await service.finalize('user-1');

        expect(upsertProfile).toHaveBeenCalledWith(
          'user-1',
          expect.objectContaining({
            heightCm: null,
            highestEducation: null,
            profession: null,
          }),
        );
        const written = upsertProfile.mock.calls[0][1];
        expect(Object.values(written)).not.toContain('Other');
        expect(Object.values(written)).not.toContain('N/A');
        expect(written.heightCm).not.toBe(0);
      });
    });
  });
});
