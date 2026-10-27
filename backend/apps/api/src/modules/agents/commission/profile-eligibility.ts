/**
 * Whether a referred member's profile counts for commission.
 *
 * Pure: the caller reads the `commission.require_verified_profile` setting and
 * passes its raw value in. The default is OFF because there is no KYC yet and
 * profiles are shown without verification.
 */
export const COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY =
  'commission.require_verified_profile';
export const COMMISSION_REQUIRE_VERIFIED_PROFILE_DEFAULT = false;

export interface ProfileEligibilityInput {
  /** Raw setting value. true = required; false/null/undefined = not required. */
  requireVerifiedProfile: unknown;
  profileVerified: boolean | null;
}

export interface ProfileEligibilityResult {
  eligible: boolean;
  reason?: 'AWAITING_VERIFICATION';
}

function isVerificationRequired(setting: unknown): boolean {
  if (setting === true) return true;
  if (setting === false || setting == null) {
    return COMMISSION_REQUIRE_VERIFIED_PROFILE_DEFAULT;
  }
  // A bad setting (e.g. the string "yes") must be noticed, not guessed at.
  throw new RangeError(
    `${COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY} must be true, false or unset.`,
  );
}

export function isProfileEligibleForCommission(
  input: ProfileEligibilityInput,
): ProfileEligibilityResult {
  if (!isVerificationRequired(input.requireVerifiedProfile)) {
    return { eligible: true };
  }
  if (input.profileVerified === true) return { eligible: true };
  return { eligible: false, reason: 'AWAITING_VERIFICATION' };
}
