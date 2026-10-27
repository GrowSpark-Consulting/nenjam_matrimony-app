import {
  COMMISSION_REQUIRE_VERIFIED_PROFILE_DEFAULT,
  COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY,
  isProfileEligibleForCommission,
} from './profile-eligibility';

const check = (
  requireVerifiedProfile: unknown,
  profileVerified: boolean | null,
) =>
  isProfileEligibleForCommission({ requireVerifiedProfile, profileVerified });

describe('isProfileEligibleForCommission', () => {
  it('exports the setting key and an OFF default', () => {
    expect(COMMISSION_REQUIRE_VERIFIED_PROFILE_KEY).toBe(
      'commission.require_verified_profile',
    );
    expect(COMMISSION_REQUIRE_VERIFIED_PROFILE_DEFAULT).toBe(false);
  });

  describe('verification not required', () => {
    it.each([false, null, undefined])(
      'is eligible whatever profileVerified is (setting %p)',
      (setting) => {
        for (const verified of [true, false, null]) {
          expect(check(setting, verified)).toEqual({ eligible: true });
        }
      },
    );

    it('carries no reason', () => {
      expect(check(false, false)).not.toHaveProperty('reason');
    });
  });

  describe('verification required', () => {
    it('is eligible when the profile is verified', () => {
      expect(check(true, true)).toEqual({ eligible: true });
    });

    it.each([false, null])(
      'is awaiting verification when profileVerified is %p',
      (verified) => {
        expect(check(true, verified)).toEqual({
          eligible: false,
          reason: 'AWAITING_VERIFICATION',
        });
      },
    );
  });

  describe('bad setting values', () => {
    it.each(['yes', 'true', 'false', '', 1, 0, {}, []])(
      'throws RangeError for %p',
      (setting) => {
        expect(() => check(setting, true)).toThrow(RangeError);
      },
    );

    it('names the setting in the error', () => {
      expect(() => check('yes', true)).toThrow(
        /commission\.require_verified_profile/,
      );
    });

    it('throws even when profileVerified would make it eligible', () => {
      expect(() => check('yes', false)).toThrow(RangeError);
      expect(() => check('yes', null)).toThrow(RangeError);
    });
  });
});
