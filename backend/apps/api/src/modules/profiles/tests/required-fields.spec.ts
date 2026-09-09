import {
  COUNTED_PROFILE_FIELDS,
  REQUIRED_PROFILE_FIELDS,
  isMeaningfulValue,
  requiredFieldScore,
  requiredFieldStatuses,
} from '../validation/required-fields';

/**
 * The field-by-field registration score.
 *
 * The 'registration' slice used to be one all-or-nothing block, so a member
 * with nineteen of twenty answers scored exactly what a member with none
 * scored and the UI could tell them nothing more useful than "incomplete".
 * These pin what each field is worth and, more importantly, what counts as an
 * answer at all.
 */

/** Every counted field answered — the 100%-of-registration fixture. */
const ALL_ANSWERED = {
  basicDetails: {
    profileCreatedFor: 'Myself',
    gender: 'MALE',
    firstName: 'Arjun',
    lastName: 'Krishnan',
    dob: '1998-08-15',
    maritalStatus: 'NEVER_MARRIED',
  },
  religionDetails: { religion: 'Hindu', community: 'Nadar' },
  locationDetails: { country: 'India', state: 'Tamil Nadu', city: 'Chennai' },
  physicalDetails: { height: `5' 8"` },
  lifestyleDetails: { eatingHabit: 'Vegetarian' },
  educationDetails: {
    qualification: 'B.E / B.Tech',
    college: 'Anna University',
    annualIncome: 'Rs. 10 - 15 Lakhs',
    employmentType: 'Private',
    workIndustry: 'IT / Software',
    occupation: 'Software Engineer',
    company: 'Acme',
  },
};

describe('the field list', () => {
  it('is the 21 Edit Profile asks for, in screen order', () => {
    expect(REQUIRED_PROFILE_FIELDS.map((f) => f.id)).toEqual([
      'profileCreatedFor',
      'gender',
      'firstName',
      'lastName',
      'dob',
      'religion',
      'community',
      'country',
      'state',
      'city',
      'subCommunity',
      'maritalStatus',
      'height',
      'diet',
      'qualification',
      'college',
      'annualIncome',
      'employmentType',
      'workIndustry',
      'occupation',
      'company',
    ]);
  });

  it('counts 20 of them — sub-community is the only optional one', () => {
    expect(COUNTED_PROFILE_FIELDS).toHaveLength(20);
    const optional = REQUIRED_PROFILE_FIELDS.filter((f) => f.optional);
    expect(optional.map((f) => f.id)).toEqual(['subCommunity']);
  });
});

describe('what counts as an answer', () => {
  it('accepts a real value', () => {
    expect(isMeaningfulValue('Chennai')).toBe(true);
    expect(isMeaningfulValue(0)).toBe(true);
    expect(isMeaningfulValue(false)).toBe(true);
  });

  it('rejects absence and whitespace', () => {
    expect(isMeaningfulValue(undefined)).toBe(false);
    expect(isMeaningfulValue(null)).toBe(false);
    expect(isMeaningfulValue('')).toBe(false);
    expect(isMeaningfulValue('   ')).toBe(false);
    expect(isMeaningfulValue([])).toBe(false);
  });

  it('rejects a placeholder that was never an answer', () => {
    // "Other" is the selection placeholder on every dropdown paired with a
    // free-text box. The widget persists what the member TYPES, so a stored
    // literal "Other" means they picked it and gave nothing.
    for (const placeholder of ['Other', 'other', ' OTHER ', 'Select', 'N/A']) {
      expect(isMeaningfulValue(placeholder)).toBe(false);
    }
  });

  it('accepts the custom value typed behind "Other"', () => {
    // Which is the whole point: choosing Other and typing "Logistics" stores
    // "Logistics", and that is a complete answer.
    expect(isMeaningfulValue('Logistics')).toBe(true);
  });
});

describe('scoring', () => {
  it('is 20 of 20 when every counted field is answered', () => {
    expect(requiredFieldScore(ALL_ANSWERED)).toEqual({
      completed: 20,
      total: 20,
    });
  });

  it('is 0 of 20 for an empty draft, without throwing', () => {
    expect(requiredFieldScore({})).toEqual({ completed: 0, total: 20 });
  });

  it('is unmoved by sub-community, answered or not', () => {
    const withSub = {
      ...ALL_ANSWERED,
      religionDetails: { ...ALL_ANSWERED.religionDetails, subCaste: 'Vadama' },
    };
    const withoutSub = {
      ...ALL_ANSWERED,
      religionDetails: { ...ALL_ANSWERED.religionDetails, subCaste: '' },
    };
    expect(requiredFieldScore(withSub)).toEqual(requiredFieldScore(withoutSub));
    expect(requiredFieldScore(withSub).completed).toBe(20);
  });

  it('drops exactly one for each field cleared', () => {
    for (const field of COUNTED_PROFILE_FIELDS) {
      const section = ALL_ANSWERED[field.section];
      const cleared = {
        ...ALL_ANSWERED,
        [field.section]: { ...section, [field.key]: '' },
      };
      expect(requiredFieldScore(cleared).completed).toBe(19);
    }
  });

  it('does not count a field left on the "Other" placeholder', () => {
    const placeheld = {
      ...ALL_ANSWERED,
      educationDetails: {
        ...ALL_ANSWERED.educationDetails,
        workIndustry: 'Other',
      },
    };
    expect(requiredFieldScore(placeheld).completed).toBe(19);
  });
});

describe('the work section', () => {
  it('counts employment type, industry, role and company separately', () => {
    const workIds = ['employmentType', 'workIndustry', 'occupation', 'company'];
    const statuses = requiredFieldStatuses(ALL_ANSWERED);
    for (const id of workIds) {
      const field = statuses.find((f) => f.id === id)!;
      expect(field.isComplete).toBe(true);
      // All four live on the Education step, so "fix this" opens step 4.
      expect(field.wizardStep).toBe(4);
      expect(field.section).toBe('educationDetails');
    }
  });

  it('still counts an employmentType a live profile already holds', () => {
    // Every value stored before this change stays valid. Task 2 added
    // 'Retired' and made the control a dropdown; it removed nothing.
    for (const stored of [
      'Private',
      'Government',
      'Business',
      'Self-Employed',
      'Not Working',
      'Student',
      'Retired',
    ]) {
      const draft = {
        ...ALL_ANSWERED,
        educationDetails: {
          ...ALL_ANSWERED.educationDetails,
          employmentType: stored,
        },
      };
      expect(requiredFieldScore(draft).completed).toBe(20);
    }
  });
});

describe('date of birth', () => {
  it('counts only a date that names a real day', () => {
    const withDob = (dob: string) => ({
      ...ALL_ANSWERED,
      basicDetails: { ...ALL_ANSWERED.basicDetails, dob },
    });
    // Presence is not enough: a stored 31 February cannot be written to the
    // column, so showing it as a completed field would be a lie.
    expect(requiredFieldScore(withDob('1998-02-31')).completed).toBe(19);
    expect(requiredFieldScore(withDob('not a date')).completed).toBe(19);
    expect(requiredFieldScore(withDob('1998-08-15')).completed).toBe(20);
  });

  it('does not apply the age floor', () => {
    // A member who registered under the previous floor of 18 has a real date
    // of birth and must not be told their profile is incomplete over it.
    const year = new Date().getUTCFullYear() - 19;
    const draft = {
      ...ALL_ANSWERED,
      basicDetails: { ...ALL_ANSWERED.basicDetails, dob: `${year}-08-15` },
    };
    expect(requiredFieldScore(draft).completed).toBe(20);
  });
});

describe('statuses', () => {
  it('name the step that fixes each missing field', () => {
    const statuses = requiredFieldStatuses({});
    expect(statuses).toHaveLength(21);
    expect(statuses.every((f) => !f.isComplete)).toBe(true);
    expect(statuses.find((f) => f.id === 'city')!.wizardStep).toBe(3);
    expect(statuses.find((f) => f.id === 'diet')!.wizardStep).toBe(6);
    expect(statuses.find((f) => f.id === 'height')!.wizardStep).toBe(5);
    expect(statuses.find((f) => f.id === 'religion')!.wizardStep).toBe(1);
  });

  it('mark sub-community optional so a client can render it as such', () => {
    const sub = requiredFieldStatuses({}).find((f) => f.id === 'subCommunity')!;
    expect(sub.optional).toBe(true);
  });
});
