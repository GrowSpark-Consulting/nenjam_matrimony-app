/**
 * Validation of the agent-program settings.
 *
 * Pure: the caller reads the raw setting values (key -> value) from wherever
 * settings live and passes them in. Nothing here supplies a default. A key
 * that is absent (undefined, or null for every key except commission.base and
 * payout.tax_withholding, where null is a real value) is reported in
 * `missing` and left out of `settings`; a key that is present but wrong throws
 * a RangeError that names it.
 */
import { COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY } from '../commission/profile-eligibility';

export const COMMISSION_AUTO_APPROVE_KEY = 'commission.auto_approve';
export { COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY };
export const REFERRAL_CREDIT_WINDOW_DAYS_KEY = 'referral.credit_window_days';
export const REFERRAL_MEMBER_DISCOUNT_BPS_KEY = 'referral.member_discount_bps';
export const REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY =
  'referral.discount_stacks_with_coupons';
export const REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY =
  'referral.discount_only_in_credit_window';
export const PAYOUT_MINIMUM_AMOUNT_PAISE_KEY = 'payout.minimum_amount_paise';
export const AGENT_CLIENT_DRAFT_LIMIT_KEY = 'agent.client_draft_limit';
export const AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY =
  'agent.payout_details_wait_hours';
export const COMMISSION_BASE_KEY = 'commission.base';
export const COMMISSION_BASE_PROVISIONAL_KEY = 'commission.base_provisional';
export const PAYOUT_TAX_WITHHOLDING_KEY = 'payout.tax_withholding';
export const AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY =
  'agent.access_token_ttl_seconds';
export const AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY =
  'agent.refresh_token_ttl_seconds';
export const AGENT_OTP_RESEND_AFTER_SECONDS_KEY =
  'agent.otp_resend_after_seconds';
export const REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY =
  'referral.code_validation_ip_limit';
export const REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY =
  'referral.code_validation_code_limit';
export const REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY =
  'referral.code_validation_window_seconds';

export type CommissionBase = 'AMOUNT_PAID' | 'AMOUNT_PAID_EXCLUDING_GST';

/** Every field is optional: an absent setting has no value and no default. */
export interface AgentProgramSettings {
  commissionAutoApprove?: boolean;
  commissionRequireVerifiedProfile?: boolean;
  referralCreditWindowDays?: number;
  referralMemberDiscountBps?: number;
  referralDiscountStacksWithCoupons?: boolean;
  referralDiscountOnlyInCreditWindow?: boolean;
  payoutMinimumAmountPaise?: number;
  agentClientDraftLimit?: number;
  agentPayoutDetailsWaitHours?: number;
  /** null is a valid, present value: "not decided yet". */
  commissionBase?: CommissionBase | null;
  commissionBaseProvisional?: boolean;
  /** Passed through untouched: the CA has not decided its shape. */
  payoutTaxWithholding?: unknown;
  accessTokenTtlSeconds?: number;
  refreshTokenTtlSeconds?: number;
  otpResendAfterSeconds?: number;
  codeValidationIpLimit?: number;
  codeValidationCodeLimit?: number;
  codeValidationWindowSeconds?: number;
}

export interface ParsedAgentProgramSettings {
  settings: AgentProgramSettings;
  /** Setting keys that were absent, in declaration order. */
  missing: string[];
}

type Rule = {
  key: string;
  field: keyof AgentProgramSettings;
  check: (value: unknown) => boolean;
  expected: string;
  /** null is a real value for this key; for every other key null = missing. */
  nullIsValue?: true;
};

const isBoolean = (v: unknown): boolean => typeof v === 'boolean';
const isIntegerAtLeast0 = (v: unknown): boolean =>
  typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
const isPositiveInteger = (v: unknown): boolean =>
  typeof v === 'number' && Number.isSafeInteger(v) && v >= 1;
const isBps = (v: unknown): boolean =>
  isIntegerAtLeast0(v) && (v as number) <= 10_000;
const isCommissionBase = (v: unknown): boolean =>
  v === null || v === 'AMOUNT_PAID' || v === 'AMOUNT_PAID_EXCLUDING_GST';
const isAnything = (): boolean => true;

const RULES: readonly Rule[] = [
  {
    key: COMMISSION_AUTO_APPROVE_KEY,
    field: 'commissionAutoApprove',
    check: isBoolean,
    expected: 'a boolean',
  },
  {
    key: COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
    field: 'commissionRequireVerifiedProfile',
    check: isBoolean,
    expected: 'a boolean',
  },
  {
    key: REFERRAL_CREDIT_WINDOW_DAYS_KEY,
    field: 'referralCreditWindowDays',
    check: isIntegerAtLeast0,
    expected: 'an integer >= 0',
  },
  {
    key: REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
    field: 'referralMemberDiscountBps',
    check: isBps,
    expected: 'an integer from 0 to 10000',
  },
  {
    key: REFERRAL_DISCOUNT_STACKS_WITH_COUPONS_KEY,
    field: 'referralDiscountStacksWithCoupons',
    check: isBoolean,
    expected: 'a boolean',
  },
  {
    key: REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
    field: 'referralDiscountOnlyInCreditWindow',
    check: isBoolean,
    expected: 'a boolean',
  },
  {
    key: PAYOUT_MINIMUM_AMOUNT_PAISE_KEY,
    field: 'payoutMinimumAmountPaise',
    check: isIntegerAtLeast0,
    expected: 'an integer >= 0',
  },
  {
    key: AGENT_CLIENT_DRAFT_LIMIT_KEY,
    field: 'agentClientDraftLimit',
    check: isIntegerAtLeast0,
    expected: 'an integer >= 0',
  },
  {
    key: AGENT_PAYOUT_DETAILS_WAIT_HOURS_KEY,
    field: 'agentPayoutDetailsWaitHours',
    check: isIntegerAtLeast0,
    expected: 'an integer >= 0',
  },
  {
    key: COMMISSION_BASE_KEY,
    field: 'commissionBase',
    check: isCommissionBase,
    expected: "null, 'AMOUNT_PAID' or 'AMOUNT_PAID_EXCLUDING_GST'",
    nullIsValue: true,
  },
  {
    key: COMMISSION_BASE_PROVISIONAL_KEY,
    field: 'commissionBaseProvisional',
    check: isBoolean,
    expected: 'a boolean',
  },
  {
    key: PAYOUT_TAX_WITHHOLDING_KEY,
    field: 'payoutTaxWithholding',
    check: isAnything,
    expected: 'any value',
    nullIsValue: true,
  },
  {
    key: AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
    field: 'accessTokenTtlSeconds',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
  {
    key: AGENT_REFRESH_TOKEN_TTL_SECONDS_KEY,
    field: 'refreshTokenTtlSeconds',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
  {
    key: AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
    field: 'otpResendAfterSeconds',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
  {
    key: REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
    field: 'codeValidationIpLimit',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
  {
    key: REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
    field: 'codeValidationCodeLimit',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
  {
    key: REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
    field: 'codeValidationWindowSeconds',
    check: isPositiveInteger,
    expected: 'an integer >= 1',
  },
];

export const AGENT_PROGRAM_SETTING_KEYS: readonly string[] = RULES.map(
  (rule) => rule.key,
);

export function parseAgentProgramSettings(
  raw: Record<string, unknown>,
): ParsedAgentProgramSettings {
  const settings: Record<string, unknown> = {};
  const missing: string[] = [];

  for (const rule of RULES) {
    const value = Object.prototype.hasOwnProperty.call(raw, rule.key)
      ? raw[rule.key]
      : undefined;
    if (value === undefined || (value === null && !rule.nullIsValue)) {
      missing.push(rule.key);
      continue;
    }
    if (!rule.check(value)) {
      throw new RangeError(`Setting ${rule.key} must be ${rule.expected}.`);
    }
    settings[rule.field] = value;
  }

  return { settings, missing };
}

export interface CommissionPolicyVersionInput {
  calcType: string;
  /** Basis points for PERCENTAGE. */
  value: number;
  holdDays: number;
}

/** Throws a RangeError unless the policy version is acceptable. */
export function validateCommissionPolicyVersion(
  policy: CommissionPolicyVersionInput,
): void {
  if (policy.calcType !== 'PERCENTAGE') {
    throw new RangeError("calcType must be 'PERCENTAGE'.");
  }
  // A percentage can never reach 100%, so 9999 bps is the ceiling.
  if (
    !Number.isSafeInteger(policy.value) ||
    policy.value < 0 ||
    policy.value > 9_999
  ) {
    throw new RangeError('value must be an integer from 0 to 9999.');
  }
  if (!Number.isSafeInteger(policy.holdDays) || policy.holdDays < 0) {
    throw new RangeError('holdDays must be an integer >= 0.');
  }
}
