import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/referral_models.dart';
import '../../domain/repositories/referral_repository.dart';

/// Real implementation over the shared [ApiClient].
///
/// **Not live-verified**: the contract is agreed but the backend endpoints
/// are not built yet, so this is never selected by default (see
/// `referralRepositoryProvider`).
///
/// Validate needs no token. The shared client's `AuthInterceptor` adds the
/// Firebase token only when a member is signed in, so a member who has no
/// session yet — every email and mobile signup at this step — sends none.
/// Attach is always made signed in, with that same token.
class ApiReferralRepository implements ReferralRepository {
  ApiReferralRepository(this._apiClient);

  final ApiClient _apiClient;

  static final Options _versioned = Options(
    headers: ApiEndpoints.agentApiVersionHeaders,
  );

  @override
  Future<ReferralCodeValidation> validateCode(String code) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.referralCodeValidate,
      data: {'code': code},
      options: _versioned,
    );
    return ReferralCodeValidation.fromJson(_unwrap(response));
  }

  @override
  Future<ReferralAttachment> attachCode(String code) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.registrationReferralCode,
      data: {'code': code},
      options: _versioned,
    );
    return ReferralAttachment.fromJson(_unwrap(response));
  }

  /// [unwrapOrThrow], plus the contract's `Retry-After` **header** on a 429
  /// (the shared helper only reads a `retryAfterSeconds` body field).
  Map<String, dynamic> _unwrap(Response<Map<String, dynamic>> response) {
    try {
      return unwrapOrThrow(response.statusCode, response.data) ?? const {};
    } on ApiException catch (e) {
      if (e.statusCode != 429 || e.retryAfterSeconds != null) rethrow;
      final seconds = int.tryParse(
        response.headers.value('retry-after')?.trim() ?? '',
      );
      throw ApiException(
        e.statusCode,
        e.message,
        code: e.code,
        retryAfterSeconds: seconds != null && seconds > 0 ? seconds : null,
      );
    }
  }
}
