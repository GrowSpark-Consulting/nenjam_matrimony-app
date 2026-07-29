import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile_detail/domain/entities/trust_score_entity.dart';
import '../../data/repositories/trust_score_repository_unavailable.dart';
import '../../domain/repositories/trust_score_repository.dart';

final trustScoreRepositoryProvider = Provider<TrustScoreRepository>(
  (ref) => const TrustScoreRepositoryUnavailable(),
);

/// The signed-in user's own trust score. See [TrustScoreRepositoryUnavailable]
/// — always resolves to an [AsyncError] today, by design, until a real
/// backend implementation is wired in.
final myTrustScoreProvider = FutureProvider.autoDispose<TrustScoreEntity>((ref) {
  return ref.watch(trustScoreRepositoryProvider).getMyTrustScore();
});
