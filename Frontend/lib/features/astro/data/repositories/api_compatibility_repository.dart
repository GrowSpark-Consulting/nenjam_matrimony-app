import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/compatibility_result.dart';
import '../../domain/repositories/compatibility_repository.dart';

/// Real backend implementation — not wired by default (see
/// `compatibilityRepositoryProvider`). Ready for the backend team to
/// connect by flipping that provider's override once their endpoints are
/// live.
///
/// TODO(backend): GET /astro/profile/me, GET /astro/compatibility/:id — the
/// `astro` controller is currently an empty stub (zero routes), so every
/// call here 404s until that module is built.
class ApiCompatibilityRepository implements CompatibilityRepository {
  ApiCompatibilityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<HoroscopeSummary> getMyHoroscopeSummary() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>(ApiEndpoints.astroProfileMe);
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return HoroscopeSummary(
      rasi: data['rasi'] as String?,
      nakshatra: data['nakshatra'] as String?,
      dosham: data['dosham'] as String?,
      matchingEnabled: data['matchingEnabled'] as bool? ?? true,
    );
  }

  @override
  Future<void> setMatchingEnabled(bool enabled) async {
    // TODO(backend-team): no dedicated opt-in endpoint exists yet for this
    // independent flow (the old registration-coupled draft PATCH was
    // removed from this feature's scope) — wire once available.
  }

  @override
  Future<CompatibilityResult> getCompatibility({String? targetUserId}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      targetUserId != null
          ? ApiEndpoints.astroCompatibility(targetUserId)
          : ApiEndpoints.astroProfileMe,
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final details = data['poruthamDetails'] as Map<String, dynamic>? ?? {};
    final components = details['components'] as Map<String, dynamic>? ?? {};
    return CompatibilityResult(
      score: (data['poruthamScore'] as num?)?.toInt() ?? 0,
      matchLabel: 'Compatibility Result',
      factors: components.entries
          .map((e) => CompatibilityFactor(
                label: e.key,
                score: ((e.value as Map)['score'] as num?)?.toInt() ?? 0,
                maxScore: ((e.value as Map)['maxScore'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
    );
  }
}
