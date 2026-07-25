import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/repositories/mock_shortlist_repository.dart';
import '../../domain/repositories/shortlist_repository.dart';

/// Swap point for a real backend: replace with
/// `ShortlistRepositoryImpl(ref.watch(apiClientProvider))` once the
/// backend's `matches`/shortlist routes ship (see that class's doc comment
/// for the proposed wire shape) — nothing else in this file needs to change.
final shortlistRepositoryProvider = Provider<ShortlistRepository>(
  (ref) => MockShortlistRepository(),
);

/// Single source of truth for shortlist state across the whole app —
/// Discover, Matches, Profile Detail, Search, the Shortlisted Profiles
/// screen, and the Profile Drawer's count badge all read from and mutate
/// through this one notifier, so no screen can disagree with another about
/// which profiles are shortlisted.
class ShortlistNotifier extends AsyncNotifier<List<DiscoveryProfileEntity>> {
  @override
  Future<List<DiscoveryProfileEntity>> build() {
    return ref.watch(shortlistRepositoryProvider).getShortlisted();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(shortlistRepositoryProvider).getShortlisted(),
    );
  }

  /// Adds [profile]. No-ops if it's already shortlisted — this is what
  /// makes rapid repeated taps and multiple call sites (a Discover card,
  /// then the same profile's Matches card) collapse into at most one real
  /// add, the optimistic update below being applied synchronously so a
  /// second tap sees the already-updated state before its own guard check.
  Future<void> shortlist(DiscoveryProfileEntity profile) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.any((p) => p.id == profile.id)) return;

    state = AsyncValue.data([...current, profile]);
    try {
      await ref.read(shortlistRepositoryProvider).add(profile);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.where((p) => p.id != profile.id).toList());
      }
      rethrow;
    }
  }

  /// Removes the profile with [profileId]. No-ops if it isn't currently
  /// shortlisted (already-in-flight rapid taps guard the same way).
  Future<void> removeFromShortlist(String profileId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final removedProfile = current.where((p) => p.id == profileId);
    if (removedProfile.isEmpty) return;
    final removed = removedProfile.first;

    state = AsyncValue.data(current.where((p) => p.id != profileId).toList());
    try {
      await ref.read(shortlistRepositoryProvider).remove(profileId);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([...latest, removed]);
      }
      rethrow;
    }
  }

  /// Convenience for a single button that both adds and removes depending
  /// on current membership — every live shortlist/bookmark button in the
  /// app calls this rather than deciding add-vs-remove itself.
  Future<void> toggleShortlist(DiscoveryProfileEntity profile) {
    final isShortlisted = state.valueOrNull?.any((p) => p.id == profile.id) ?? false;
    return isShortlisted ? removeFromShortlist(profile.id) : shortlist(profile);
  }
}

final shortlistNotifierProvider =
    AsyncNotifierProvider<ShortlistNotifier, List<DiscoveryProfileEntity>>(
  ShortlistNotifier.new,
);

/// Whether [profileId] is currently shortlisted — the one read every
/// shortlist/bookmark button across the app watches.
final isShortlistedProvider = Provider.family<bool, String>((ref, profileId) {
  final list = ref.watch(shortlistNotifierProvider).valueOrNull;
  return list?.any((p) => p.id == profileId) ?? false;
});

/// Shortlisted count for the Profile Drawer badge.
final shortlistCountProvider = Provider<int>((ref) {
  return ref.watch(shortlistNotifierProvider).valueOrNull?.length ?? 0;
});
