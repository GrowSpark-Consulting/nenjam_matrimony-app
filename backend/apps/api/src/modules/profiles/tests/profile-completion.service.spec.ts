import { ProfileCompletionService } from '../services/profile-completion.service';
import type { ProfileRepository } from '../repositories/profile.repository';
import type { PhotoRepository } from '../repositories/photo.repository';
import type { PrismaService } from '@app/database';

/**
 * Every one of the 20 counted registration fields, answered.
 *
 * The 'registration' slice is scored field by field (see
 * validation/required-fields.ts), so "mandatory complete" now means all 20
 * answers are present — not merely that the four section rules pass, which
 * they can while height, diet and the whole work section are still blank.
 *
 * Deliberately stops short of completing the education, physical and
 * lifestyle MODULES: those require fields beyond the 20 (workLocation;
 * weight + disability; smoking/drinking/fitness/hobbies/aboutMe). So this
 * fixture still earns exactly 20 and nothing else, which is what every
 * arithmetic test below is built on.
 */
const MANDATORY_COMPLETE = {
  basicDetails: {
    firstName: 'Arjun',
    lastName: 'Sundar',
    gender: 'MALE',
    dob: '1997-01-01',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Self',
  },
  // Field 13 and field 14. Present here, but each section needs more than
  // this one field to earn its own module.
  physicalDetails: { height: "5'9" },
  lifestyleDetails: { eatingHabit: 'Vegetarian' },
  // Fields 15-21, minus workLocation, which the education MODULE needs but
  // the required-field list does not.
  educationDetails: {
    qualification: "Bachelor's",
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

const EDUCATION_COMPLETE = {
  qualification: "Bachelor's",
  college: 'Anna University',
  occupation: 'Engineer',
  company: 'Acme Corp',
  employmentType: 'Private',
  workIndustry: 'IT / Software',
  annualIncome: '10',
  workLocation: 'Chennai',
};

const PHYSICAL_COMPLETE = {
  height: `5'9"`,
  weight: '68 kg',
  disability: 'None',
};

const LIFESTYLE_COMPLETE = {
  eatingHabit: 'Vegetarian',
  smoking: 'No',
  drinking: 'No',
  fitness: 'Regular',
  hobbies: ['Reading'],
  aboutMe: 'Loves long walks.',
};

const FAMILY_COMPLETE = {
  familyType: 'Nuclear',
  familyValues: 'Traditional',
};

const HOROSCOPE_COMPLETE = {
  rashi: 'Mesham',
  birthPlace: 'Chennai',
};

const PARTNER_PREF_TOUCHED = {
  preferredAgeRange: '25-30',
};

type Overrides = {
  draftData?: Record<string, unknown>;
  photoCount?: number;
  phone?: string | null;
  approvedDocTypes?: string[];
  quizResponseCount?: number;
};

function buildService(overrides: Overrides = {}) {
  const profileRepository = {
    getOrCreateRegistrationStep: jest.fn(),
  } as unknown as ProfileRepository;

  const photoRepository = {
    countForUser: jest.fn().mockResolvedValue(overrides.photoCount ?? 0),
  } as unknown as PhotoRepository;

  // kycFindMany is kept as its own reference (not read back off `prisma`)
  // so assertions on the where-clause target a plain jest.fn(), not a value
  // typed as PrismaService's instance method.
  const kycFindMany = jest
    .fn()
    .mockResolvedValue(
      (overrides.approvedDocTypes ?? []).map((docType) => ({ docType })),
    );
  const prisma = {
    user: {
      findUnique: jest
        .fn()
        .mockResolvedValue({ phone: overrides.phone ?? null }),
    },
    kycVerification: {
      findMany: kycFindMany,
    },
    userQuizResponse: {
      count: jest.fn().mockResolvedValue(overrides.quizResponseCount ?? 0),
    },
  } as unknown as PrismaService;

  const service = new ProfileCompletionService(
    prisma,
    profileRepository,
    photoRepository,
  );

  return {
    service,
    kycFindMany,
    calculate: () => service.calculate('user-1', overrides.draftData ?? {}),
  };
}

/**
 * The four-slice completion score.
 *
 * Registration information is 60 of the 100, earned over its 21 items — the
 * 20 counted draft fields plus at least one profile photo. What remains after
 * registration is exactly what the completion screen asks for: About Family
 * (10), Horoscope (5) and Verification (25), all three unchanged in weight and
 * in rule.
 *
 * The seven modules this replaced (education, physical, lifestyle, psychology,
 * partner preference, photos, and the old all-or-nothing registration) each
 * demanded more than registration collects, so a member who answered every
 * registration question scored 20% and was docked for questions nobody had
 * asked them. Those extra fields are now simply optional and unscored.
 */
describe('ProfileCompletionService', () => {
  /** A newly registered member: every registration field answered. */
  const registrationAnswered = { ...MANDATORY_COMPLETE };

  /** Registration done, a photo uploaded, phone verified by the signup. */
  const newUser = {
    draftData: registrationAnswered,
    photoCount: 1,
    phone: '+919000000000',
  };

  describe('a newly registered user', () => {
    it('scores the full 60 for registration', async () => {
      const { calculate } = buildService({
        draftData: registrationAnswered,
        photoCount: 1,
      });
      const result = await calculate();

      const registration = result.breakdown.find(
        (m) => m.id === 'registration',
      );
      expect(registration?.earned).toBe(60);
      expect(registration?.weight).toBe(60);
      expect(registration?.isComplete).toBe(true);
      expect(result.registrationComplete).toBe(true);
    });

    it('reaches 65% with mobile verified, and asks only for what is left', async () => {
      const result = await buildService(newUser).calculate();

      expect(result.percentage).toBe(65);
      expect(result.missingSections).toEqual([
        'family',
        'horoscope',
        'verification',
      ]);
      expect(result.completedSections).toEqual(['registration']);
    });

    it('lists no registration field as missing', async () => {
      // The whole point: a member must not be asked again for what they just
      // gave. requiredFields stays populated for deep-linking, but every entry
      // is complete and registrationComplete tells the client to hide the
      // group.
      const result = await buildService(newUser).calculate();

      expect(result.registrationComplete).toBe(true);
      expect(result.requiredFields.filter((f) => !f.isComplete)).toEqual([]);
      // 21 draft fields (sub-community included, though it never counts) plus
      // the photo.
      expect(result.requiredFields).toHaveLength(22);
    });
  });

  describe('the sections that remain', () => {
    it('About Family adds its unchanged 10', async () => {
      const { calculate } = buildService({
        ...newUser,
        draftData: { ...registrationAnswered, familyDetails: FAMILY_COMPLETE },
      });
      const result = await calculate();
      expect(result.percentage).toBe(75);
      expect(result.missingSections).toEqual(['horoscope', 'verification']);
    });

    it('Horoscope adds its unchanged 5', async () => {
      const { calculate } = buildService({
        ...newUser,
        draftData: {
          ...registrationAnswered,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
      });
      const result = await calculate();
      expect(result.percentage).toBe(70);
      expect(result.missingSections).toEqual(['family', 'verification']);
    });

    it('missing About Family costs exactly 10', async () => {
      const withFamily = buildService({
        ...newUser,
        draftData: { ...registrationAnswered, familyDetails: FAMILY_COMPLETE },
      });
      expect((await withFamily.calculate()).percentage).toBe(75);
      expect((await buildService(newUser).calculate()).percentage).toBe(65);
    });

    it('missing Horoscope costs exactly 5', async () => {
      const withHoroscope = buildService({
        ...newUser,
        draftData: {
          ...registrationAnswered,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
      });
      expect((await withHoroscope.calculate()).percentage).toBe(70);
      expect((await buildService(newUser).calculate()).percentage).toBe(65);
    });

    it('everything answered and every check verified is exactly 100', async () => {
      const { calculate } = buildService({
        draftData: {
          ...registrationAnswered,
          familyDetails: FAMILY_COMPLETE,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
        photoCount: 1,
        phone: '+919000000000',
        approvedDocTypes: [
          'INCOME_PROOF',
          'ASSET_PROOF',
          'AADHAAR',
          'NRI_PROOF',
        ],
      });
      const result = await calculate();
      expect(result.percentage).toBe(100);
      expect(result.missingSections).toEqual([]);
    });

    it('the four weights sum to exactly 100', async () => {
      const result = await buildService({
        draftData: registrationAnswered,
      }).calculate();
      expect(result.breakdown.map((m) => m.id)).toEqual([
        'registration',
        'family',
        'horoscope',
        'verification',
      ]);
      expect(result.breakdown.reduce((sum, m) => sum + m.weight, 0)).toBe(100);
    });

    it('does not score the fields registration never asks for', async () => {
      // Work location, weight, disability, smoking/drinking/fitness/hobbies/
      // about-me, the quiz and partner preferences are all optional now.
      // Supplying them must not move the number.
      const embellished = buildService({
        ...newUser,
        draftData: {
          ...registrationAnswered,
          physicalDetails: PHYSICAL_COMPLETE,
          lifestyleDetails: LIFESTYLE_COMPLETE,
          educationDetails: EDUCATION_COMPLETE,
          partnerPreference: PARTNER_PREF_TOUCHED,
        },
        quizResponseCount: 12,
      });
      expect((await embellished.calculate()).percentage).toBe(
        (await buildService(newUser).calculate()).percentage,
      );
    });
  });

  describe('the profile photo is a registration item', () => {
    it('a photo-less new user is short exactly one of 21 items', async () => {
      const { calculate } = buildService({
        draftData: registrationAnswered,
        photoCount: 0,
        phone: '+919000000000',
      });
      const result = await calculate();

      // round(60 * 20/21) = 57, plus the 5 for mobile.
      expect(
        result.breakdown.find((m) => m.id === 'registration')!.earned,
      ).toBe(57);
      expect(result.percentage).toBe(62);
      expect(result.registrationComplete).toBe(false);

      const photo = result.requiredFields.find((f) => f.id === 'photo')!;
      expect(photo.isComplete).toBe(false);
      expect(photo.wizardStep).toBe(11);
    });

    it('so a profile with no photo can never read 100%', async () => {
      const { calculate } = buildService({
        draftData: {
          ...registrationAnswered,
          familyDetails: FAMILY_COMPLETE,
          horoscopeDetails: HOROSCOPE_COMPLETE,
        },
        photoCount: 0,
        phone: '+919000000000',
        approvedDocTypes: [
          'INCOME_PROOF',
          'ASSET_PROOF',
          'AADHAAR',
          'NRI_PROOF',
        ],
      });
      expect((await calculate()).percentage).toBe(97);
    });
  });

  describe('a legacy profile', () => {
    it('names only the fields it genuinely lacks', async () => {
      const legacy = {
        ...registrationAnswered,
        physicalDetails: {},
        lifestyleDetails: {},
        educationDetails: {
          ...MANDATORY_COMPLETE.educationDetails,
          workIndustry: '',
        },
      };
      const result = await buildService({
        draftData: legacy,
        photoCount: 1,
      }).calculate();

      expect(result.registrationComplete).toBe(false);
      expect(
        result.requiredFields.filter((f) => !f.isComplete).map((f) => f.id),
      ).toEqual(['height', 'diet', 'workIndustry']);
      // 18 of 21 items -> round(60 * 18/21) = 51.
      expect(result.percentage).toBe(51);
    });

    it('a profile from before workIndustry existed loses only that one', async () => {
      const result = await buildService({
        draftData: {
          ...registrationAnswered,
          educationDetails: {
            ...MANDATORY_COMPLETE.educationDetails,
            workIndustry: '',
          },
        },
        photoCount: 1,
      }).calculate();

      expect(
        result.requiredFields.filter((f) => !f.isComplete).map((f) => f.id),
      ).toEqual(['workIndustry']);
      // 20 of 21 -> round(60 * 20/21) = 57.
      expect(result.percentage).toBe(57);
    });
  });

  describe('what counts as answered', () => {
    it('sub-community is optional and moves nothing', async () => {
      const withSub = buildService({
        draftData: {
          ...registrationAnswered,
          religionDetails: {
            ...MANDATORY_COMPLETE.religionDetails,
            subCaste: 'Vadama',
          },
        },
        photoCount: 1,
      });
      const withoutSub = buildService({
        draftData: {
          ...registrationAnswered,
          religionDetails: {
            ...MANDATORY_COMPLETE.religionDetails,
            subCaste: '',
          },
        },
        photoCount: 1,
      });
      expect((await withSub.calculate()).percentage).toBe(
        (await withoutSub.calculate()).percentage,
      );
      expect((await withoutSub.calculate()).registrationComplete).toBe(true);
    });

    it('Other without a custom value stays incomplete', async () => {
      // OtherOptionField persists what the member TYPES and stores an empty
      // string until they do, so a literal "Other" reaching the server means
      // the question was opened and left unanswered.
      const result = await buildService({
        draftData: {
          ...registrationAnswered,
          educationDetails: {
            ...MANDATORY_COMPLETE.educationDetails,
            workIndustry: 'Other',
          },
        },
        photoCount: 1,
      }).calculate();

      expect(result.registrationComplete).toBe(false);
      expect(
        result.requiredFields.find((f) => f.id === 'workIndustry')!.isComplete,
      ).toBe(false);
    });

    it('the custom value typed behind Other does count', async () => {
      const result = await buildService({
        draftData: {
          ...registrationAnswered,
          educationDetails: {
            ...MANDATORY_COMPLETE.educationDetails,
            workIndustry: 'Logistics',
          },
        },
        photoCount: 1,
      }).calculate();
      expect(result.registrationComplete).toBe(true);
    });
  });

  describe('verification', () => {
    it('is 25 overall, five implemented checks at 5 each', async () => {
      const result = await buildService({
        draftData: registrationAnswered,
      }).calculate();

      expect(
        result.breakdown.find((m) => m.id === 'verification')!.weight,
      ).toBe(25);
      expect(result.verificationBreakdown.map((v) => v.id)).toEqual([
        'mobile',
        'income',
        'asset',
        'aadhaar',
        'nri',
      ]);
      expect(
        result.verificationBreakdown.reduce((sum, v) => sum + v.weight, 0),
      ).toBe(25);
    });

    it('awards nothing for a verification that is not implemented yet', async () => {
      // Live selfie verification is planned. It must earn nothing until it
      // exists, and when it lands its share comes out of this same 25 — the
      // profile total does not move.
      const result = await buildService({
        draftData: registrationAnswered,
        approvedDocTypes: ['SELFIE', 'LIVE_SELFIE', 'FACE'],
      }).calculate();

      expect(
        result.breakdown.find((m) => m.id === 'verification')!.earned,
      ).toBe(0);
      expect(result.verificationBreakdown.every((v) => !v.isVerified)).toBe(
        true,
      );
    });

    it('counts each implemented check independently', async () => {
      const result = await buildService({
        draftData: registrationAnswered,
        phone: '+919000000000',
        approvedDocTypes: ['AADHAAR'],
      }).calculate();

      expect(
        result.breakdown.find((m) => m.id === 'verification')!.earned,
      ).toBe(10);
    });

    it('a pending KYC row counts for nothing', async () => {
      // The service filters to status APPROVED itself, so PENDING/REJECTED
      // rows are invisible to it regardless of what else exists.
      const { kycFindMany, calculate } = buildService({
        draftData: registrationAnswered,
        approvedDocTypes: [],
      });
      await calculate();
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      const [call] = kycFindMany.mock.calls as Array<
        [{ where: { status: string } }]
      >;
      expect(call[0].where.status).toBe('APPROVED');
    });

    it('an unverified phone does not count as mobile verified', async () => {
      const result = await buildService({
        draftData: registrationAnswered,
        phone: null,
      }).calculate();

      expect(
        result.verificationBreakdown.find((v) => v.id === 'mobile')!.isVerified,
      ).toBe(false);
    });
  });

  describe('the score is derived, never incremented', () => {
    it('removing an answer reduces the percentage', async () => {
      const complete = buildService({
        draftData: registrationAnswered,
        photoCount: 1,
      });
      const cleared = buildService({
        draftData: { ...registrationAnswered, lifestyleDetails: {} },
        photoCount: 1,
      });
      expect((await complete.calculate()).percentage).toBe(60);
      // Losing diet drops one of 21 items: round(60 * 20/21) = 57.
      expect((await cleared.calculate()).percentage).toBe(57);
    });

    it('deleting the last photo drops its share back out', async () => {
      const withPhoto = buildService({
        draftData: registrationAnswered,
        photoCount: 2,
      });
      const withoutPhoto = buildService({
        draftData: registrationAnswered,
        photoCount: 0,
      });
      expect((await withPhoto.calculate()).percentage).toBe(60);
      expect((await withoutPhoto.calculate()).percentage).toBe(57);
    });
  });
});
