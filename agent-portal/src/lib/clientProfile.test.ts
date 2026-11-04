import {
  HEIGHT_OPTIONS,
  REQUIRED_PATHS,
  SECTIONS,
  getPath,
  heightLabel,
  normalizeDetails,
  setAnswer,
} from './clientProfile';

describe('required fields', () => {
  it('are exactly the nine paths the backend lists, all present in the form', () => {
    expect([...REQUIRED_PATHS]).toEqual([
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
    const paths = SECTIONS.flatMap((s) => s.fields.map((f) => f.path));
    for (const p of REQUIRED_PATHS) expect(paths).toContain(p);
  });
});

describe('height labels', () => {
  it('are the member app list: 92 labels from 122 to 213 cm, exact format', () => {
    expect(HEIGHT_OPTIONS).toHaveLength(92);
    expect(HEIGHT_OPTIONS[0].value).toBe('4\'0" (122 cm)');
    expect(heightLabel(160)).toBe('5\'3" (160 cm)');
    expect(heightLabel(175)).toBe('5\'9" (175 cm)');
    expect(HEIGHT_OPTIONS.at(-1)?.value).toBe('7\'0" (213 cm)');
  });

  it('only label strings are offered: no numbers, no "175 cm"', () => {
    for (const o of HEIGHT_OPTIONS) {
      expect(o.value).toMatch(/^\d'\d{1,2}" \(\d{3} cm\)$/);
    }
    expect(HEIGHT_OPTIONS.map((o) => o.value)).not.toContain('175');
    expect(HEIGHT_OPTIONS.map((o) => o.value)).not.toContain('175 cm');
  });
});

describe('normalizeDetails', () => {
  it('drops missing, null, empty and whitespace answers and empty sections', () => {
    const { details, errors } = normalizeDetails({
      basicDetails: { firstName: ' Priya ', lastName: '', gender: null, dob: '   ' },
      languageDetails: { motherTongue: '  ' },
      partnerPreference: { preferredAgeRange: '', extended: { diet: '   ' } },
      physicalDetails: { height: null },
    });
    expect(errors).toEqual([]);
    expect(details).toEqual({ basicDetails: { firstName: 'Priya' } });
    expect(details).not.toHaveProperty('partnerPreference');
  });

  it('keeps answered partner preferences, even nested ones', () => {
    const { details } = normalizeDetails({
      partnerPreference: { preferredAgeRange: '26-30', extended: { diet: 'Vegetarian', minEducation: '' } },
    });
    expect(details).toEqual({
      partnerPreference: { preferredAgeRange: '26-30', extended: { diet: 'Vegetarian' } },
    });
  });

  it('an empty community is allowed and simply omitted', () => {
    const { details, errors } = normalizeDetails({
      religionDetails: { religionCode: 'HINDU', communityCode: '' },
    });
    expect(errors).toEqual([]);
    expect(details).toEqual({ religionDetails: { religionCode: 'HINDU' } });
  });

  it('never sends the server-filled labels back as answers', () => {
    const { details } = normalizeDetails({
      religionDetails: { religionCode: 'HINDU', religion: 'Hindu', communityCode: 'X', community: 'Y' },
      locationDetails: { stateCode: 'IN-TN', state: 'Tamil Nadu' },
    });
    expect(details).toEqual({
      religionDetails: { religionCode: 'HINDU', communityCode: 'X' },
      locationDetails: { stateCode: 'IN-TN' },
    });
  });

  it('does not mutate its input', () => {
    const input = { basicDetails: { firstName: ' A ', lastName: '' } };
    const copy = JSON.parse(JSON.stringify(input));
    normalizeDetails(input);
    expect(input).toEqual(copy);
  });

  describe('siblings', () => {
    const fam = (siblings: unknown[]) => normalizeDetails({ familyDetails: { siblings } });
    type Row = Record<string, unknown>;
    const rows = (d: Record<string, unknown>) => (d.familyDetails as { siblings: Row[] }).siblings;

    it('a row without a relation is rejected, naming its path', () => {
      const { errors, details } = fam([{ name: 'Arun' }]);
      expect(errors.map((e) => e.path)).toEqual(['familyDetails.siblings[0].relation']);
      expect(details).toEqual({});
    });

    it('an empty-string age is never sent; an unanswered age is omitted', () => {
      const { details, errors } = fam([{ relation: 'BROTHER', name: 'Arun', age: '' }]);
      expect(errors).toEqual([]);
      const row = rows(details)[0];
      expect(row).toEqual({ relation: 'BROTHER', name: 'Arun' });
      expect('age' in row).toBe(false);
    });

    it('a numeric age is sent as a number', () => {
      for (const age of [25, '25']) {
        expect(rows(fam([{ relation: 'SISTER', age }]).details)[0].age).toBe(25);
      }
    });

    it('a non-numeric age is an error, not a string on the wire', () => {
      const { errors } = fam([{ relation: 'SISTER', age: 'abc' }]);
      expect(errors.map((e) => e.path)).toEqual(['familyDetails.siblings[0].age']);
    });

    it('fully empty rows are left out', () => {
      const { details, errors } = fam([{}, { relation: '', name: ' ' }]);
      expect(errors).toEqual([]);
      expect(details).toEqual({});
    });
  });
});

describe('setAnswer (merging into the complete draft)', () => {
  const full = {
    basicDetails: { firstName: 'Priya', lastName: 'S' },
    religionDetails: { religionCode: 'HINDU', communityCode: 'HINDU-VELLALAR' },
    locationDetails: { countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-TN-MADURAI' },
    educationDetails: { qualification: 'MBA / PGDM' },
  };

  it('editing one field keeps every other section and field, and is immutable', () => {
    const next = setAnswer(full, 'basicDetails.firstName', 'Divya');
    expect(next).toEqual({ ...full, basicDetails: { firstName: 'Divya', lastName: 'S' } });
    expect(full.basicDetails.firstName).toBe('Priya');
  });

  it('changing religion clears the community only', () => {
    const next = setAnswer(full, 'religionDetails.religionCode', 'CHRISTIAN');
    expect(getPath(next, 'religionDetails.communityCode')).toBeUndefined();
    expect(getPath(next, 'locationDetails.cityCode')).toBe('IN-TN-MADURAI');
  });

  it('changing country clears state and city; state clears city', () => {
    const a = setAnswer(full, 'locationDetails.countryCode', 'US');
    expect(getPath(a, 'locationDetails.stateCode')).toBeUndefined();
    expect(getPath(a, 'locationDetails.cityCode')).toBeUndefined();
    const b = setAnswer(full, 'locationDetails.stateCode', 'IN-KA');
    expect(getPath(b, 'locationDetails.cityCode')).toBeUndefined();
    expect(getPath(b, 'locationDetails.countryCode')).toBe('IN');
  });

  it('setting the same value changes nothing', () => {
    expect(setAnswer(full, 'religionDetails.religionCode', 'HINDU')).toBe(full);
  });
});
