import {
  isBasicDetailsComplete,
  isLocationDetailsComplete,
  isMatchableFromDraft,
  isReligionDetailsComplete,
} from './registration-rules';

/**
 * "Can this draft become a `user_profiles` row?" — a narrower question than
 * "may this profile be finalized?", and the two must not share an answer.
 *
 * `syncMatchableFromDraft` used to ask the finalize question. Those rules
 * require `subCaste`, `area`, `pinCode` and `nativePlace`, every one of which
 * is a NULLABLE column the write already coerces with `|| null`, and none of
 * which the onboarding flow collects. So an onboarding save wrote to
 * `draft_data` and returned before touching `user_profiles`, leaving Discover,
 * matching and Near Me on a stale row.
 *
 * The shapes below are taken from live `registration_steps` rows, not
 * invented: 4 of 11 drafts with a location section were blocked this way, one
 * of them reading `Karnataka/Mysore` against a profile still reading
 * `Karnataka/hcufi`.
 */

/** What the onboarding flow actually produces. */
const onboardingDraft = {
  basicDetails: {
    firstName: 'Asha',
    lastName: 'Raman',
    gender: 'FEMALE',
    maritalStatus: 'NEVER_MARRIED',
    profileCreatedFor: 'Myself',
    dob: '1998-04-12',
  },
  // Onboarding asks religion + caste + community. It does not ask subCaste.
  religionDetails: { religion: 'Hindu', caste: 'Iyer', community: 'Tamil' },
  languageDetails: { motherTongue: 'Tamil', languagesKnown: ['Tamil'] },
  // Onboarding asks country/state/city only.
  locationDetails: { country: 'India', state: 'Karnataka', city: 'Mysore' },
};

/** What the older wizard produces — every section filled. */
const wizardDraft = {
  ...onboardingDraft,
  religionDetails: {
    religion: 'Hindu',
    caste: 'Iyer',
    subCaste: 'Vadama',
    community: 'Tamil',
  },
  locationDetails: {
    country: 'India',
    state: 'Karnataka',
    city: 'Mysore',
    area: 'Gokulam',
    pinCode: '570002',
    nativePlace: 'Madurai',
  },
};

/**
 * Every section the Flutter onboarding screens PATCH, and nothing else —
 * assembled from the `apply*` methods in `RegistrationNotifier` rather than
 * from a live row, so this fixture goes stale the moment a step stops sending
 * one of these.
 *
 * This is the regression. Onboarding used to collect no `caste`, no
 * `motherTongue`, and no name/gender/dob at all: `create_profile_for` wrote
 * `profileCreatedFor`, the religion step wrote religion + community, and
 * `profile_basics` wrote state + city. Six NOT NULL columns were therefore
 * never filled, `isMatchableFromDraft` returned false on every single save,
 * `syncMatchableFromDraft` returned early every time, and no `user_profiles`
 * row was ever written — while every PATCH answered 200. The member finished
 * onboarding, landed on Discover, and `GET /profiles/me` answered 404 for the
 * life of the account. The screens now ask for all six.
 */
const currentOnboardingDraft = {
  basicDetails: {
    profileCreatedFor: 'Myself',
    firstName: 'Asha',
    lastName: 'Raman',
    gender: 'FEMALE',
    dob: '1998-04-12T00:00:00.000Z',
    maritalStatus: 'NEVER_MARRIED',
  },
  religionDetails: { religion: 'Hindu', caste: 'Iyer', community: 'Tamil' },
  languageDetails: { motherTongue: 'Tamil' },
  locationDetails: { country: 'India', state: 'Karnataka', city: 'Mysore' },
  physicalDetails: { height: "5'4\"" },
  educationDetails: { qualification: 'B.E.', annualIncome: '10 - 20 Lakhs' },
  lifestyleDetails: { aboutMe: 'A short description.' },
};

describe('the draft the onboarding flow produces', () => {
  it('can become a user_profiles row', () => {
    expect(isMatchableFromDraft(currentOnboardingDraft)).toBe(true);
  });

  // Each of these is a NOT NULL column. Dropping one must block the write
  // rather than let a half-built profile through — and the screen that owns
  // it must therefore keep asking for it.
  it.each([
    ['caste', 'religionDetails', 'caste'],
    ['motherTongue', 'languageDetails', 'motherTongue'],
    ['firstName', 'basicDetails', 'firstName'],
    ['lastName', 'basicDetails', 'lastName'],
    ['gender', 'basicDetails', 'gender'],
    ['dob', 'basicDetails', 'dob'],
  ])('is blocked without %s', (_label, section, field) => {
    const stripped = {
      ...currentOnboardingDraft,
      [section]: {
        ...(currentOnboardingDraft as Record<string, Record<string, unknown>>)[
          section
        ],
        [field]: undefined,
      },
    };

    expect(isMatchableFromDraft(stripped)).toBe(false);
  });

  it('was blocked before the screens asked for those six', () => {
    // The exact pre-fix shape: onboarding's own sections, minus the fields no
    // screen collected. This is what shipped, and why new members had no
    // profile.
    const preFix = {
      basicDetails: {
        profileCreatedFor: 'Myself',
        maritalStatus: 'NEVER_MARRIED',
      },
      religionDetails: { religion: 'Hindu', community: 'Tamil' },
      locationDetails: { country: 'India', state: 'Karnataka', city: 'Mysore' },
    };

    expect(isMatchableFromDraft(preFix)).toBe(false);
  });
});

describe('isMatchableFromDraft', () => {
  it('accepts an onboarding draft the finalize rules reject', () => {
    // The regression, stated directly: this draft could not materialize, so
    // the member's city never reached user_profiles.
    expect(isMatchableFromDraft(onboardingDraft)).toBe(true);

    expect(isReligionDetailsComplete(onboardingDraft.religionDetails)).toBe(
      false,
    );
    expect(isLocationDetailsComplete(onboardingDraft.locationDetails)).toBe(
      false,
    );
  });

  it('accepts a fully-filled wizard draft', () => {
    expect(isMatchableFromDraft(wizardDraft)).toBe(true);
  });

  it('ignores fields whose columns are nullable', () => {
    // subCaste, area, pinCode, nativePlace, community and country are all
    // nullable, so none of them can block a write.
    const stripped = {
      ...onboardingDraft,
      religionDetails: { religion: 'Hindu', caste: 'Iyer' },
      locationDetails: { state: 'Karnataka', city: 'Mysore' },
    };

    expect(isMatchableFromDraft(stripped)).toBe(true);
  });

  it('does not require languagesKnown, whose column defaults to []', () => {
    const draft = {
      ...onboardingDraft,
      languageDetails: { motherTongue: 'Tamil' },
    };

    expect(isMatchableFromDraft(draft)).toBe(true);
  });

  describe('still refuses a draft missing a NOT NULL value', () => {
    // Writing these would mean inventing a value into someone's profile, so
    // staying blocked is the correct outcome — one live draft has religion and
    // community but no caste, and it must remain blocked.
    it.each([
      ['caste', { religionDetails: { religion: 'Hindu', community: 'Tamil' } }],
      ['religion', { religionDetails: { caste: 'Iyer' } }],
      ['motherTongue', { languageDetails: {} }],
      ['state', { locationDetails: { country: 'India', city: 'Mysore' } }],
      ['city', { locationDetails: { country: 'India', state: 'Karnataka' } }],
      ['firstName', { basicDetails: { ...onboardingDraft.basicDetails, firstName: '' } }],
      ['dob', { basicDetails: { ...onboardingDraft.basicDetails, dob: '' } }],
      ['gender', { basicDetails: { ...onboardingDraft.basicDetails, gender: '' } }],
    ])('missing %s', (_label, override) => {
      expect(isMatchableFromDraft({ ...onboardingDraft, ...override })).toBe(
        false,
      );
    });

    it('an entirely empty draft', () => {
      expect(isMatchableFromDraft({})).toBe(false);
    });

    it('the literal "Other" placeholder, which is not an answer', () => {
      const draft = {
        ...onboardingDraft,
        religionDetails: { religion: 'Other', caste: 'Iyer' },
      };

      expect(isMatchableFromDraft(draft)).toBe(false);
    });
  });

  it('leaves the finalize contract untouched', () => {
    // finalize() must keep demanding the full set — this change widens what
    // can be materialized, never what can be published.
    expect(isBasicDetailsComplete(onboardingDraft.basicDetails)).toBe(true);
    expect(isReligionDetailsComplete(wizardDraft.religionDetails)).toBe(true);
    expect(isLocationDetailsComplete(wizardDraft.locationDetails)).toBe(true);
    expect(isLocationDetailsComplete(onboardingDraft.locationDetails)).toBe(
      false,
    );
  });
});
