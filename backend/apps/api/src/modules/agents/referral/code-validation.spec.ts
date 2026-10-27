import {
  CodeValidationAttemptInput,
  decideCodeValidationAttempt,
  toValidateResponse,
  ValidateResponseInput,
} from './code-validation';

const attempt = (
  overrides: Partial<CodeValidationAttemptInput> = {},
): CodeValidationAttemptInput => ({
  ipAttempts: 0,
  codeAttempts: 0,
  ipLimit: 10,
  codeLimit: 20,
  ...overrides,
});

describe('decideCodeValidationAttempt', () => {
  it('allows the first attempt', () => {
    expect(decideCodeValidationAttempt(attempt())).toEqual({ allowed: true });
  });

  describe('IP_LIMIT', () => {
    it('allows one below the limit', () => {
      expect(decideCodeValidationAttempt(attempt({ ipAttempts: 9 }))).toEqual({
        allowed: true,
      });
    });

    it('blocks exactly at the limit', () => {
      expect(decideCodeValidationAttempt(attempt({ ipAttempts: 10 }))).toEqual({
        allowed: false,
        reason: 'IP_LIMIT',
      });
    });

    it('blocks above the limit', () => {
      expect(
        decideCodeValidationAttempt(attempt({ ipAttempts: 500 })).allowed,
      ).toBe(false);
    });

    it('uses the limit it is given', () => {
      expect(
        decideCodeValidationAttempt(attempt({ ipAttempts: 1, ipLimit: 1 })),
      ).toEqual({ allowed: false, reason: 'IP_LIMIT' });
    });
  });

  describe('CODE_LIMIT', () => {
    it('allows one below the limit', () => {
      expect(
        decideCodeValidationAttempt(attempt({ codeAttempts: 19 })),
      ).toEqual({ allowed: true });
    });

    it('blocks exactly at the limit', () => {
      expect(
        decideCodeValidationAttempt(attempt({ codeAttempts: 20 })),
      ).toEqual({ allowed: false, reason: 'CODE_LIMIT' });
    });
  });

  it('checks the IP limit first', () => {
    expect(
      decideCodeValidationAttempt(
        attempt({ ipAttempts: 10, codeAttempts: 20 }),
      ),
    ).toEqual({ allowed: false, reason: 'IP_LIMIT' });
  });

  describe('validation', () => {
    it.each([-1, 1.5, NaN, Infinity])('rejects ipAttempts %p', (value) => {
      expect(() =>
        decideCodeValidationAttempt(attempt({ ipAttempts: value })),
      ).toThrow(RangeError);
    });

    it.each([-1, 1.5, NaN, Infinity])('rejects codeAttempts %p', (value) => {
      expect(() =>
        decideCodeValidationAttempt(attempt({ codeAttempts: value })),
      ).toThrow(RangeError);
    });

    it.each([0, -1, 1.5, NaN, Infinity])('rejects ipLimit %p', (value) => {
      expect(() =>
        decideCodeValidationAttempt(attempt({ ipLimit: value })),
      ).toThrow(RangeError);
    });

    it.each([0, -1, 1.5, NaN, Infinity])('rejects codeLimit %p', (value) => {
      expect(() =>
        decideCodeValidationAttempt(attempt({ codeLimit: value })),
      ).toThrow(RangeError);
    });

    it('accepts zero attempts and a limit of 1', () => {
      expect(
        decideCodeValidationAttempt(
          attempt({ ipAttempts: 0, codeAttempts: 0, ipLimit: 1, codeLimit: 1 }),
        ),
      ).toEqual({ allowed: true });
    });
  });
});

const response = (
  overrides: Partial<ValidateResponseInput> = {},
): ValidateResponseInput => ({
  found: true,
  codeActive: true,
  agentStatus: 'ACTIVE',
  firstName: 'Ravi',
  lastName: 'Kumar',
  ...overrides,
});

describe('toValidateResponse', () => {
  it('a valid code shows first name and last initial', () => {
    expect(toValidateResponse(response())).toEqual({
      valid: true,
      agentDisplayName: 'Ravi K.',
    });
  });

  it('uses the first name alone when there is no last name', () => {
    expect(toValidateResponse(response({ lastName: null }))).toEqual({
      valid: true,
      agentDisplayName: 'Ravi',
    });
  });

  it('uses the first grapheme for a Tamil last name', () => {
    expect(
      toValidateResponse(response({ firstName: 'அருண்', lastName: 'குமார்' })),
    ).toEqual({ valid: true, agentDisplayName: 'அருண் கு.' });
  });

  it('a valid code with no usable name has a null display name', () => {
    expect(
      toValidateResponse(response({ firstName: '  ', lastName: null })),
    ).toEqual({ valid: true, agentDisplayName: null });
    expect(
      toValidateResponse(response({ firstName: null, lastName: null })),
    ).toEqual({ valid: true, agentDisplayName: null });
  });

  it('never returns more than the two fields', () => {
    expect(Object.keys(toValidateResponse(response())).sort()).toEqual([
      'agentDisplayName',
      'valid',
    ]);
  });

  describe('every invalid case is identical', () => {
    const INVALID = { valid: false, agentDisplayName: null };

    const cases: Array<[string, Partial<ValidateResponseInput>]> = [
      ['code not found', { found: false }],
      [
        'code not found, no agent data',
        {
          found: false,
          agentStatus: null,
          firstName: null,
          lastName: null,
        },
      ],
      ['code inactive', { codeActive: false }],
      ['agent PENDING_APPROVAL', { agentStatus: 'PENDING_APPROVAL' }],
      ['agent REJECTED', { agentStatus: 'REJECTED' }],
      ['agent SUSPENDED', { agentStatus: 'SUSPENDED' }],
      ['agent TERMINATED', { agentStatus: 'TERMINATED' }],
      ['agent status unknown', { agentStatus: 'active' }],
      ['agent status null', { agentStatus: null }],
      [
        'everything wrong',
        {
          found: false,
          codeActive: false,
          agentStatus: 'TERMINATED',
        },
      ],
    ];

    it.each(cases)('%s', (_label, overrides) => {
      expect(toValidateResponse(response(overrides))).toEqual(INVALID);
    });

    it('all invalid results serialise to the same bytes and leak no name', () => {
      const bodies = cases.map(([, overrides]) =>
        JSON.stringify(toValidateResponse(response(overrides))),
      );
      expect(new Set(bodies).size).toBe(1);
      expect(bodies[0]).toBe('{"valid":false,"agentDisplayName":null}');
      expect(bodies[0]).not.toContain('Ravi');
    });
  });
});
