import { ProfileCompletionService } from '../services/profile-completion.service';
import type { ProfileRepository } from '../repositories/profile.repository';
import type { PhotoRepository } from '../repositories/photo.repository';
import type { RecommendationDismissalRepository } from '../repositories/recommendation-dismissal.repository';
import type { PrismaService } from '@app/database';
import { RECOMMENDATION_CARDS } from '../domain/recommendation-cards';

/**
 * The "Complete Your Profile" recommendation cards.
 *
 * Two things are being pinned here, and they are the two that keep Home and
 * Edit Profile honest:
 *
 *  1. A card's `isComplete` is the SAME signal that scored its module — there
 *     is no second completion rule anywhere — so a card can never contradict
 *     the percentage rendered beside it.
 *  2. `psychology` is offered without being counted. It carries no weight, it
 *     is absent from `breakdown`, and finishing it moves nothing. The
 *     arithmetic tests below exist because "optional for now" is exactly the
 *     kind of promise that quietly stops being true.
 */

// The 20 counted registration answers, all present — the same fixture shape
// profile-completion.service.spec.ts uses, kept local so a change to the card
// tests can never perturb the scoring tests.
const REGISTRATION_ANSWERED = {
  basicDetails: {
    firstName: 'Arjun',
    lastName: 'Sundar',
    gender: 'MALE',
    dob: '1997-01-01',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Self',
  },
  physicalDetails: { height: '5ft 9in' },
  lifestyleDetails: { eatingHabit: 'Vegetarian' },
  educationDetails: {
    qualification: 'Bachelors',
    college: 'Anna University',
    annualIncome: '10',
    employmentType: 'Private',
    workIndustry: 'IT / Software',
    occupation: 'Engineer',
    company: 'Acme Corp',
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
};

const FAMILY_COMPLETE = {
  familyType: 'Nuclear',
  familyStatus: 'Middle Class',
  familyValues: 'Moderate',
  fatherOccupation: 'Retired',
  motherOccupation: 'Homemaker',
  siblings: '1',
};

const HOROSCOPE_COMPLETE = {
  timeOfBirth: '10:30',
  placeOfBirth: 'Chennai',
  star: 'Ashwini',
  rashi: 'Mesham',
  birthPlace: 'Chennai',
};

type Overrides = {
  draftData?: Record<string, unknown>;
  photoCount?: number;
  phone?: string | null;
  approvedDocTypes?: string[];
  quizResponseCount?: number;
  dismissedCardKeys?: string[];
  hasPartnerPreferenceRow?: boolean;
};

function buildService(overrides: Overrides = {}) {
  const profileRepository = {
    getOrCreateRegistrationStep: jest.fn(),
  } as unknown as ProfileRepository;

  const photoRepository = {
    countForUser: jest.fn().mockResolvedValue(overrides.photoCount ?? 0),
  } as unknown as PhotoRepository;

  const prisma = {
    user: {
      findUnique: jest
        .fn()
        .mockResolvedValue({ phone: overrides.phone ?? null }),
    },
    kycVerification: {
      findMany: jest
        .fn()
        .mockResolvedValue(
          (overrides.approvedDocTypes ?? []).map((docType) => ({ docType })),
        ),
    },
    userQuizResponse: {
      count: jest.fn().mockResolvedValue(overrides.quizResponseCount ?? 0),
    },
    partnerPreference: {
      findUnique: jest
        .fn()
        .mockResolvedValue(
          overrides.hasPartnerPreferenceRow ? { userId: 'user-1' } : null,
        ),
    },
  } as unknown as PrismaService;

  const findKeysForUser = jest
    .fn()
    .mockResolvedValue(overrides.dismissedCardKeys ?? []);

  const dismissalRepository = {
    findKeysForUser,
    dismiss: jest.fn(),
    restore: jest.fn(),
  } as unknown as RecommendationDismissalRepository;

  const service = new ProfileCompletionService(
    prisma,
    profileRepository,
    photoRepository,
    dismissalRepository,
  );

  return {
    findKeysForUser,
    calculate: () => service.calculate('user-1', overrides.draftData ?? {}),
  };
}

type CalculateResult = Awaited<
  ReturnType<ReturnType<typeof buildService>['calculate']>
>;

function card(result: CalculateResult, key: string) {
  const found = result.recommendations.find((r) => r.key === key);
  if (!found) throw new Error('no recommendation card: ' + key);
  return found;
}

/** A profile with everything registration asks for, including a photo. */
const REGISTERED = {
  draftData: REGISTRATION_ANSWERED,
  photoCount: 1,
};

describe('completion recommendations', () => {
  it('lists every known card, in the catalogue order', async () => {
    const result = await buildService(REGISTERED).calculate();

    expect(result.recommendations.map((r) => r.key)).toEqual(
      RECOMMENDATION_CARDS.map((c) => c.key),
    );
  });

  it('each card carries the wizard step the client opens for it', async () => {
    const result = await buildService(REGISTERED).calculate();

    // These are the routes profileSectionRoute() already maps: family and
    // horoscope are Edit Profile sections, psychology and verification are
    // pages of their own.
    expect(card(result, 'about_family').wizardStep).toBe(7);
    expect(card(result, 'horoscope').wizardStep).toBe(8);
    expect(card(result, 'psychology').wizardStep).toBe(9);
    expect(card(result, 'verification').wizardStep).toBe(12);
    expect(card(result, 'photo').wizardStep).toBe(11);
  });

  describe('a card is complete exactly when its section is', () => {
    it('family is incomplete until the family section is', async () => {
      const before = await buildService(REGISTERED).calculate();
      expect(card(before, 'about_family').isComplete).toBe(false);

      const after = await buildService({
        ...REGISTERED,
        draftData: {
          ...REGISTRATION_ANSWERED,
          familyDetails: FAMILY_COMPLETE,
        },
      }).calculate();

      expect(card(after, 'about_family').isComplete).toBe(true);
      // And the card's state agrees with the module that scored it.
      expect(after.breakdown.find((m) => m.id === 'family')!.isComplete).toBe(
        true,
      );
    });

    it('horoscope is incomplete until the horoscope section is', async () => {
      const after = await buildService({
        ...REGISTERED,
        draftData: {
          ...REGISTRATION_ANSWERED,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
      }).calculate();

      expect(card(after, 'horoscope').isComplete).toBe(true);
      expect(
        after.breakdown.find((m) => m.id === 'horoscope')!.isComplete,
      ).toBe(true);
    });

    it('verification completes only when all five checks pass', async () => {
      const partial = await buildService({
        ...REGISTERED,
        phone: '+919876543210',
        approvedDocTypes: ['AADHAAR'],
      }).calculate();
      expect(card(partial, 'verification').isComplete).toBe(false);

      const all = await buildService({
        ...REGISTERED,
        phone: '+919876543210',
        approvedDocTypes: [
          'AADHAAR',
          'INCOME_PROOF',
          'ASSET_PROOF',
          'NRI_PROOF',
        ],
      }).calculate();
      expect(card(all, 'verification').isComplete).toBe(true);
    });

    it('psychology completes on a submitted quiz response', async () => {
      const before = await buildService(REGISTERED).calculate();
      expect(card(before, 'psychology').isComplete).toBe(false);

      const after = await buildService({
        ...REGISTERED,
        quizResponseCount: 1,
      }).calculate();
      expect(card(after, 'psychology').isComplete).toBe(true);
    });
  });

  describe('the psychology card never touches the percentage', () => {
    it('taking the quiz changes nothing about the score', async () => {
      const without = await buildService(REGISTERED).calculate();
      const withQuiz = await buildService({
        ...REGISTERED,
        quizResponseCount: 1,
      }).calculate();

      expect(withQuiz.percentage).toBe(without.percentage);
      expect(withQuiz.breakdown).toEqual(without.breakdown);
    });

    it('is flagged as not affecting the score, like partner_preference and unlike every other card', async () => {
      const result = await buildService(REGISTERED).calculate();

      expect(card(result, 'psychology').affectsScore).toBe(false);
      expect(
        result.recommendations
          .filter(
            (r) => r.key !== 'psychology' && r.key !== 'partner_preference',
          )
          .every((r) => r.affectsScore),
      ).toBe(true);
    });

    it('has no module and no weight in the breakdown', async () => {
      const result = await buildService({
        ...REGISTERED,
        quizResponseCount: 1,
      }).calculate();

      expect(
        result.breakdown.find((m) => m.id === 'psychology'),
      ).toBeUndefined();
      // The approved formula, still exactly 100 across the four slices.
      expect(result.breakdown.reduce((sum, m) => sum + m.weight, 0)).toBe(100);
    });

    it('a fully complete profile reads 100% with the quiz untaken', async () => {
      const result = await buildService({
        draftData: {
          ...REGISTRATION_ANSWERED,
          familyDetails: FAMILY_COMPLETE,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
        photoCount: 1,
        phone: '+919876543210',
        approvedDocTypes: [
          'AADHAAR',
          'INCOME_PROOF',
          'ASSET_PROOF',
          'NRI_PROOF',
        ],
        quizResponseCount: 0,
      }).calculate();

      expect(result.percentage).toBe(100);
      expect(card(result, 'psychology').isComplete).toBe(false);
    });
  });

  describe('the partner_preference card never touches the percentage', () => {
    it('saving preferences changes nothing about the score', async () => {
      const without = await buildService(REGISTERED).calculate();
      const withPreferences = await buildService({
        ...REGISTERED,
        hasPartnerPreferenceRow: true,
      }).calculate();

      expect(withPreferences.percentage).toBe(without.percentage);
      expect(withPreferences.breakdown).toEqual(without.breakdown);
    });

    it('has no module and no weight in the breakdown', async () => {
      const result = await buildService({
        ...REGISTERED,
        hasPartnerPreferenceRow: true,
      }).calculate();

      expect(
        result.breakdown.find((m) => m.id === 'partner_preference'),
      ).toBeUndefined();
      expect(result.breakdown.reduce((sum, m) => sum + m.weight, 0)).toBe(100);
    });

    it('is incomplete until a PartnerPreference row is saved', async () => {
      const before = await buildService(REGISTERED).calculate();
      expect(card(before, 'partner_preference').isComplete).toBe(false);

      const after = await buildService({
        ...REGISTERED,
        hasPartnerPreferenceRow: true,
      }).calculate();
      expect(card(after, 'partner_preference').isComplete).toBe(true);
      expect(card(after, 'partner_preference').wizardStep).toBe(10);
    });
  });

  describe('registration cards', () => {
    it('are both complete once registration is', async () => {
      const result = await buildService(REGISTERED).calculate();

      expect(result.registrationComplete).toBe(true);
      expect(card(result, 'registration').isComplete).toBe(true);
      expect(card(result, 'photo').isComplete).toBe(true);
    });

    it('a missing photo leaves the photo card open, not the answers card', async () => {
      const result = await buildService({
        draftData: REGISTRATION_ANSWERED,
        photoCount: 0,
      }).calculate();

      expect(result.registrationComplete).toBe(false);
      // Every answer is given — only the upload is missing, so only the
      // photo card should still be asking for something.
      expect(card(result, 'registration').isComplete).toBe(true);
      expect(card(result, 'photo').isComplete).toBe(false);
    });

    it('a missing answer leaves the answers card open', async () => {
      const result = await buildService({
        draftData: {
          ...REGISTRATION_ANSWERED,
          educationDetails: {
            ...REGISTRATION_ANSWERED.educationDetails,
            occupation: '',
          },
        },
        photoCount: 1,
      }).calculate();

      expect(result.registrationComplete).toBe(false);
      expect(card(result, 'registration').isComplete).toBe(false);
      expect(card(result, 'photo').isComplete).toBe(true);
    });

    it('the optional sub-community never holds the card open', async () => {
      const religionWithoutSubCaste = {
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Brahmin',
      };

      const result = await buildService({
        draftData: {
          ...REGISTRATION_ANSWERED,
          religionDetails: religionWithoutSubCaste,
        },
        photoCount: 1,
      }).calculate();

      expect(card(result, 'registration').isComplete).toBe(true);
      expect(result.registrationComplete).toBe(true);
    });
  });

  describe('dismissals', () => {
    it('flags exactly the dismissed cards', async () => {
      const result = await buildService({
        ...REGISTERED,
        dismissedCardKeys: ['horoscope', 'psychology'],
      }).calculate();

      expect(card(result, 'horoscope').isDismissed).toBe(true);
      expect(card(result, 'psychology').isDismissed).toBe(true);
      expect(card(result, 'about_family').isDismissed).toBe(false);
      expect(card(result, 'verification').isDismissed).toBe(false);
    });

    it('never changes the percentage or the section completion state', async () => {
      const plain = await buildService(REGISTERED).calculate();
      const dismissed = await buildService({
        ...REGISTERED,
        dismissedCardKeys: ['horoscope', 'about_family', 'verification'],
      }).calculate();

      // The whole point: hiding the suggestion leaves the data — and
      // therefore the score — exactly where it was.
      expect(dismissed.percentage).toBe(plain.percentage);
      expect(dismissed.breakdown).toEqual(plain.breakdown);
      expect(card(dismissed, 'horoscope').isComplete).toBe(
        card(plain, 'horoscope').isComplete,
      );
    });

    it('a dismissed card that is later completed reports both', async () => {
      const result = await buildService({
        ...REGISTERED,
        draftData: {
          ...REGISTRATION_ANSWERED,
          familyDetails: FAMILY_COMPLETE,
        },
        dismissedCardKeys: ['about_family'],
      }).calculate();

      expect(card(result, 'about_family').isComplete).toBe(true);
      expect(card(result, 'about_family').isDismissed).toBe(true);
    });

    it('an unknown stored key cannot invent a card', async () => {
      const result = await buildService({
        ...REGISTERED,
        dismissedCardKeys: ['something_this_build_never_heard_of'],
      }).calculate();

      expect(result.recommendations.map((r) => r.key)).toEqual(
        RECOMMENDATION_CARDS.map((c) => c.key),
      );
      expect(result.recommendations.every((r) => !r.isDismissed)).toBe(true);
    });

    it('reads the dismissals for the calling user only', async () => {
      const { findKeysForUser, calculate } = buildService(REGISTERED);
      await calculate();

      expect(findKeysForUser).toHaveBeenCalledWith('user-1');
    });
  });
});
