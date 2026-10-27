/**
 * Whether an agent can be paid out now, and every reason they cannot.
 *
 * Pure: the caller supplies the facts and the settings (`waitHours`,
 * `minimumPaise`). Nothing here is a business default.
 */

export type PayoutIneligibleReason =
  | 'AGENT_NOT_PAYABLE'
  | 'PAN_NOT_VERIFIED'
  | 'DETAILS_NOT_VERIFIED'
  | 'WAIT_NOT_OVER'
  | 'NOTHING_TO_PAY'
  | 'BELOW_MINIMUM'
  | 'PAYOUT_EXISTS';

export interface PayoutEligibilityInput {
  agentStatus: string;
  panVerified: boolean;
  payoutDetailsVerified: boolean;
  /** When the payout details were last changed; null if never. */
  payoutDetailsChangedAt: Date | null;
  waitHours: number;
  now: Date;
  balancePaise: number;
  minimumPaise: number;
  /** A payout already exists for this period. */
  hasPayoutForPeriod: boolean;
}

export interface PayoutEligibility {
  eligible: boolean;
  /** Every failing reason, in a fixed order. Empty when eligible. */
  reasons: PayoutIneligibleReason[];
}

const MS_PER_HOUR = 60 * 60 * 1000;

// Only an ACTIVE agent, or a TERMINATED one still owed their approved balance,
// can be paid. A SUSPENDED agent cannot, nor can an applicant.
const PAYABLE_AGENT_STATUSES: ReadonlySet<string> = new Set([
  'ACTIVE',
  'TERMINATED',
]);

function assertNonNegativeInteger(name: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative integer.`);
  }
}

export function decidePayoutEligibility(
  input: PayoutEligibilityInput,
): PayoutEligibility {
  assertNonNegativeInteger('waitHours', input.waitHours);
  assertNonNegativeInteger('balancePaise', input.balancePaise);
  assertNonNegativeInteger('minimumPaise', input.minimumPaise);
  if (Number.isNaN(input.now.getTime())) {
    throw new RangeError('now must be a valid date.');
  }
  if (
    input.payoutDetailsChangedAt !== null &&
    Number.isNaN(input.payoutDetailsChangedAt.getTime())
  ) {
    throw new RangeError('payoutDetailsChangedAt must be a valid date.');
  }

  const reasons: PayoutIneligibleReason[] = [];

  if (!PAYABLE_AGENT_STATUSES.has(input.agentStatus)) {
    reasons.push('AGENT_NOT_PAYABLE');
  }
  if (!input.panVerified) reasons.push('PAN_NOT_VERIFIED');
  if (!input.payoutDetailsVerified) reasons.push('DETAILS_NOT_VERIFIED');
  if (
    input.payoutDetailsChangedAt !== null &&
    input.now.getTime() <
      input.payoutDetailsChangedAt.getTime() + input.waitHours * MS_PER_HOUR
  ) {
    reasons.push('WAIT_NOT_OVER');
  }
  // A zero balance is never payable, even when the minimum is set to 0.
  if (input.balancePaise <= 0) reasons.push('NOTHING_TO_PAY');
  if (input.balancePaise < input.minimumPaise) reasons.push('BELOW_MINIMUM');
  if (input.hasPayoutForPeriod) reasons.push('PAYOUT_EXISTS');

  return { eligible: reasons.length === 0, reasons };
}
