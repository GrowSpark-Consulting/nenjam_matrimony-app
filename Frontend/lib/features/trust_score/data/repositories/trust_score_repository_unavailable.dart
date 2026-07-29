import '../../../profile_detail/domain/entities/trust_score_entity.dart';
import '../../domain/repositories/trust_score_repository.dart';

/// TODO(backend): swap this for a real Dio-backed implementation once the
/// trust-score module ships an endpoint. Throws immediately rather than
/// guessing at a URL and making a real network call against a contract
/// nobody has defined yet — the provider surfaces this as a normal
/// [AsyncError], so the UI's "not available yet" + retry state is honest,
/// not a fake empty/zero score.
class TrustScoreRepositoryUnavailable implements TrustScoreRepository {
  const TrustScoreRepositoryUnavailable();

  @override
  Future<TrustScoreEntity> getMyTrustScore() {
    throw StateError('Trust score is not available yet.');
  }
}
