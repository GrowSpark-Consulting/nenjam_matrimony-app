import {
  isEducationDetailsValid,
  isEducationSectionTouched,
  isLifestyleDetailsValid,
  isLifestyleSectionTouched,
  isPhysicalDetailsValid,
  isPhysicalSectionTouched,
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

  // Caste and sub-caste left this contract when onboarding stopped asking for
  // them. Requiring either would make finalize() unsatisfiable for every
  // profile the current signup flow can produce — sub-community is offered on
  // the "Let's build your Profile" step but is optional, and caste is not
  // collected at all.
  it('is true when caste is missing — onboarding no longer collects it', () => {
    expect(isReligionDetailsComplete({ ...complete, caste: '' })).toBe(true);
  });

  it('is true when subCaste is missing — it is optional', () => {
    expect(isReligionDetailsComplete({ ...complete, subCaste: '' })).toBe(true);
  });

  it('is false when community is missing', () => {
    expect(isReligionDetailsComplete({ ...complete, community: '' })).toBe(
      false,
    );
  });

  it('is false when religion is the literal "Other" placeholder (no custom value typed yet)', () => {
    expect(isReligionDetailsComplete({ ...complete, religion: 'Other' })).toBe(
      false,
    );
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
    expect(isEducationDetailsValid({ qualification: "Bachelor's" })).toBe(
      false,
    );
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

  // No screen in the current registration flow asks for Work Location, so it
  // cannot be required — requiring it rejected every onboarding signup for a
  // field the member was never shown. It still marks the section as touched
  // (the full wizard's Education step does collect it).
  it('is valid when Work Location is missing — no current screen collects it', () => {
    const { workLocation: _workLocation, ...rest } = complete;
    expect(isEducationDetailsValid(rest)).toBe(true);
  });

  it('is invalid when Work Location alone is filled, with nothing else', () => {
    expect(isEducationSectionTouched({ workLocation: 'Chennai' })).toBe(true);
    expect(isEducationDetailsValid({ workLocation: 'Chennai' })).toBe(false);
  });

  // The exact payload onboarding's Education + Income steps produce.
  it('is valid for the section onboarding actually fills', () => {
    expect(
      isEducationDetailsValid({
        qualification: "Bachelor's",
        college: 'Anna University',
        occupation: 'Engineer',
        company: 'Acme Corp',
        employmentType: 'Private',
        annualIncome: '10',
      }),
    ).toBe(true);
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
    expect(isEducationDetailsValid({ ...complete, annualIncome: '37' })).toBe(
      true,
    );
  });
});

// Both sections below are half-filled by onboarding on the member's behalf,
// without the corresponding wizard step ever being shown. Finalize used to
// reject exactly that shape, naming steps the member had never opened, which
// made a fresh-device signup impossible to complete.
describe('isPhysicalDetailsValid', () => {
  const complete = { height: '5ft 8in', weight: '70 kg', disability: 'None' };

  it('is valid when the entire section is untouched (skipped)', () => {
    expect(isPhysicalSectionTouched({})).toBe(false);
    expect(isPhysicalDetailsValid({})).toBe(true);
  });

  // `disability` defaults to 'None' on the client and is sent by every
  // payload, so on its own it must never count as engagement.
  it('is valid with only the default disability value', () => {
    expect(isPhysicalSectionTouched({ disability: 'None' })).toBe(false);
    expect(isPhysicalDetailsValid({ disability: 'None' })).toBe(true);
  });

  // The exact shape onboarding's Marital step produces: height written for
  // the member, Physical step never opened.
  it('is valid with the height onboarding writes, and no weight', () => {
    expect(isPhysicalSectionTouched({ height: '5ft 8in', disability: 'None' }))
      .toBe(false);
    expect(isPhysicalDetailsValid({ height: '5ft 8in', disability: 'None' }))
      .toBe(true);
  });

  // Opening the Physical step always writes weight, so the all-or-nothing
  // rule still binds anyone who actually engages with it.
  it('is invalid when weight is set but height is missing', () => {
    expect(isPhysicalSectionTouched({ weight: '70 kg' })).toBe(true);
    expect(isPhysicalDetailsValid({ weight: '70 kg', disability: 'None' }))
      .toBe(false);
  });

  it('is invalid when weight is set but disability is missing', () => {
    expect(isPhysicalDetailsValid({ height: '5ft 8in', weight: '70 kg' })).toBe(
      false,
    );
  });

  it('is valid when every field is filled', () => {
    expect(isPhysicalDetailsValid(complete)).toBe(true);
  });
});

describe('isLifestyleDetailsValid', () => {
  const complete = {
    eatingHabit: 'Vegetarian',
    smoking: 'No',
    drinking: 'No',
    fitness: 'Regular',
    hobbies: ['Reading'],
    aboutMe: 'A short description.',
  };

  it('is valid when the entire section is untouched (skipped)', () => {
    expect(isLifestyleSectionTouched({})).toBe(false);
    expect(isLifestyleDetailsValid({})).toBe(true);
  });

  // The exact shape onboarding produces: eatingHabit from the Marital step,
  // aboutMe from the About step, Lifestyle step never opened.
  it('is valid with only the fields onboarding writes', () => {
    const onboarding = {
      eatingHabit: 'Vegetarian',
      aboutMe: 'A short description.',
    };
    expect(isLifestyleSectionTouched(onboarding)).toBe(false);
    expect(isLifestyleDetailsValid(onboarding)).toBe(true);
  });

  // Opening the Lifestyle step writes smoking/drinking/fitness together, so
  // engaging with it still requires the whole section.
  it('is invalid once a Lifestyle-only field is set but the rest is missing', () => {
    expect(isLifestyleSectionTouched({ smoking: 'No' })).toBe(true);
    expect(isLifestyleDetailsValid({ smoking: 'No' })).toBe(false);
  });

  it('is invalid when hobbies are chosen but the scalars are missing', () => {
    expect(isLifestyleSectionTouched({ hobbies: ['Reading'] })).toBe(true);
    expect(isLifestyleDetailsValid({ hobbies: ['Reading'] })).toBe(false);
  });

  it('is invalid when every scalar is filled but hobbies are empty', () => {
    expect(isLifestyleDetailsValid({ ...complete, hobbies: [] })).toBe(false);
  });

  it('is valid when every field is filled', () => {
    expect(isLifestyleDetailsValid(complete)).toBe(true);
  });
});
