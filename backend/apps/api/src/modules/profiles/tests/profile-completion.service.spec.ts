import { ProfileCompletionService } from '../services/profile-completion.service';
import type { ProfileRepository } from '../repositories/profile.repository';
import type { PhotoRepository } from '../repositories/photo.repository';
import type { PrismaService } from '@app/database';

const MANDATORY_COMPLETE = {
  basicDetails: {
    firstName: 'Arjun',
    lastName: 'Sundar',
    gender: 'MALE',
    dob: '1997-01-01',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Self',
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

describe('ProfileCompletionService', () => {
  it('returns 0 when no data has been completed at all', async () => {
    const { calculate } = buildService({ draftData: {} });
    const result = await calculate();
    expect(result.percentage).toBe(0);
  });

  it('returns 0 when only some mandatory steps are complete (no partial credit)', async () => {
    const { calculate } = buildService({
      draftData: {
        basicDetails: MANDATORY_COMPLETE.basicDetails,
        religionDetails: MANDATORY_COMPLETE.religionDetails,
        languageDetails: MANDATORY_COMPLETE.languageDetails,
        // locationDetails missing
      },
    });
    const result = await calculate();
    expect(result.percentage).toBe(0);
  });

  it('awards exactly 20 once all four mandatory steps are complete', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
    });
    const result = await calculate();
    expect(result.percentage).toBe(20);
    expect(result.completedSections).toContain('registration');
  });

  it('mandatory + Education = 30', async () => {
    const { calculate } = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: EDUCATION_COMPLETE,
      },
    });
    expect((await calculate()).percentage).toBe(30);
  });

  it('mandatory + Physical = 25', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE, physicalDetails: PHYSICAL_COMPLETE },
    });
    expect((await calculate()).percentage).toBe(25);
  });

  it('mandatory + Family = 30', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE, familyDetails: FAMILY_COMPLETE },
    });
    expect((await calculate()).percentage).toBe(30);
  });

  it('mandatory + Psychology = 23', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      quizResponseCount: 1,
    });
    expect((await calculate()).percentage).toBe(23);
  });

  it('mandatory + Photos = 32', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      photoCount: 1,
    });
    expect((await calculate()).percentage).toBe(32);
  });

  it('mandatory + Mobile verification = 25', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      phone: '+919876543210',
    });
    expect((await calculate()).percentage).toBe(25);
  });

  it('mandatory + Mobile + Aadhaar = 30', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      phone: '+919876543210',
      approvedDocTypes: ['AADHAAR'],
    });
    expect((await calculate()).percentage).toBe(30);
  });

  it('mandatory + all optional sections + all verifications = 100', async () => {
    const { calculate } = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: EDUCATION_COMPLETE,
        physicalDetails: PHYSICAL_COMPLETE,
        lifestyleDetails: LIFESTYLE_COMPLETE,
        familyDetails: FAMILY_COMPLETE,
        horoscopeDetails: HOROSCOPE_COMPLETE,
        partnerPreference: PARTNER_PREF_TOUCHED,
      },
      photoCount: 1,
      quizResponseCount: 1,
      phone: '+919876543210',
      approvedDocTypes: ['AADHAAR', 'INCOME_PROOF', 'ASSET_PROOF', 'NRI_PROOF'],
    });
    const result = await calculate();
    expect(result.percentage).toBe(100);
    expect(result.missingSections).toEqual([]);
  });

  it('never exceeds 100 even if weights were to sum higher', async () => {
    const { calculate } = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: EDUCATION_COMPLETE,
        physicalDetails: PHYSICAL_COMPLETE,
        lifestyleDetails: LIFESTYLE_COMPLETE,
        familyDetails: FAMILY_COMPLETE,
        horoscopeDetails: HOROSCOPE_COMPLETE,
        partnerPreference: PARTNER_PREF_TOUCHED,
      },
      photoCount: 5,
      quizResponseCount: 3,
      phone: '+919876543210',
      approvedDocTypes: ['AADHAAR', 'INCOME_PROOF', 'ASSET_PROOF', 'NRI_PROOF'],
    });
    expect((await calculate()).percentage).toBeLessThanOrEqual(100);
  });

  it('removing previously-completed data reduces the percentage (derived, not incremented)', async () => {
    const withEducation = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: EDUCATION_COMPLETE,
      },
    });
    expect((await withEducation.calculate()).percentage).toBe(30);

    const educationCleared = buildService({
      draftData: { ...MANDATORY_COMPLETE, educationDetails: {} },
    });
    expect((await educationCleared.calculate()).percentage).toBe(20);
  });

  it('a touched-but-incomplete optional section earns nothing (not partial credit)', async () => {
    const { calculate } = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: { qualification: "Bachelor's" }, // rest missing
      },
    });
    expect((await calculate()).percentage).toBe(20);
  });

  it('pending KYC verification does not count toward the 25%', async () => {
    // approvedDocTypes intentionally empty — kycVerification.findMany is
    // already filtered to status: APPROVED by the service itself, so a
    // PENDING/REJECTED row is invisible to it regardless.
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      approvedDocTypes: [],
    });
    expect((await calculate()).percentage).toBe(20);
  });

  it('an unverified phone (no User.phone) does not count as mobile verified', async () => {
    const { calculate } = buildService({
      draftData: { ...MANDATORY_COMPLETE },
      phone: null,
    });
    expect((await calculate()).percentage).toBe(20);
  });

  it('module weights sum to exactly 100', async () => {
    const { calculate } = buildService({
      draftData: {
        ...MANDATORY_COMPLETE,
        educationDetails: EDUCATION_COMPLETE,
        physicalDetails: PHYSICAL_COMPLETE,
        lifestyleDetails: LIFESTYLE_COMPLETE,
        familyDetails: FAMILY_COMPLETE,
        horoscopeDetails: HOROSCOPE_COMPLETE,
        partnerPreference: PARTNER_PREF_TOUCHED,
      },
      photoCount: 1,
      quizResponseCount: 1,
      phone: '+919876543210',
      approvedDocTypes: ['AADHAAR', 'INCOME_PROOF', 'ASSET_PROOF', 'NRI_PROOF'],
    });
    const result = await calculate();
    const totalWeight = result.breakdown.reduce((sum, m) => sum + m.weight, 0);
    expect(totalWeight).toBe(100);
    expect(result.percentage).toBe(100);
  });

  describe('verification breakdown (earned vs. weight, so Flutter never has to guess partial progress)', () => {
    it('earns 5 of 25 for mobile only, and is not marked complete', async () => {
      const { calculate } = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        phone: '+919876543210',
      });
      const result = await calculate();
      const verification = result.breakdown.find(
        (m) => m.id === 'verification',
      )!;
      expect(verification.earned).toBe(5);
      expect(verification.isComplete).toBe(false);
      expect(result.verificationBreakdown).toEqual(
        expect.arrayContaining([
          { id: 'mobile', weight: 5, isVerified: true },
          { id: 'income', weight: 5, isVerified: false },
          { id: 'asset', weight: 5, isVerified: false },
          { id: 'aadhaar', weight: 5, isVerified: false },
          { id: 'nri', weight: 5, isVerified: false },
        ]),
      );
    });

    it('earns 10 of 25 for mobile + aadhaar', async () => {
      const { calculate } = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        phone: '+919876543210',
        approvedDocTypes: ['AADHAAR'],
      });
      const result = await calculate();
      const verification = result.breakdown.find(
        (m) => m.id === 'verification',
      )!;
      expect(verification.earned).toBe(10);
      expect(verification.isComplete).toBe(false);
    });

    it('earns the full 25 of 25 only once all five flags are verified, and is then marked complete', async () => {
      const { calculate } = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        phone: '+919876543210',
        approvedDocTypes: [
          'AADHAAR',
          'INCOME_PROOF',
          'ASSET_PROOF',
          'NRI_PROOF',
        ],
      });
      const result = await calculate();
      const verification = result.breakdown.find(
        (m) => m.id === 'verification',
      )!;
      expect(verification.earned).toBe(25);
      expect(verification.isComplete).toBe(true);
    });

    it('a rejected/pending KYC row never counts — the query itself only ever asks for APPROVED', async () => {
      const { calculate, kycFindMany } = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        // The mock's `findMany` return value already only reflects what a
        // real `status: 'APPROVED'` filter would return — a REJECTED or
        // PENDING row for the same user is invisible to this query
        // regardless of what else exists in the table. Asserting the actual
        // where-clause is the authoritative proof, not just an empty mock.
        approvedDocTypes: [],
      });
      const result = await calculate();
      expect(kycFindMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'user-1', status: 'APPROVED' },
        }),
      );
      expect(
        result.verificationBreakdown.find((v) => v.id === 'aadhaar'),
      ).toEqual({ id: 'aadhaar', weight: 5, isVerified: false });
    });
  });

  describe('partner preference (Step 11)', () => {
    it('untouched partner preference earns 0%', async () => {
      const { calculate } = buildService({
        draftData: { ...MANDATORY_COMPLETE, partnerPreference: {} },
      });
      expect((await calculate()).percentage).toBe(20);
    });

    it('any single preference field earns the full 5% — Partner Preference has no all-or-nothing rule anywhere in the system (every PartnerPreferenceDto field is @IsOptional, and the standalone Partner Preferences page has no save-gate), so "touched" and "complete" are the same state by design, unlike Education/Physical/Lifestyle/Horoscope', async () => {
      const { calculate } = buildService({
        draftData: {
          ...MANDATORY_COMPLETE,
          partnerPreference: { preferredAgeRange: '25-30' },
        },
      });
      expect((await calculate()).percentage).toBe(25);
    });

    it('an "extended" (advanced Partner Preferences page) field alone also earns the 5%', async () => {
      const { calculate } = buildService({
        draftData: {
          ...MANDATORY_COMPLETE,
          partnerPreference: { extended: { religionImportance: 'high' } },
        },
      });
      expect((await calculate()).percentage).toBe(25);
    });
  });

  describe('photo removal', () => {
    it("deleting the user's last photo drops the 12% back out", async () => {
      const withPhoto = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        photoCount: 1,
      });
      expect((await withPhoto.calculate()).percentage).toBe(32);

      const photoDeleted = buildService({
        draftData: { ...MANDATORY_COMPLETE },
        photoCount: 0,
      });
      expect((await photoDeleted.calculate()).percentage).toBe(20);
    });
  });
});
