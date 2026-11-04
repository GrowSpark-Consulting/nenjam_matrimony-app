import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DRAFT_SECTIONS } from '../../profiles/services/profile-draft.service';
import {
  CLIENT_DIETS,
  CLIENT_EMPLOYMENT_TYPES,
  CLIENT_FAMILY_TYPES,
  CLIENT_HEIGHTS,
  CLIENT_INCOME_RANGES,
  CLIENT_PREF_AGE_RANGES,
  CLIENT_PREF_CASTES,
  CLIENT_PREF_DIETS,
  CLIENT_PREF_HEIGHT_RANGES,
  CLIENT_PREF_INCOMES,
  CLIENT_PREF_LOCATIONS,
  CLIENT_PREF_MARITAL_STATUSES,
  CLIENT_PREF_MIN_EDUCATIONS,
  CLIENT_PREF_OCCUPATIONS,
  CLIENT_PREF_RELIGIONS,
  CLIENT_RASHIS,
  CLIENT_STARS,
  clientHeightLabel,
  missingRequiredClientFields,
  parseStoredClientProfile,
  toClientWizardDraft,
  validateClientProfile,
  WIZARD_SECTIONS,
  type ClientProfile,
} from './client-profile';

const NOW = new Date('2026-11-03T10:00:00.000Z');

/** A complete profile, every section filled. */
export const FULL: ClientProfile = {
  basicDetails: {
    firstName: 'Priya',
    lastName: 'Sundaram',
    gender: 'FEMALE',
    dob: '1998-04-12',
    maritalStatus: 'NEVER_MARRIED',
  },
  religionDetails: {
    religionCode: 'HINDU',
    communityCode: 'HINDU-VELLALAR',
    subCaste: 'Pillai',
  },
  languageDetails: { motherTongue: 'Tamil' },
  locationDetails: {
    countryCode: 'IN',
    stateCode: 'IN-TN',
    cityCode: 'IN-TN-MDU',
    nativePlace: 'Tirunelveli',
  },
  educationDetails: {
    qualification: 'B.E / B.Tech',
    occupation: 'Software Engineer',
    employmentType: 'Private',
    annualIncome: '10 - 20 Lakhs',
  },
  physicalDetails: { height: `5'3" (160 cm)` },
  lifestyleDetails: { eatingHabit: 'Vegetarian', aboutMe: 'Loves music.' },
  familyDetails: {
    father: { occupation: 'Retired teacher' },
    mother: { occupation: 'Homemaker' },
    siblings: [{ relation: 'BROTHER', name: 'Arun', age: 30 }],
    familyType: 'Nuclear Family',
  },
  horoscopeDetails: { rashi: 'Simha', star: 'Rohini' },
  partnerPreference: {
    preferredAgeRange: '26-30',
    preferredHeightRange: `5'4"-5'8"`,
    maritalStatusPref: 'Never Married',
    religionPref: 'Hindu',
    castePref: 'Any Caste',
    occupationPref: 'Software / IT',
    incomePref: '10-20 Lakhs',
    locationPref: 'Same State',
    extended: { minEducation: 'Bachelors', diet: 'Vegetarian' },
  },
};

const fieldsOf = (input: unknown) => {
  const check = validateClientProfile(input, NOW);
  return check.ok ? [] : check.fields;
};

describe('validateClientProfile', () => {
  it('accepts the full profile, every section', () => {
    expect(validateClientProfile(FULL, NOW)).toEqual({
      ok: true,
      profile: FULL,
    });
  });

  it('accepts a partial or empty draft (completeness is judged at submit)', () => {
    expect(validateClientProfile(undefined, NOW)).toEqual({
      ok: true,
      profile: {},
    });
    expect(validateClientProfile({}, NOW)).toEqual({ ok: true, profile: {} });
    expect(
      validateClientProfile({ basicDetails: { firstName: ' Priya ' } }, NOW),
    ).toEqual({ ok: true, profile: { basicDetails: { firstName: 'Priya' } } });
  });

  it('drops empty answers and upper-cases codes', () => {
    expect(
      validateClientProfile(
        {
          basicDetails: { firstName: '', lastName: null },
          locationDetails: { stateCode: 'in-tn', nativePlace: '   ' },
        },
        NOW,
      ),
    ).toEqual({
      ok: true,
      profile: { locationDetails: { stateCode: 'IN-TN' } },
    });
  });

  it('names every bad field, never its value', () => {
    const check = validateClientProfile(
      {
        basicDetails: { gender: 'OTHER', dob: '2010-01-01' },
        physicalDetails: { height: '5 ft 3' },
        partnerPreference: { extended: { diet: 'Fish' } },
        familyDetails: { siblings: [{ name: 'Arun' }] },
      },
      NOW,
    );
    expect(check).toEqual({
      ok: false,
      fields: [
        'details.basicDetails.gender',
        'details.basicDetails.dob',
        'details.physicalDetails.height',
        'details.familyDetails.siblings[0].relation',
        'details.partnerPreference.extended.diet',
      ],
    });
    expect(JSON.stringify(check)).not.toContain('Fish');
  });

  it('refuses an unknown section or field, naming only the section', () => {
    expect(fieldsOf({ photos: [] })).toEqual(['details']);
    expect(fieldsOf({ basicDetails: { profileCreatedFor: 'Son' } })).toEqual([
      'details.basicDetails',
    ]);
    expect(fieldsOf({ basicDetails: { caste: 'x' } })).toEqual([
      'details.basicDetails',
    ]);
    expect(fieldsOf([FULL])).toEqual(['details']);
  });

  it('accepts and ignores the labels it sends back (they come from the codes)', () => {
    expect(
      validateClientProfile(
        {
          religionDetails: {
            religionCode: 'HINDU',
            religion: 'Something else',
          },
          locationDetails: { cityCode: 'IN-TN-MDU', city: 'Madurai' },
        },
        NOW,
      ),
    ).toEqual({
      ok: true,
      profile: {
        religionDetails: { religionCode: 'HINDU' },
        locationDetails: { cityCode: 'IN-TN-MDU' },
      },
    });
  });

  it('lengths: names 50, about 1000 (Tamil counted by character)', () => {
    expect(fieldsOf({ basicDetails: { firstName: 'x'.repeat(51) } })).toEqual([
      'details.basicDetails.firstName',
    ]);
    expect(fieldsOf({ basicDetails: { firstName: 'பிரியா' } })).toEqual([]);
    expect(
      fieldsOf({ lifestyleDetails: { aboutMe: 'x'.repeat(1000) } }),
    ).toEqual([]);
    expect(
      fieldsOf({ lifestyleDetails: { aboutMe: 'x'.repeat(1001) } }),
    ).toEqual(['details.lifestyleDetails.aboutMe']);
  });

  it('siblings: at most 10, each a brother or a sister, ages 0 to 120', () => {
    const sibling = { relation: 'SISTER' };
    expect(
      fieldsOf({ familyDetails: { siblings: Array(11).fill(sibling) } }),
    ).toEqual(['details.familyDetails.siblings']);
    expect(
      fieldsOf({
        familyDetails: { siblings: [{ relation: 'SISTER', age: 121 }] },
      }),
    ).toEqual(['details.familyDetails.siblings[0].age']);
    expect(
      fieldsOf({ familyDetails: { siblings: [{ relation: 'COUSIN' }] } }),
    ).toEqual(['details.familyDetails.siblings[0].relation']);
  });

  it('a malformed code is refused (whether it exists is the master data’s call)', () => {
    expect(fieldsOf({ locationDetails: { cityCode: 'IN TN' } })).toEqual([
      'details.locationDetails.cityCode',
    ]);
  });
});

describe('missingRequiredClientFields', () => {
  it('nothing is missing from the full profile', () => {
    expect(missingRequiredClientFields(FULL)).toEqual([]);
  });

  it('names what an empty or partial profile lacks, in the required list order', () => {
    expect(missingRequiredClientFields({})).toEqual([
      'basicDetails.firstName',
      'basicDetails.lastName',
      'basicDetails.gender',
      'basicDetails.dob',
      'basicDetails.maritalStatus',
      'religionDetails.religionCode',
      'locationDetails.stateCode',
      'locationDetails.cityCode',
      'educationDetails.qualification',
    ]);
    expect(
      missingRequiredClientFields({
        ...FULL,
        educationDetails: { occupation: 'Doctor' },
      }),
    ).toEqual(['educationDetails.qualification']);
  });

  it('a blank stored value still counts as missing (data saved before, or by another path)', () => {
    expect(
      missingRequiredClientFields({
        ...FULL,
        educationDetails: { qualification: '   ' },
      }),
    ).toEqual(['educationDetails.qualification']);
  });

  it('every optional field can be left out', () => {
    const minimal: ClientProfile = {
      basicDetails: FULL.basicDetails,
      religionDetails: { religionCode: 'HINDU' },
      locationDetails: {
        countryCode: 'IN',
        stateCode: 'IN-TN',
        cityCode: 'IN-TN-MDU',
      },
      educationDetails: { qualification: 'Diploma' },
    };
    expect(missingRequiredClientFields(minimal)).toEqual([]);
  });
});

describe('toClientWizardDraft', () => {
  it("writes every filled section under the wizard's names, as Myself, with their steps done", () => {
    const resolved: ClientProfile = {
      ...FULL,
      religionDetails: {
        ...FULL.religionDetails,
        religion: 'Hindu',
        community: 'Vellalar',
      },
    };
    const draft = toClientWizardDraft(resolved);
    expect(draft.draftData).toEqual({
      ...resolved,
      basicDetails: { ...FULL.basicDetails, profileCreatedFor: 'Myself' },
    });
    expect(draft.completedSteps).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(draft.currentStep).toBe(10);
  });

  it('leaves out the sections the agent did not fill', () => {
    const draft = toClientWizardDraft({
      basicDetails: { firstName: 'Priya' },
      locationDetails: { stateCode: 'IN-TN' },
    });
    expect(Object.keys(draft.draftData)).toEqual([
      'basicDetails',
      'locationDetails',
    ]);
    expect(draft.completedSteps).toEqual([1, 4]);
    expect(draft.currentStep).toBe(4);
  });

  it('always writes step 1 with "Myself", even for an empty profile', () => {
    expect(toClientWizardDraft({})).toEqual({
      draftData: { basicDetails: { profileCreatedFor: 'Myself' } },
      completedSteps: [1],
      currentStep: 1,
    });
  });

  it('does not share objects with the profile it was made from', () => {
    const draft = toClientWizardDraft(FULL);
    (draft.draftData.familyDetails.siblings as unknown[]).push('x');
    expect((FULL.familyDetails?.siblings as unknown[]).length).toBe(1);
  });

  it("the wizard's sections, in step order, are the member wizard's own", () => {
    expect([...WIZARD_SECTIONS]).toEqual([...DRAFT_SECTIONS]);
  });
});

describe('parseStoredClientProfile', () => {
  it('reads the full profile back', () => {
    expect(parseStoredClientProfile(JSON.stringify(FULL))).toEqual(FULL);
  });

  it('reads a step-1-only draft from before as its basicDetails, without profileCreatedFor', () => {
    expect(
      parseStoredClientProfile(
        JSON.stringify({ ...FULL.basicDetails, profileCreatedFor: 'Daughter' }),
      ),
    ).toEqual({ basicDetails: FULL.basicDetails });
  });

  it('throws on corrupt data', () => {
    expect(() => parseStoredClientProfile('[]')).toThrow(TypeError);
  });
});

/** The values the member app offers, read from its own source (a drift guard). */
describe('the allowed values are the member wizard’s own', () => {
  const FRONTEND = join(__dirname, '../../../../../../../Frontend/lib');
  const read = (rel: string) => readFileSync(join(FRONTEND, rel), 'utf8');
  /** The string items of `<name> = [ ... ];` in a Dart file. */
  const dartList = (source: string, name: string): string[] => {
    const at = source.indexOf(`${name} = [`);
    if (at < 0) throw new Error(`${name} not found`);
    const body = source.slice(at, source.indexOf('];', at));
    return [...body.matchAll(/'((?:\\'|[^'])*)'|"((?:\\"|[^"])*)"/g)].map((m) =>
      (m[1] ?? m[2]).replace(/\\'/g, "'").replace(/\\"/g, '"'),
    );
  };
  const options = read('core/constants/profile_options.dart');
  const prefs = read(
    'features/registration/presentation/utils/partner_preference_labels.dart',
  );
  const prefsPage = read(
    'features/partner_preferences/presentation/pages/partner_preferences_page.dart',
  );
  const horoscope = read(
    'features/registration/presentation/widgets/step_horoscope.dart',
  );
  const family = read(
    'features/registration/presentation/widgets/step_family.dart',
  );

  it.each([
    ['diets', options, 'diets', CLIENT_DIETS],
    ['employment types', options, 'employmentTypes', CLIENT_EMPLOYMENT_TYPES],
    ['income ranges', options, 'incomeRanges', CLIENT_INCOME_RANGES],
    ['family types', family, '_familyTypes', CLIENT_FAMILY_TYPES],
    ['rashis', horoscope, '_rashis', CLIENT_RASHIS],
    ['stars', horoscope, '_stars', CLIENT_STARS],
    ['pref age ranges', prefs, 'partnerPrefAgeRanges', CLIENT_PREF_AGE_RANGES],
    [
      'pref height ranges',
      prefs,
      'partnerPrefHeightRanges',
      CLIENT_PREF_HEIGHT_RANGES,
    ],
    ['pref religions', prefs, 'partnerPrefReligions', CLIENT_PREF_RELIGIONS],
    ['pref castes', prefs, 'partnerPrefCastes', CLIENT_PREF_CASTES],
    [
      'pref occupations',
      prefs,
      'partnerPrefOccupations',
      CLIENT_PREF_OCCUPATIONS,
    ],
    ['pref incomes', prefs, 'partnerPrefIncomes', CLIENT_PREF_INCOMES],
    ['pref locations', prefs, 'partnerPrefLocations', CLIENT_PREF_LOCATIONS],
    [
      'pref marital statuses',
      prefs,
      'partnerPrefMaritalStatuses',
      CLIENT_PREF_MARITAL_STATUSES,
    ],
    [
      'pref minimum education',
      prefsPage,
      '_minEducationOptions',
      CLIENT_PREF_MIN_EDUCATIONS,
    ],
  ])('%s', (_label, source, name, ours) => {
    expect([...ours]).toEqual(dartList(source, name));
  });

  it('pref diets are the Partner Preferences page’s diet choices', () => {
    const at = prefsPage.indexOf('_dietMap(AppLocalizations l10n) => {');
    const body = prefsPage.slice(at, prefsPage.indexOf('};', at));
    const keys = [...body.matchAll(/'((?:\\'|[^'])*)':/g)].map((m) =>
      m[1].replace(/\\'/g, "'"),
    );
    expect([...CLIENT_PREF_DIETS]).toEqual(keys);
  });

  it('heights: the same 122-213 cm range and label', () => {
    expect(options).toContain('_minHeightCm = 122');
    expect(options).toContain('_maxHeightCm = 213');
    expect(CLIENT_HEIGHTS).toHaveLength(92);
    expect(clientHeightLabel(175)).toBe(`5'9" (175 cm)`);
    expect(CLIENT_HEIGHTS[0]).toBe(`4'0" (122 cm)`);
  });
});
