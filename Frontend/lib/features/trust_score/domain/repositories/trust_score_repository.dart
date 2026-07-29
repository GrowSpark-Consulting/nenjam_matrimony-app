import '../../../profile_detail/domain/entities/trust_score_entity.dart';

/// Pure abstract contract for "my own" trust score.
///
/// No backend endpoint exists for this yet — `trust-score.controller.ts` on
/// the backend is an empty `@Controller()` stub. Deliberately no concrete
/// implementation guesses at a URL and issues a real network call against
/// it; see [TrustScoreRepositoryUnavailable] for what's wired today. A
/// backend engineer can implement this interface for real (e.g. a
/// Dio-backed class calling whatever route the trust-score module
/// eventually exposes) with zero changes to the provider or UI.
abstract interface class TrustScoreRepository {
  Future<TrustScoreEntity> getMyTrustScore();
}
