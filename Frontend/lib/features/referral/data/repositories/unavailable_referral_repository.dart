import '../../domain/models/referral_models.dart';
import '../../domain/repositories/referral_repository.dart';

/// What a non-debug build gets while the referral endpoints are not live:
/// every call is refused. It never answers "valid" or "attached", so a build
/// a real member could install cannot present a mock result as the server's.
class UnavailableReferralRepository implements ReferralRepository {
  const UnavailableReferralRepository();

  @override
  Future<ReferralCodeValidation> validateCode(String code) =>
      Future.error(StateError('Referral endpoints are not live.'));

  @override
  Future<ReferralAttachment> attachCode(String code) =>
      Future.error(StateError('Referral endpoints are not live.'));
}
