import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/compatibility_result.dart';
import '../../domain/repositories/compatibility_repository.dart';
import '../../data/repositories/mock_compatibility_repository.dart';

/// Default implementation is the in-memory mock. Override this provider
/// with an `ApiCompatibilityRepository` once the backend team's endpoints
/// are ready — no other code needs to change.
final compatibilityRepositoryProvider = Provider<CompatibilityRepository>(
  (ref) => MockCompatibilityRepository(),
);

/// The signed-in user's own horoscope summary + matching opt-in status.
/// Used by ProfilePage and HoroscopeMatchingPage.
final myHoroscopeSummaryProvider =
    FutureProvider.autoDispose<HoroscopeSummary>((ref) {
  return ref.watch(compatibilityRepositoryProvider).getMyHoroscopeSummary();
});

/// A representative compatibility preview (mock data) shown on the
/// Horoscope Matching page so users can see what a match result looks like.
final compatibilityPreviewProvider =
    FutureProvider.autoDispose<CompatibilityResult>((ref) {
  return ref.watch(compatibilityRepositoryProvider).getCompatibility();
});
