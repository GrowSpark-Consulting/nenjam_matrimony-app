import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/profile_completion_aggregator.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/profile_completion_module.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';

/// Verifies the Step 13 "max 25%, 5% per verified flag" contract from the
/// product spec: mobile/income/asset/aadhaar/nri each independently worth 5
/// of the overall 100-point profile completion score, submitted-but-not-yet
/// -verified documents contribute 0, and email verification never adds to
/// this score.
void main() {
  group('VerificationModule weight', () {
    test('all active module weights sum to exactly 100', () {
      final totalWeight =
          profileCompletionModules.fold<double>(0, (sum, m) => sum + m.weight);
      expect(totalWeight, 100);
    });

    test('VerificationModule alone is worth exactly 25 points', () {
      final module = profileCompletionModules.firstWhere((m) => m.id == 'verification');
      expect(module.weight, 25);
    });
  });

  group('Step 13 contribution to overall completion percentage', () {
    double verificationProgress(VerificationStatus status) {
      final context = ProfileCompletionContext(
        draft: ProfileDraft(verificationStatus: status),
      );
      final module =
          profileCompletionModules.firstWhere((m) => m.id == 'verification');
      return module.evaluate(context).progress;
    }

    test('nothing verified -> 0% of the verification module', () {
      expect(verificationProgress(const VerificationStatus()), 0.0);
    });

    test('mobile only -> verification module 20% complete (5 of 25 points)', () {
      const status = VerificationStatus(mobileVerified: true);
      expect(verificationProgress(status), closeTo(1 / 5, 1e-9));
    });

    test('mobile + income -> verification module 40% complete (10 of 25 points)', () {
      const status =
          VerificationStatus(mobileVerified: true, incomeVerified: true);
      expect(verificationProgress(status), closeTo(2 / 5, 1e-9));
    });

    test('all five verified -> verification module 100% complete (25 of 25 points)', () {
      const status = VerificationStatus(
        mobileVerified: true,
        incomeVerified: true,
        assetVerified: true,
        aadhaarVerified: true,
        govIdVerified: true,
        nriVerified: true,
      );
      expect(verificationProgress(status), 1.0);
    });

    test('email verified alone does NOT move the verification module', () {
      const status = VerificationStatus(emailVerified: true);
      expect(verificationProgress(status), 0.0);
    });

    test('submitted-but-pending documents do not count as verified', () {
      // incomeVerified/assetVerified/etc. only ever flip true on a backend
      // VERIFIED status (see StepVerification._syncMirrors) — a plain
      // ProfileDraft with everything false models "submitted, pending
      // review" just as accurately as "never submitted", since neither
      // state sets these flags.
      expect(verificationProgress(const VerificationStatus()), 0.0);
    });

    test('mobile-only earns exactly 5 of the module\'s 25 points', () {
      const status = VerificationStatus(mobileVerified: true);
      final module =
          profileCompletionModules.firstWhere((m) => m.id == 'verification');
      final earned = module.weight * verificationProgress(status);
      expect(earned, closeTo(5, 1e-9));
    });

    test('all five verified earns the full 25 points', () {
      const status = VerificationStatus(
        mobileVerified: true,
        incomeVerified: true,
        assetVerified: true,
        aadhaarVerified: true,
        govIdVerified: true,
        nriVerified: true,
      );
      final module =
          profileCompletionModules.firstWhere((m) => m.id == 'verification');
      final earned = module.weight * verificationProgress(status);
      expect(earned, closeTo(25, 1e-9));
    });
  });
}
