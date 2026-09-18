import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../data/repositories/partner_preferences_repository_impl.dart';
import '../../domain/repositories/partner_preferences_repository.dart';

/// Real backend, over `GET`/`PUT /discover/preferences` — see
/// [PartnerPreferencesRepository] for exactly which fields this covers.
final partnerPreferencesRepositoryProvider =
    Provider<PartnerPreferencesRepository>(
  (ref) => PartnerPreferencesRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Loads the caller's saved base preference fields (`build()` -> `GET`) and
/// performs saves (`save()` -> `PUT`).
///
/// This notifier is deliberately NOT where in-progress edits live —
/// [PartnerPreferencesPage] keeps its own local `_draft` (`extended` included)
/// and seeds it from this provider's value exactly once per page visit, so a
/// background refresh of this provider (or any other rebuild) can never wipe
/// out unsaved changes the user is mid-way through. `.autoDispose` because
/// this state is scoped to one visit to the page — reopening it later
/// re-fetches, which is the freshness this screen wants, not a wasted
/// request.
class PartnerPreferencesNotifier
    extends AutoDisposeAsyncNotifier<PartnerPreference> {
  bool _saving = false;

  @override
  Future<PartnerPreference> build() {
    return ref.watch(partnerPreferencesRepositoryProvider).getPreferences();
  }

  /// Re-fetches from page 1 — the retry action for a failed initial load.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(partnerPreferencesRepositoryProvider).getPreferences(),
    );
  }

  /// `PUT /discover/preferences` with [preferences]'s base fields. No-ops
  /// while a save is already in flight — the page's own `_saving` flag
  /// covers the UI (disabling the button), this is the belt-and-braces
  /// guard against a second call actually reaching the network (e.g. a
  /// double-tap that lands before the first `setState` rebuild disables the
  /// button). Rethrows on failure so the page can show its own error
  /// snackbar; this provider's state is left at its last-known-good value
  /// rather than switched to `AsyncError`, so the page doesn't flash into an
  /// error/retry screen over a save failure it's already reporting itself.
  Future<PartnerPreference> save(PartnerPreference preferences) async {
    if (_saving) return state.requireValue;
    _saving = true;
    try {
      final updated = await ref
          .read(partnerPreferencesRepositoryProvider)
          .updatePreferences(preferences);
      state = AsyncData(updated);
      return updated;
    } finally {
      _saving = false;
    }
  }
}

final partnerPreferencesProvider = AutoDisposeAsyncNotifierProvider<
    PartnerPreferencesNotifier, PartnerPreference>(
  PartnerPreferencesNotifier.new,
);
