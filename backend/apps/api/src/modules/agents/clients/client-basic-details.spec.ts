import {
  CLIENT_NAME_MAX_LENGTH,
  CLIENT_PROFILE_CREATED_FOR,
  parseStoredClientBasicDetails,
  validateClientBasicDetails,
} from './client-basic-details';

const NOW = new Date('2026-11-03T10:00:00.000Z');

const VALID = {
  firstName: 'Priya',
  lastName: 'Sundaram',
  gender: 'FEMALE',
  dob: '1998-04-12',
  maritalStatus: 'NEVER_MARRIED',
  profileCreatedFor: 'Daughter',
};

const fieldsOf = (input: unknown) => {
  const check = validateClientBasicDetails(input, NOW);
  return check.ok ? [] : check.fields;
};

describe('validateClientBasicDetails', () => {
  it('accepts the six step-1 fields and trims the names', () => {
    expect(
      validateClientBasicDetails(
        { ...VALID, firstName: '  Priya ', lastName: ' Sundaram  ' },
        NOW,
      ),
    ).toEqual({ ok: true, details: VALID });
  });

  it('refuses anything that is not an object', () => {
    for (const input of [null, undefined, 'x', 3, [VALID]]) {
      expect(fieldsOf(input)).toEqual(['details']);
    }
  });

  it('names every missing or wrong field, never a value', () => {
    expect(fieldsOf({})).toEqual([
      'details.firstName',
      'details.lastName',
      'details.gender',
      'details.dob',
      'details.maritalStatus',
      'details.profileCreatedFor',
    ]);
    const check = validateClientBasicDetails(
      { ...VALID, gender: 'OTHER', maritalStatus: 'MARRIED' },
      NOW,
    );
    expect(check).toEqual({
      ok: false,
      fields: ['details.gender', 'details.maritalStatus'],
    });
    expect(JSON.stringify(check)).not.toContain('OTHER');
  });

  it('refuses an extra property without echoing its name', () => {
    expect(fieldsOf({ ...VALID, phone: '+919876543210' })).toEqual(['details']);
  });

  it('names are 1 to 50 characters after trimming (Tamil counted by character)', () => {
    expect(fieldsOf({ ...VALID, firstName: '   ' })).toEqual([
      'details.firstName',
    ]);
    expect(
      fieldsOf({ ...VALID, lastName: 'x'.repeat(CLIENT_NAME_MAX_LENGTH) }),
    ).toEqual([]);
    expect(
      fieldsOf({ ...VALID, lastName: 'x'.repeat(CLIENT_NAME_MAX_LENGTH + 1) }),
    ).toEqual(['details.lastName']);
    expect(fieldsOf({ ...VALID, firstName: 'பிரியா' })).toEqual([]);
    expect(fieldsOf({ ...VALID, firstName: 7 })).toEqual(['details.firstName']);
  });

  it('applies the wizard birth-date rule: a real day, at least 21 years before now', () => {
    expect(fieldsOf({ ...VALID, dob: '2005-11-03' })).toEqual([]);
    expect(fieldsOf({ ...VALID, dob: '2005-11-04' })).toEqual(['details.dob']);
    expect(fieldsOf({ ...VALID, dob: '1998-02-30' })).toEqual(['details.dob']);
    expect(fieldsOf({ ...VALID, dob: '2030-01-01' })).toEqual(['details.dob']);
  });

  it('takes a calendar date only, not a timestamp', () => {
    expect(fieldsOf({ ...VALID, dob: '1998-04-12T00:00:00.000' })).toEqual([
      'details.dob',
    ]);
    expect(fieldsOf({ ...VALID, dob: '12-04-1998' })).toEqual(['details.dob']);
  });

  it('allows exactly the member app values for who the profile is for', () => {
    for (const value of CLIENT_PROFILE_CREATED_FOR) {
      expect(fieldsOf({ ...VALID, profileCreatedFor: value })).toEqual([]);
    }
    expect(fieldsOf({ ...VALID, profileCreatedFor: 'myself' })).toEqual([
      'details.profileCreatedFor',
    ]);
  });
});

describe('parseStoredClientBasicDetails', () => {
  it('reads back what was stored', () => {
    expect(parseStoredClientBasicDetails(JSON.stringify(VALID))).toEqual(VALID);
  });

  it('throws on corrupt data', () => {
    expect(() => parseStoredClientBasicDetails('[]')).toThrow(TypeError);
    expect(() =>
      parseStoredClientBasicDetails(JSON.stringify({ firstName: 'A' })),
    ).toThrow('incomplete');
  });
});
