import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../data/completion_recommendation_repository.dart';
import 'profile_completeness_provider.dart';

final completionRecommendationRepositoryProvider =
    Provider<CompletionRecommendationRepository>(
      (ref) => CompletionRecommendationRepository(ref.watch(apiClientProvider)),
    );

/// Cards dismissed during this session whose refreshed server response hasn't
/// landed yet.
///
/// The card has to leave the row the instant the cross is tapped — waiting a
/// round trip for it reads as a broken button — but the dismissal itself is
/// only real once the server has it. So the tap adds the key here, the
/// request goes out, and the shared draft provider is invalidated; the
/// refetched response comes back with `isDismissed: true` and this set stops
/// mattering. A failed request removes the key again, and the card returns.
///
/// Deliberately NOT the source of truth for "is this dismissed" — that lives
/// in the database, which is what makes a dismissal survive a restart, a
/// re-login and a reinstall. This set only covers the seconds in between.
class PendingDismissals extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void _add(String cardKey) => state = {...state, cardKey};

  void _remove(String cardKey) =>
      state = state.where((k) => k != cardKey).toSet();

  /// Hides [cardKey] optimistically and persists it. Returns false (and puts
  /// the card back) if the request failed, so the caller can tell the member
  /// rather than silently pretending.
  Future<bool> dismiss(String cardKey) async {
    if (state.contains(cardKey)) return true;
    _add(cardKey);
    try {
      await ref
          .read(completionRecommendationRepositoryProvider)
          .dismiss(cardKey);
    } catch (_) {
      _remove(cardKey);
      return false;
    }
    // Refresh the one response both Home and Edit Profile read, so the card
    // is gone from both — and stays gone — rather than only from the screen
    // that dismissed it.
    for (final provider in profileCompletionProviders) {
      ref.invalidate(provider);
    }
    return true;
  }
}

final pendingDismissalsProvider =
    NotifierProvider<PendingDismissals, Set<String>>(PendingDismissals.new);

/// Everything holding backend completion state — the raw draft response and
/// the shaped snapshot Home, Edit Profile and the Profile dashboard render.
///
/// One list rather than `invalidate` calls scattered through the screens,
/// because forgetting one of them is exactly how the two screens used to
/// drift: a section finished from Home stayed listed on Edit Profile until
/// something else happened to refresh it.
final List<ProviderOrFamily> profileCompletionProviders = [
  profileDraftResponseProvider,
  profileCompletenessSnapshotProvider,
];

/// Re-fetches that state from a widget. The `Ref`-side equivalent is the
/// loop inside [PendingDismissals.dismiss] — `Ref` and `WidgetRef` are
/// unrelated types, so the list above is what the two share, not a function.
void refreshProfileCompletion(WidgetRef ref) {
  for (final provider in profileCompletionProviders) {
    ref.invalidate(provider);
  }
}
