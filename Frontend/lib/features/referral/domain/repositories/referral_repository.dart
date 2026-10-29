import '../models/referral_models.dart';

/// The two member referral endpoints. Failures are thrown as `ApiException`
/// carrying the contract's `code` (and `retryAfterSeconds` on a 429).
abstract class ReferralRepository {
  /// `POST /referrals/codes/validate` — no token needed. [code] must already
  /// be normalised.
  Future<ReferralCodeValidation> validateCode(String code);

  /// `POST /registration/referral-code` — needs the member's Firebase token.
  /// [code] must already be normalised.
  Future<ReferralAttachment> attachCode(String code);
}
