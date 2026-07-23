import {
  isEducationDetailsValid,
  isEducationSectionTouched,
  isReligionDetailsComplete,
} from '../validation/registration-rules';

describe('isReligionDetailsComplete', () => {
  const complete = {
    religion: 'Hindu',
    caste: 'Iyer',
    subCaste: 'Vadama',
    community: 'Brahmin',
  };

  it('is true when religion, caste, subCaste, and community are all present', () => {
    expect(isReligionDetailsComplete(complete)).toBe(true);
  });

  it('is false when religion is missing', () => {
    expect(
      isReligionDetailsComplete({ ...complete, religion: undefined }),
    ).toBe(false);
  });

  it('is false when caste is missing', () => {
    expect(isReligionDetailsComplete({ ...complete, caste: '' })).toBe(false);
  });

  it('is false when subCaste is missing', () => {
    expect(isReligionDetailsComplete({ ...complete, subCaste: '' })).toBe(
      false,
    );
  });

  it('is false when community is missing', () => {
    expect(isReligionDetailsComplete({ ...complete, community: '' })).toBe(
      false,
    );
  });

  it('is false when religion is the literal "Other" placeholder (no custom value typed yet)', () => {
    expect(
      isReligionDetailsComplete({ ...complete, religion: 'Other' }),
    ).toBe(false);
  });

  it('is true when religion is a genuine custom value entered after selecting "Other"', () => {
    expect(
      isReligionDetailsComplete({ ...complete, religion: 'Zoroastrian' }),
    ).toBe(true);
  });
});

describe('isEducationDetailsValid', () => {
  const complete = {
    qualification: "Bachelor's",
    college: 'Anna University',
    occupation: 'Engineer',
    company: 'Acme Corp',
    employmentType: 'Private',
    annualIncome: '10',
    workLocation: 'Chennai',
  };

  it('is valid when the entire section is untouched (skipped)', () => {
    expect(isEducationSectionTouched({})).toBe(false);
    expect(isEducationDetailsValid({})).toBe(true);
  });

  it('is invalid with only Qualification filled', () => {
    expect(
      isEducationDetailsValid({ qualification: "Bachelor's" }),
    ).toBe(false);
  });

  it('is invalid when College is missing', () => {
    const { college: _college, ...rest } = complete;
    expect(isEducationDetailsValid(rest)).toBe(false);
  });

  it('is invalid when Company is missing', () => {
    const { company: _company, ...rest } = complete;
    expect(isEducationDetailsValid(rest)).toBe(false);
  });

  it('is invalid when Annual Income is missing', () => {
    const { annualIncome: _annualIncome, ...rest } = complete;
    expect(isEducationDetailsValid(rest)).toBe(false);
  });

  it('is invalid when Work Location is missing', () => {
    const { workLocation: _workLocation, ...rest } = complete;
    expect(isEducationDetailsValid(rest)).toBe(false);
  });

  it('is valid when every field is filled', () => {
    expect(isEducationDetailsValid(complete)).toBe(true);
  });

  it('is invalid when Annual Income is the literal "Other" placeholder (no custom value typed yet)', () => {
    expect(
      isEducationDetailsValid({ ...complete, annualIncome: 'Other' }),
    ).toBe(false);
  });

  it('is valid when Annual Income is a genuine custom value entered after selecting "Other"', () => {
    expect(
      isEducationDetailsValid({ ...complete, annualIncome: '37' }),
    ).toBe(true);
  });
});
