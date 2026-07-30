/// A conversation peer's live presence — online flag, whether they're currently
/// typing to this user, and their last-seen time. Held in a `Map<userId,
/// PresenceState>` cache (see `presenceProvider`) that's seeded once from REST
/// and then kept current entirely by `chat.presence` / `chat.typing` socket
/// events (never polled).
///
/// Value equality is defined so Riverpod `select` can skip rebuilding a widget
/// when a peer's presence hasn't actually changed.
class PresenceState {
  final bool isOnline;
  final bool isTyping;
  final DateTime? lastSeen;

  const PresenceState({
    this.isOnline = false,
    this.isTyping = false,
    this.lastSeen,
  });

  PresenceState copyWith({
    bool? isOnline,
    bool? isTyping,
    DateTime? lastSeen,
  }) {
    return PresenceState(
      isOnline: isOnline ?? this.isOnline,
      isTyping: isTyping ?? this.isTyping,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PresenceState &&
      other.isOnline == isOnline &&
      other.isTyping == isTyping &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(isOnline, isTyping, lastSeen);
}
