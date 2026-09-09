import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';

/// The dismissal side of the "Complete Your Profile" cards — hiding a
/// suggestion, and nothing else.
///
/// There is no write path here that touches a profile section, by design: the
/// backend stores a dismissal as one row keyed by card id in a table no
/// profile query reads (see `profile_recommendation_dismissals`), so a
/// dismissal cannot lose a member's family, horoscope or verification
/// answers. Both calls return the refreshed completion state; callers
/// generally invalidate the shared draft provider instead of reading it, so
/// Home and Edit Profile pick the change up together.
class CompletionRecommendationRepository {
  CompletionRecommendationRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Hides [cardKey] from Home and Edit Profile, permanently and across
  /// devices, until it is restored. Idempotent on the backend.
  Future<void> dismiss(String cardKey) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.profileCompletionDismissals,
      data: {'cardKey': cardKey},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  /// Brings a dismissed card back, with whatever data the member had already
  /// saved for it still in place.
  Future<void> restore(String cardKey) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.profileCompletionDismissal(cardKey),
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
