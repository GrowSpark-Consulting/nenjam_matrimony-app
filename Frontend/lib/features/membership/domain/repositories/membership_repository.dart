import '../models/checkout_models.dart';
import '../models/membership_models.dart';

/// The membership API (docs/membership/api-contract.md). Every call is
/// scoped to the signed-in member; errors surface as `ApiException`
/// (membership 403s keep `feature`/`limit`/`resetsAt`/`upgradeTo`).
///
/// `POST /membership/subscription/cancel` is deliberately absent: purchases
/// are one-time, so the contract says not to expose it until recurring
/// billing exists.
abstract class MembershipRepository {
  Future<MembershipCatalog> getPlans();

  Future<MyMembership> getMe();

  /// Newest first, at most 50.
  Future<List<MembershipHistoryItem>> getHistory();

  Future<CheckoutSession> startCheckout(CheckoutRequest request);

  Future<CheckoutVerifyResult> verifyCheckout(CheckoutVerifyRequest request);
}
