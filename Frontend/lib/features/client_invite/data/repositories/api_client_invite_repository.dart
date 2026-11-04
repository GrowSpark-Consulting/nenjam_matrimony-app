import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/client_invite_models.dart';
import '../../domain/repositories/client_invite_repository.dart';

/// Live repository.
///
/// Takes its **own** [ApiClient] (see `clientInviteRepositoryProvider`): the
/// shared client's `AuthInterceptor` would attach a Firebase token and, on a
/// 401, refresh and then sign the member out. The client token is not a
/// Firebase token and has no session to protect, so these calls send exactly
/// the CLIENT bearer and nothing else.
class ApiClientInviteRepository implements ClientInviteRepository {
  ApiClientInviteRepository(this._api);

  final ApiClient _api;

  Options _opts([ClientAccessToken? token]) => Options(
    headers: {
      ...ApiEndpoints.agentApiVersionHeaders,
      if (token != null) 'Authorization': 'Bearer ${token.value}',
    },
  );

  @override
  Future<ClientOtpChallenge> requestOtp(String phoneE164) async {
    final body = await _send(
      () => _api.post<Map<String, dynamic>>(
        ApiEndpoints.clientInviteOtpRequest,
        data: {'phone': phoneE164},
        options: _opts(),
      ),
    );
    return ClientOtpChallenge.fromJson(body ?? const {});
  }

  @override
  Future<ClientAccessToken> verifyOtp(String phoneE164, String code) async {
    final body = await _send(
      () => _api.post<Map<String, dynamic>>(
        ApiEndpoints.clientInviteOtpVerify,
        data: {'phone': phoneE164, 'code': code},
        options: _opts(),
      ),
    );
    final token = body == null ? null : ClientAccessToken.tryFromJson(body);
    if (token == null) throw const ClientInviteNetworkException();
    return token;
  }

  @override
  Future<List<ClientInvite>> list(ClientAccessToken token) async {
    final body = await _send(
      () => _api.get<Map<String, dynamic>>(
        ApiEndpoints.clientInvites,
        options: _opts(token),
      ),
    );
    final items = body?['items'];
    if (items is! List) return const [];
    return items
        .map(ClientInvite.tryFromJson)
        .whereType<ClientInvite>()
        .toList();
  }

  @override
  Future<ClientAcceptResult> accept(ClientAccessToken token, String id) async {
    final body = await _send(
      () => _api.post<Map<String, dynamic>>(
        ApiEndpoints.clientInviteAccept(id),
        options: _opts(token),
      ),
    );
    return ClientAcceptResult.fromJson(body ?? const {});
  }

  @override
  Future<void> reject(ClientAccessToken token, String id) async {
    await _send(
      () => _api.post<Map<String, dynamic>>(
        ApiEndpoints.clientInviteReject(id),
        options: _opts(token),
      ),
    );
  }

  /// Throws `ApiException` for a refusal (4xx, or a 5xx whose body carries a
  /// contract `code` such as `OTP_DELIVERY_UNAVAILABLE`) and
  /// [ClientInviteNetworkException] when there is no usable answer.
  Future<Map<String, dynamic>?> _send(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await call();
    } on DioException catch (e) {
      final r = e.response;
      final data = r?.data;
      if (r != null && data is Map) {
        _throwRefusal(r.statusCode, Map<String, dynamic>.from(data), r.headers);
      }
      throw const ClientInviteNetworkException();
    }
    _throwRefusal(response.statusCode, response.data, response.headers);
    return response.data;
  }

  /// [unwrapOrThrow], plus the `Retry-After` **header** on a 429.
  void _throwRefusal(int? status, Map<String, dynamic>? data, Headers headers) {
    try {
      unwrapOrThrow(status, data);
    } on ApiException catch (e) {
      if (e.statusCode != 429 || e.retryAfterSeconds != null) rethrow;
      final seconds = int.tryParse(headers.value('retry-after')?.trim() ?? '');
      throw ApiException(
        e.statusCode,
        e.message,
        code: e.code,
        retryAfterSeconds: seconds != null && seconds > 0 ? seconds : null,
      );
    }
  }
}
