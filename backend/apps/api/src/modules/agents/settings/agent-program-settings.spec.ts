import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_CLIENT_DRAFT_LIMIT_KEY,
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
  AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
  AGENT_PROGRAM_SETTING_KEYS,
  AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
  COMMISSION_AUTO_APPROVE_KEY,
  COMMISSION_BASE_KEY,
  COMMISSION_BASE_PROVISIONAL_KEY,
  COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
  PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
  PAYOUT_TAX_WITHHOLDING_KEY,
  parseAgentProgramSettings,
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
  REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
  REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
  validateCommissionPolicyVersion,
} from './agent-program-settings';

const ALL: Record<string, unknown> = {
  [COMMISSION_AUTO_APPROVE_KEY]: true,
  [COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY]: false,
  [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: 60,
  [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: 500,
  [REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY]: false,
  [REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY]: true,
  [PAYOUT_MINIMUM_AMOUNT_PAISE_KEY]: 50_000,
  [AGENT_CLIENT_DRAFT_LIMIT_KEY]: 10,
  [AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY]: 24,
  [COMMISSION_BASE_KEY]: 'AMOUNT_PAID',
  [COMMISSION_BASE_PROVISIONAL_KEY]: true,
  [PAYOUT_TAX_WITHHOLDING_KEY]: { anything: 'goes' },
  [AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY]: 900,
  [AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY]: 2_592_000,
  [AGENT_OTP_RESEND_AFTER_SECONDS_KEY]: 30,
  [REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY]: 10,
  [REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY]: 20,
  [REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY]: 60,
};

describe('setting keys', () => {
  it('uses the agreed key names', () => {
    expect(COMMISSION_AUTO_APPROVE_KEY).toBe('commission.auto_approve');
    expect(COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY).toBe(
      'commission.require_verified_profile',
    );
    expect(REFERRAL_CREDIT_WINDOW_DAYS_KEY).toBe('referral.credit_window_days');
    expect(REFERRAL_MEMBER_DISCOUNT_BPS_KEY).toBe(
      'referral.member_discount_bps',
    );
    expect(REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY).toBe(
      'referral.discount_stacks_with_coupons',
    );
    expect(REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY).toBe(
      'referral.discount_only_in_credit_window',
    );
    expect(PAYOUT_MINIMUM_AMOUNT_PAISE_KEY).toBe('payout.minimum_amount_paise');
    expect(AGENT_CLIENT_DRAFT_LIMIT_KEY).toBe('agent.client_draft_limit');
    expect(AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY).toBe(
      'agent.payout_details_wait_hours',
    );
    expect(COMMISSION_BASE_KEY).toBe('commission.base');
    expect(COMMISSION_BASE_PROVISIONAL_KEY).toBe('commission.base_provisional');
    expect(PAYOUT_TAX_WITHHOLDING_KEY).toBe('payout.tax_withholding');
    expect(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY).toBe(
      'agent.access_token_ttl_seconds',
    );
    expect(AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY).toBe(
      'agent.refresh_token_ttl_seconds',
    );
    expect(AGENT_OTP_RESEND_AFTER_SECONDS_KEY).toBe(
      'agent.otp_resend_after_seconds',
    );
    expect(REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY).toBe(
      'referral.code_validation_ip_limit',
    );
    expect(REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY).toBe(
      'referral.code_validation_code_limit',
    );
    expect(REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY).toBe(
      'referral.code_validation_window_seconds',
    );
    expect(AGENT_PROGRAM_SETTING_KEYS).toHaveLength(18);
  });
});

describe('parseAgentProgramSettings', () => {
  it('parses a complete set', () => {
    expect(parseAgentProgramSettings(ALL)).toEqual({
      settings: {
        commissionAutoApprove: true,
        commissionRequireVerifiedProfile: false,
        referralCreditWindowDays: 60,
        referralMemberDiscountBps: 500,
        referralDiscountStacksWithCoupons: false,
        referralDiscountOnlyInCreditWindow: true,
        payoutMinimumAmountPaise: 50_000,
        agentClientDraftLimit: 10,
        agentPayoutDetailsWaitHours: 24,
        commissionBase: 'AMOUNT_PAID',
        commissionBaseProvisional: true,
        payoutTaxWithholding: { anything: 'goes' },
        accessTokenTtlSeconds: 900,
        refreshTokenTtlSeconds: 2_592_000,
        otpResendAfterSeconds: 30,
        codeValidationIpLimit: 10,
        codeValidationCodeLimit: 20,
        codeValidationWindowSeconds: 60,
      },
      missing: [],
    });
  });

  it('lists every key as missing, with no defaults, for an empty input', () => {
    const result = parseAgentProgramSettings({});
    expect(result.settings).toEqual({});
    expect(result.missing).toEqual([...AGENT_PROGRAM_SETTING_KEYS]);
  });

  it.each(AGENT_PROGRAM_SETTING_KEYS.map((k) => [k]))(
    'reports only %s as missing when it alone is absent',
    (key) => {
      const raw = { ...ALL };
      delete raw[key];
      const result = parseAgentProgramSettings(raw);
      expect(result.missing).toEqual([key]);
      expect(Object.keys(result.settings)).toHaveLength(17);
    },
  );

  it('treats an explicit undefined as absent', () => {
    const result = parseAgentProgramSettings({
      ...ALL,
      [AGENT_CLIENT_DRAFT_LIMIT_KEY]: undefined,
    });
    expect(result.missing).toEqual([AGENT_CLIENT_DRAFT_LIMIT_KEY]);
    expect(result.settings).not.toHaveProperty('agentClientDraftLimit');
  });

  describe('null', () => {
    const NULL_IS_VALUE = [COMMISSION_BASE_KEY, PAYOUT_TAX_WITHHOLDING_KEY];
    const NULL_IS_MISSING = AGENT_PROGRAM_SETTING_KEYS.filter(
      (key) => !NULL_IS_VALUE.includes(key),
    );

    it('counts as missing for exactly sixteen keys', () => {
      expect(NULL_IS_MISSING).toHaveLength(16);
    });

    it.each(NULL_IS_MISSING.map((k) => [k]))(
      'is missing, with no default, for %s',
      (key) => {
        const result = parseAgentProgramSettings({ ...ALL, [key]: null });
        expect(result.missing).toEqual([key]);
        expect(Object.keys(result.settings)).toHaveLength(17);
        expect(Object.values(result.settings)).not.toContain(null);
      },
    );

    it.each(NULL_IS_VALUE.map((k) => [k]))(
      'is a real value, not missing, for %s',
      (key) => {
        const result = parseAgentProgramSettings({ ...ALL, [key]: null });
        expect(result.missing).toEqual([]);
        expect(Object.keys(result.settings)).toHaveLength(18);
      },
    );

    it('null and undefined together are all reported, in key order', () => {
      const result = parseAgentProgramSettings({
        ...ALL,
        [COMMISSION_AUTO_APPROVE_KEY]: null,
        [AGENT_CLIENT_DRAFT_LIMIT_KEY]: undefined,
        [COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY]: null,
      });
      expect(result.missing).toEqual([
        COMMISSION_AUTO_APPROVE_KEY,
        COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
        AGENT_CLIENT_DRAFT_LIMIT_KEY,
      ]);
    });

    it('an all-null input leaves only the two null-valued keys set', () => {
      const allNull = Object.fromEntries(
        AGENT_PROGRAM_SETTING_KEYS.map((key) => [key, null]),
      );
      const result = parseAgentProgramSettings(allNull);
      expect(result.missing).toEqual(NULL_IS_MISSING);
      expect(result.settings).toEqual({
        commissionBase: null,
        payoutTaxWithholding: null,
      });
    });
  });

  it('ignores keys it does not know', () => {
    const result = parseAgentProgramSettings({ ...ALL, 'something.else': 1 });
    expect(result.missing).toEqual([]);
    expect(JSON.stringify(result.settings)).not.toContain('something');
  });

  it('does not read inherited properties', () => {
    const raw = Object.create({ [AGENT_CLIENT_DRAFT_LIMIT_KEY]: 5 }) as Record<
      string,
      unknown
    >;
    expect(parseAgentProgramSettings(raw).missing).toContain(
      AGENT_CLIENT_DRAFT_LIMIT_KEY,
    );
  });

  describe('booleans', () => {
    const keys = [
      COMMISSION_AUTO_APPROVE_KEY,
      COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
      REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY,
      REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
      COMMISSION_BASE_PROVISIONAL_KEY,
    ];
    for (const key of keys) {
      it.each(['true', 'yes', 1, 0, {}])(`${key} rejects %p`, (value) => {
        expect(() =>
          parseAgentProgramSettings({ ...ALL, [key]: value }),
        ).toThrow(new RegExp(key.replace(/\./g, '\\.')));
      });
    }
  });

  describe('non-negative integers', () => {
    const keys = [
      REFERRAL_CREDIT_WINDOW_DAYS_KEY,
      PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
      AGENT_CLIENT_DRAFT_LIMIT_KEY,
      AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
    ];
    for (const key of keys) {
      it(`${key} accepts 0`, () => {
        expect(parseAgentProgramSettings({ ...ALL, [key]: 0 }).missing).toEqual(
          [],
        );
      });
      it.each([-1, 1.5, NaN, Infinity, '10', true])(
        `${key} rejects %p`,
        (value) => {
          expect(() =>
            parseAgentProgramSettings({ ...ALL, [key]: value }),
          ).toThrow(RangeError);
          expect(() =>
            parseAgentProgramSettings({ ...ALL, [key]: value }),
          ).toThrow(new RegExp(key.replace(/\./g, '\\.')));
        },
      );
    }
  });

  describe('referral.member_discount_bps', () => {
    it.each([0, 1, 500, 10_000])('accepts %p', (value) => {
      expect(
        parseAgentProgramSettings({
          ...ALL,
          [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: value,
        }).settings.referralMemberDiscountBps,
      ).toBe(value);
    });

    it.each([-1, 10_001, 5.5, '500'])('rejects %p', (value) => {
      expect(() =>
        parseAgentProgramSettings({
          ...ALL,
          [REFERRAL_MEMBER_DISCOUNT_BPS_KEY]: value,
        }),
      ).toThrow(/referral\.member_discount_bps/);
    });
  });

  describe('commission.base', () => {
    it.each([null, 'AMOUNT_PAID', 'AMOUNT_PAID_EXCLUDING_GST'])(
      'accepts %p (null is present, not missing)',
      (value) => {
        const result = parseAgentProgramSettings({
          ...ALL,
          [COMMISSION_BASE_KEY]: value,
        });
        expect(result.missing).toEqual([]);
        expect(result.settings.commissionBase).toBe(value);
      },
    );

    it.each(['amount_paid', 'GROSS', '', 1, true])('rejects %p', (value) => {
      expect(() =>
        parseAgentProgramSettings({ ...ALL, [COMMISSION_BASE_KEY]: value }),
      ).toThrow(/commission\.base/);
    });
  });

  describe('payout.tax_withholding', () => {
    it.each([null, 'x', 5, { rate: 1 }, [1, 2], false])(
      'passes %p through untouched',
      (value) => {
        const result = parseAgentProgramSettings({
          ...ALL,
          [PAYOUT_TAX_WITHHOLDING_KEY]: value,
        });
        expect(result.missing).toEqual([]);
        expect(result.settings.payoutTaxWithholding).toBe(value);
      },
    );
  });
});

describe('validateCommissionPolicyVersion', () => {
  const policy = (
    overrides: Partial<{
      calcType: string;
      value: number;
      holdDays: number;
    }> = {},
  ) => ({ calcType: 'PERCENTAGE', value: 1000, holdDays: 14, ...overrides });

  it('accepts a valid policy', () => {
    expect(() => validateCommissionPolicyVersion(policy())).not.toThrow();
  });

  it.each([0, 1, 9_999])('accepts value %p', (value) => {
    expect(() =>
      validateCommissionPolicyVersion(policy({ value })),
    ).not.toThrow();
  });

  it.each([0, 1, 365])('accepts holdDays %p', (holdDays) => {
    expect(() =>
      validateCommissionPolicyVersion(policy({ holdDays })),
    ).not.toThrow();
  });

  it.each(['FIXED', 'percentage', '', 'FLAT'])(
    'rejects calcType %p',
    (calcType) => {
      expect(() =>
        validateCommissionPolicyVersion(policy({ calcType })),
      ).toThrow(RangeError);
    },
  );

  it.each([-1, 10_000, 12_000, 5.5, NaN, Infinity])(
    'rejects value %p',
    (value) => {
      expect(() => validateCommissionPolicyVersion(policy({ value }))).toThrow(
        RangeError,
      );
    },
  );

  it.each([-1, 1.5, NaN, Infinity])('rejects holdDays %p', (holdDays) => {
    expect(() => validateCommissionPolicyVersion(policy({ holdDays }))).toThrow(
      RangeError,
    );
  });
});

describe('positive-integer settings (timing and rate limits)', () => {
  const KEYS = [
    AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
    AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
    AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
    REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
    REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
    REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
  ];

  it.each(KEYS.map((k) => [k]))(
    '%s has no default: absent is missing',
    (key) => {
      const raw = { ...ALL };
      delete raw[key];
      const result = parseAgentProgramSettings(raw);
      expect(result.missing).toEqual([key]);
      expect(Object.keys(result.settings)).toHaveLength(17);
    },
  );

  it.each(KEYS.map((k) => [k]))('%s: null is missing, not a value', (key) => {
    const result = parseAgentProgramSettings({ ...ALL, [key]: null });
    expect(result.missing).toEqual([key]);
  });

  it.each(KEYS.map((k) => [k]))('%s accepts 1 as the smallest value', (key) => {
    const result = parseAgentProgramSettings({ ...ALL, [key]: 1 });
    expect(result.missing).toEqual([]);
  });

  describe.each(KEYS)('%s must be a positive integer', (key) => {
    it.each([0, -1, 1.5, NaN, Infinity, '30', true, Number.MAX_VALUE])(
      'rejects %p and names the key',
      (value) => {
        expect(() =>
          parseAgentProgramSettings({ ...ALL, [key]: value }),
        ).toThrow(new RangeError(`Setting ${key} must be an integer >= 1.`));
      },
    );
  });
});
