import 'package:dio/dio.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/agent_referral_link.dart';
import '../../domain/repositories/agent_referral_link_repository.dart';

/// Real `GET /agent/referral-links`. **Not live-verified** — the endpoint is
/// not built yet.
///
/// Takes its own [Dio] rather than the member `ApiClient`: that client's
/// `AuthInterceptor` writes the member's *Firebase* token into
/// `Authorization`, and this endpoint needs the agent's own access token
/// (`agentBearer`). The member app has no agent sign-in, so nothing supplies
/// [agentAccessToken] yet; this is the seam for when one exists. Token
/// refresh (`TOKEN_EXPIRED` → `POST /agent/auth/refresh`) is not handled
/// here.
class ApiAgentReferralLinkRepository implements AgentReferralLinkRepository {
  ApiAgentReferralLinkRepository({
    required Dio dio,
    required Future<String?> Function() agentAccessToken,
  }) : _dio = dio,
       _agentAccessToken = agentAccessToken;

  final Dio _dio;
  final Future<String?> Function() _agentAccessToken;

  @override
  Future<List<AgentReferralLink>> getReferralLinks() async {
    final token = await _agentAccessToken();
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.agentReferralLinks,
      options: Options(
        headers: {
          ...ApiEndpoints.agentApiVersionHeaders,
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? const {};
    final items = data['items'];
    return [
      if (items is List)
        for (final item in items)
          if (item is Map)
            AgentReferralLink.fromJson(Map<String, dynamic>.from(item)),
    ];
  }
}
