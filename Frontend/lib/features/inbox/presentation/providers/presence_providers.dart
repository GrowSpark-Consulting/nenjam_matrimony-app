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

  // When each user's presence was last set by a LIVE `chat.presence` event
  // (as opposed to a REST snapshot via [seed]) — lets [seed] tell "this peer
  // was just updated live a moment ago, don't stomp it with a slightly
  // older in-flight REST response" apart from "this entry is just old
  // cached data that a fresh REST read should be allowed to correct". See
  // [seed]'s doc comment for why this replaced the old "never touch again
  // once tracked" rule.
  final Map<String, DateTime> _liveUpdatedAt = {};
  static const _liveGrace = Duration(seconds: 10);

  @override
  Map<String, PresenceState> build() {
    ref.onDispose(() {
      for (final t in _typingTimers.values) {
        t.cancel();
      }
      _typingTimers.clear();
      _liveUpdatedAt.clear();
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
    _liveUpdatedAt[userId] = DateTime.now();
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

  /// Reconciles a peer's presence from a REST snapshot (the conversations
  /// list, refreshed on mount, pull-to-refresh, and every socket reconnect —
  /// see `chatRealtimeSyncProvider`'s `onReady` listener). Always APPLIES the
  /// fresh value, unless a live `chat.presence` event updated this exact
  /// peer within [_liveGrace] — a near-simultaneous in-flight REST response
  /// racing a live event is the one case worth deferring to the live value
  /// for; anything older than that grace window is treated as a
  /// possibly-stale cache entry a fresh read is trusted to correct.
  ///
  /// This replaces an earlier "only seed once, never touch again" rule that
  /// caused a permanent leak: if a `chat.presence: offline` broadcast was
  /// ever missed (e.g. this client's own socket was briefly down when a
  /// peer disconnected), the peer would show "online" for the rest of the
  /// session, since nothing was ever allowed to correct it — not even a
  /// fresh conversations-list fetch confirming they're actually offline.
  /// `isTyping` is preserved from the current cached value — a REST
  /// snapshot carries no typing information.
  void seed(String userId, {required bool isOnline, DateTime? lastSeen}) {
    final liveAt = _liveUpdatedAt[userId];
    if (liveAt != null && DateTime.now().difference(liveAt) < _liveGrace) {
      return;
    }
    _mutate(
      userId,
      (s) => s.copyWith(isOnline: isOnline, lastSeen: lastSeen ?? s.lastSeen),
    );
  }

  /// Wipes the entire cache — called on sign-out, since every entry belongs
  /// to the session that just ended and would otherwise show stale (and
  /// potentially wrong) presence for whoever signs in next on this device,
  /// until each peer happens to get a fresh update.
  void clear() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _liveUpdatedAt.clear();
    state = const {};
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
