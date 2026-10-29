import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/checkout_models.dart';
import '../../domain/models/membership_models.dart';
import '../../domain/repositories/membership_repository.dart';

/// Real implementation over the shared authenticated [ApiClient] (Firebase
/// ID token attached by `AuthInterceptor`). 4xx bodies become an
/// [ApiException] through [unwrapOrThrow], which keeps the membership 403
/// details. A 5xx (502 from Razorpay, 503 when payments aren't configured)
/// surfaces as Dio's own exception.
class ApiMembershipRepository implements MembershipRepository {
  ApiMembershipRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<MembershipCatalog> getPlans() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.membershipPlans,
    );
    return MembershipCatalog.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? const {},
    );
  }

  @override
  Future<MyMembership> getMe() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.membershipMe,
    );
    return MyMembership.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? const {},
    );
  }

  @override
  Future<List<MembershipHistoryItem>> getHistory() async {
    // Untyped: the body is a JSON array, and a typed Map request would fail
    // inside Dio before an error body could be read.
    final response = await _apiClient.get<dynamic>(
      ApiEndpoints.membershipHistory,
    );
    final data = unwrapOrThrow<dynamic>(response.statusCode, response.data);
    return [
      if (data is List)
        for (final item in data)
          if (item is Map)
            MembershipHistoryItem.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<CheckoutSession> startCheckout(CheckoutRequest request) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.membershipCheckout,
      data: request.toJson(),
    );
    return CheckoutSession.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? const {},
    );
  }

  @override
  Future<CheckoutVerifyResult> verifyCheckout(
    CheckoutVerifyRequest request,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.membershipCheckoutVerify,
      data: request.toJson(),
    );
    return CheckoutVerifyResult.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? const {},
    );
  }
}
