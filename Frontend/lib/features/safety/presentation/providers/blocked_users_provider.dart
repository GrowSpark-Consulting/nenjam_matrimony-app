import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/blocked_user_entity.dart';
import 'safety_providers.dart';

/// Owns the Blocked Users screen's list — `GET /users/blocked` via the
/// existing [safetyRepositoryProvider] (no parallel repository). Mirrors the
/// same "list notifier + optimistic local removal" shape already used by
/// `ShortlistNotifier`/`ReelFeedNotifier`.
class BlockedUsersNotifier extends AsyncNotifier<List<BlockedUserEntity>> {
  @override
  Future<List<BlockedUserEntity>> build() async {
    final page = await ref.watch(safetyRepositoryProvider).getBlockedUsers();
    return page.items;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(safetyRepositoryProvider).getBlockedUsers();
      return page.items;
    });
  }

  /// Drops [userId] from the loaded list — called after `handleUnblockUser`
  /// has already confirmed the unblock succeeded, so there's nothing to roll
  /// back on failure (there is no failure path left by that point).
  void removeBlockedUser(String userId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.where((b) => b.profile.id != userId).toList(),
    );
  }
}

final blockedUsersNotifierProvider =
    AsyncNotifierProvider<BlockedUsersNotifier, List<BlockedUserEntity>>(
  BlockedUsersNotifier.new,
);
