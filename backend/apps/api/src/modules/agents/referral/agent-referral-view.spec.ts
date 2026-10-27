import {
  AGENT_REFERRAL_VIEW_FIELDS,
  COMMISSION_STATUS_PUBLIC_MAP,
  FULLY_MASKED_PHONE,
  IST_OFFSET_MS,
  InternalCommissionStatus,
  maskPhone,
  ReferralViewSource,
  toAgentReferralView,
  toDisplayName,
  toPublicCommissionStatus,
} from './agent-referral-view';

const source = (
  overrides: Partial<ReferralViewSource> = {},
): ReferralViewSource => ({
  attributionId: 'attr-1',
  firstName: 'Priya',
  lastName: 'Sharma',
  phoneE164: '+919876543210',
  age: 27,
  city: 'Chennai',
  signedUpAt: new Date('2026-10-01T08:30:00Z'),
  stage: 'PURCHASED',
  profileCompletenessPct: 85,
  planName: 'Gold',
  purchasedAt: '2026-10-05T10:00:00Z',
  commissionStatus: 'APPROVED',
  ...overrides,
});

describe('toAgentReferralView', () => {
  it('has exactly the allow-listed keys', () => {
    const view = toAgentReferralView(source());
    expect(Object.keys(view).sort()).toEqual(
      [...AGENT_REFERRAL_VIEW_FIELDS].sort(),
    );
    expect(AGENT_REFERRAL_VIEW_FIELDS).toHaveLength(11);
  });

  it('maps the values', () => {
    expect(toAgentReferralView(source())).toEqual({
      id: 'attr-1',
      displayName: 'Priya S.',
      age: 27,
      city: 'Chennai',
      signedUpAt: '2026-10-01',
      stage: 'PURCHASED',
      profileCompletenessPct: 85,
      planName: 'Gold',
      purchasedAt: '2026-10-05',
      commissionStatus: 'APPROVED',
      maskedPhone: '+91 98***210',
    });
  });

  it('keeps the keys, with nulls, for a member who has not purchased', () => {
    const view = toAgentReferralView(
      source({
        stage: 'REGISTERED',
        planName: null,
        purchasedAt: null,
        commissionStatus: null,
      }),
    );
    expect(Object.keys(view).sort()).toEqual(
      [...AGENT_REFERRAL_VIEW_FIELDS].sort(),
    );
    expect(view.planName).toBeNull();
    expect(view.purchasedAt).toBeNull();
    expect(view.commissionStatus).toBeNull();
  });

  it('never leaks extra input fields', () => {
    const stuffed = {
      ...source({ commissionStatus: 'FROZEN' }),
      userId: 'user-secret-id',
      email: 'priya@example.com',
      photos: ['https://cdn.example.com/p1.jpg'],
      annualIncome: 2_400_000,
      fullPhone: '+919876543210',
      phone: '+919876543210',
      familyDetails: { fatherName: 'Secret Father' },
      horoscope: { rasi: 'Mesha' },
      internalCommissionStatus: 'FROZEN',
      fraudFlag: true,
    };
    const view = toAgentReferralView(stuffed);
    const json = JSON.stringify(view);

    expect(Object.keys(view).sort()).toEqual(
      [...AGENT_REFERRAL_VIEW_FIELDS].sort(),
    );
    for (const secret of [
      'user-secret-id',
      'priya@example.com',
      'cdn.example.com',
      '2400000',
      '9876543210',
      'Secret Father',
      'Mesha',
      'FROZEN',
      'fraud',
      'Sharma',
    ]) {
      expect(json).not.toContain(secret);
    }
  });

  it('uses the attribution id, not a user id', () => {
    const stuffed = { ...source(), id: 'user-id', userId: 'user-id' };
    expect(toAgentReferralView(stuffed).id).toBe('attr-1');
  });

  describe('dates in Indian time (UTC+05:30)', () => {
    const signedUp = (value: Date | string) =>
      toAgentReferralView(source({ signedUpAt: value })).signedUpAt;

    it('uses a fixed +05:30 offset', () => {
      expect(IST_OFFSET_MS).toBe(19_800_000);
    });

    it('rolls to the next day after 18:30 UTC', () => {
      expect(signedUp('2026-10-27T19:00:00Z')).toBe('2026-10-28');
      expect(signedUp('2026-10-27T18:30:00Z')).toBe('2026-10-28');
    });

    it('stays on the same day just before 18:30 UTC', () => {
      expect(signedUp('2026-10-27T18:29:59Z')).toBe('2026-10-27');
    });

    it('is the same day for the rest of the IST day', () => {
      expect(signedUp('2026-10-27T00:00:00Z')).toBe('2026-10-27');
      expect(signedUp('2026-10-26T18:30:00Z')).toBe('2026-10-27');
    });

    it('rolls over month and year ends', () => {
      expect(signedUp('2026-12-31T20:00:00Z')).toBe('2027-01-01');
    });

    it('accepts a Date and applies it to purchasedAt too', () => {
      const view = toAgentReferralView(
        source({
          signedUpAt: new Date('2026-10-27T19:00:00Z'),
          purchasedAt: new Date('2026-10-27T19:00:00Z'),
        }),
      );
      expect(view.signedUpAt).toBe('2026-10-28');
      expect(view.purchasedAt).toBe('2026-10-28');
    });

    it('outputs date-only strings', () => {
      expect(signedUp('2026-10-01T08:30:00Z')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    });
  });

  it('throws on an invalid date rather than emitting garbage', () => {
    expect(() => toAgentReferralView(source({ signedUpAt: 'nope' }))).toThrow(
      RangeError,
    );
  });

  it.each([
    [-5, 0],
    [0, 0],
    [49.6, 50],
    [100, 100],
    [250, 100],
    [NaN, 0],
  ])('clamps completeness %p to %p', (input, expected) => {
    expect(
      toAgentReferralView(source({ profileCompletenessPct: input }))
        .profileCompletenessPct,
    ).toBe(expected);
  });
});

describe('maskPhone', () => {
  it('masks a +91 number', () => {
    expect(maskPhone('+919876543210')).toBe('+91 98***210');
  });

  it('masks a +91 number written with spaces', () => {
    expect(maskPhone('+91 98765 43210')).toBe('+91 98***210');
    expect(maskPhone(' +91 9876-543-210 ')).toBe('+91 98***210');
  });

  it('fully masks a non-+91 number without leaking digits', () => {
    const result = maskPhone('+14155552671');
    expect(result).toBe(FULLY_MASKED_PHONE);
    expect(result).not.toMatch(/\d/);
  });

  it.each([
    ['a short string', '+9198765'],
    ['an empty string', ''],
    ['no plus sign', '919876543210'],
    ['too many digits', '+9198765432101'],
    ['letters', '+91987654321a'],
    ['only whitespace', '   '],
  ])('fully masks %s', (_label, input) => {
    const result = maskPhone(input);
    expect(result).toBe(FULLY_MASKED_PHONE);
    expect(result).not.toMatch(/\d/);
  });

  it('never throws on non-string input', () => {
    expect(maskPhone(undefined)).toBe(FULLY_MASKED_PHONE);
    expect(maskPhone(null)).toBe(FULLY_MASKED_PHONE);
    expect(maskPhone(12345 as unknown as string)).toBe(FULLY_MASKED_PHONE);
  });
});

describe('toDisplayName', () => {
  it('gives first name and last initial', () => {
    expect(toDisplayName('Priya', 'Sharma')).toBe('Priya S.');
  });

  it('gives the first name only without a last name', () => {
    expect(toDisplayName('Priya')).toBe('Priya');
    expect(toDisplayName('Priya', '')).toBe('Priya');
    expect(toDisplayName('Priya', null)).toBe('Priya');
    expect(toDisplayName('Priya', '   ')).toBe('Priya');
  });

  it('copes with extra spaces', () => {
    expect(toDisplayName('  Priya  ', '  Sharma  ')).toBe('Priya S.');
  });

  it('does not split either field: the initial is the start of the last name field', () => {
    expect(toDisplayName('Priya', 'Kumar Sharma')).toBe('Priya K.');
    expect(toDisplayName('Mary Ann', 'Sharma')).toBe('Mary Ann S.');
  });

  it('upper-cases a lower-case Latin initial', () => {
    expect(toDisplayName('priya', 'sharma')).toBe('priya S.');
  });

  it('takes the first grapheme of a Tamil name, not the first code unit', () => {
    // The last name starts with the syllable கு (க + ு), two code points.
    const last = 'குமார்';
    expect(toDisplayName('அருண்', last)).toBe('அருண் கு.');
    expect(last[0]).toBe('க'); // what string[0] would have produced
  });
});

describe('commission status mapping', () => {
  it.each<[InternalCommissionStatus, string]>([
    ['ON_HOLD', 'ON_HOLD'],
    ['AWAITING_VERIFICATION', 'ON_HOLD'],
    ['IN_REVIEW', 'ON_HOLD'],
    ['FROZEN', 'ON_HOLD'],
    ['READY', 'ON_HOLD'],
    ['APPROVED', 'APPROVED'],
    ['PAID', 'PAID'],
    ['CANCELLED', 'CANCELLED'],
    ['REVERSED', 'CANCELLED'],
  ])('maps %s to %s', (internal, expected) => {
    expect(toPublicCommissionStatus(internal)).toBe(expected);
  });

  it('covers every internal status in the table', () => {
    expect(Object.keys(COMMISSION_STATUS_PUBLIC_MAP)).toHaveLength(9);
  });

  it('keeps null as null', () => {
    expect(toPublicCommissionStatus(null)).toBeNull();
    expect(toPublicCommissionStatus(undefined)).toBeNull();
  });

  it('fails safe to ON_HOLD for an unknown internal status', () => {
    expect(
      toPublicCommissionStatus('FRAUD_SUSPECTED' as InternalCommissionStatus),
    ).toBe('ON_HOLD');
  });

  it('only ever outputs the four public values', () => {
    const allowed = new Set(['ON_HOLD', 'APPROVED', 'PAID', 'CANCELLED']);
    for (const value of Object.values(COMMISSION_STATUS_PUBLIC_MAP)) {
      expect(allowed.has(value)).toBe(true);
    }
  });
});
