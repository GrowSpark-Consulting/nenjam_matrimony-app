import '../../../../core/network/api_exception.dart';
import '../../domain/models/referral_models.dart';
import '../../domain/repositories/referral_repository.dart';

/// **MOCK** — stands in for the referral endpoints until the backend builds
/// them. Nothing here talks to a server, and a pass here proves only that
/// the app handles the contract's shapes, not that any backend accepts them.
///
/// Answers follow the contract's examples: [validCode] (`NM7K2P9X`, the
/// contract's example code) belongs to "Ravi K."; every other well-formed
/// code is `valid: false`, and attaching it is `404 CODE_NOT_FOUND`.
class MockReferralRepository implements ReferralRepository {
  const MockReferralRepository();

  static const String validCode = 'NM7K2P9X';
  static const String validAgentDisplayName = 'Ravi K.';

  @override
  Future<ReferralCodeValidation> validateCode(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final valid = code == validCode;
    return ReferralCodeValidation(
      valid: valid,
      agentDisplayName: valid ? validAgentDisplayName : null,
    );
  }

  @override
  Future<ReferralAttachment> attachCode(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (code != validCode) {
      throw ApiException(
        404,
        'Referral code not found.',
        code: 'CODE_NOT_FOUND',
      );
    }
    // Mock window end: today + 60 days (the contract's example
    // `creditWindowDays`). The real value is a server setting.
    final end = DateTime.now().add(const Duration(days: 60));
    return ReferralAttachment(
      attached: true,
      agentDisplayName: validAgentDisplayName,
      windowEndsAt:
          '${end.year.toString().padLeft(4, '0')}-'
          '${end.month.toString().padLeft(2, '0')}-'
          '${end.day.toString().padLeft(2, '0')}',
    );
  }
}
