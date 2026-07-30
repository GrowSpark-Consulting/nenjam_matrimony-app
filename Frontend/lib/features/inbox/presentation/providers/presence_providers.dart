import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/presence_state.dart';

/// The single live presence cache — `peerUserId → PresenceState`. Seeded once
/// from the conversation REST payloads (see `chatRealtimeSyncProvider`) and then
/// kept current purely by `chat.presence` / `chat.typing` socket events. UI
/// reads a single peer with
/// `ref.watch(presenceProvider.select((m) => m[userId]))`, so only the presence
/// widgets rebuild — never the whole chat page — and only when that peer's
/// state actually changes (PresenceState has value equality).
class PresenceNotifier extends Notifier<Map<String, PresenceState>> {
  // Safety timers so a "typing" state can never stick if the matching stop event
  // is lost (dropped socket, killed sender). Keyed by userId.
  final Map<String, Timer> _typingTimers = {};
  static const _typingTtl = Duration(seconds: 6);

  @override
  Map<String, PresenceState> build() {
    ref.onDispose(() {
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
    });
    return const {};
  }

  /// Live online/offline transition from a `chat.presence` event. Coming online
  /// clears any stale typing (a peer can't be typing while offline).
  void applyPresence(
    String userId, {
    required bool isOnline,
    DateTime? lastSeen,
  }) {
    if (!isOnline) _clearTypingTimer(userId);
    _mutate(
      userId,
      (s) => s.copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen ?? s.lastSeen,
        isTyping: isOnline ? s.isTyping : false,
      ),
    );
  }

  /// Live typing transition from a `chat.typing` event. A `true` also arms a TTL
  /// that auto-clears typing if no stop arrives — so it can never get stuck.
  void setTyping(String userId, bool isTyping) {
    _clearTypingTimer(userId);
    if (isTyping) {
      _typingTimers[userId] = Timer(_typingTtl, () {
        _typingTimers.remove(userId);
        _mutate(userId, (s) => s.copyWith(isTyping: false));
      });
    }
    _mutate(userId, (s) => s.copyWith(isTyping: isTyping));
  }

  void _clearTypingTimer(String userId) {
    _typingTimers.remove(userId)?.cancel();
  }

  /// Seeds a peer's presence from a REST snapshot — only when we're not already
  /// tracking them, so a fresher socket update is never clobbered by a
  /// later-arriving initial fetch.
  void seed(String userId, {required bool isOnline, DateTime? lastSeen}) {
    if (state.containsKey(userId)) return;
    state = {
      ...state,
      userId: PresenceState(isOnline: isOnline, lastSeen: lastSeen),
    };
  }

  void _mutate(
    String userId,
    PresenceState Function(PresenceState current) update,
  ) {
    final current = state[userId] ?? const PresenceState();
    final next = update(current);
    if (next == current) return; // value equality → no needless rebuilds
    state = {...state, userId: next};
  }
}

final presenceProvider =
    NotifierProvider<PresenceNotifier, Map<String, PresenceState>>(
  PresenceNotifier.new,
);

/// A single peer's live presence — a family selector that only rebuilds its
/// watchers when *that* peer's [PresenceState] changes (value equality on the
/// selected slice). Returns null until the peer is tracked.
final peerPresenceProvider =
    Provider.family<PresenceState?, String>((ref, userId) {
  return ref.watch(presenceProvider.select((m) => m[userId]));
});
