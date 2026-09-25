/// Real-time socket events the backend emits (see backend
/// `realtime.events.ts`). Each is a lightweight *refresh signal* — the client
/// re-fetches the affected data through the normal authenticated REST
/// endpoints, so handling is naturally idempotent (a duplicate event, a
/// reconnect replay, or a push+socket race just triggers another safe re-fetch).
enum RealtimeEvent {
  interestCreated('interest.created'),
  interestAccepted('interest.accepted'),
  interestRejected('interest.rejected'),
  notificationCreated('notification.created'),
  shortlistCreated('shortlist.created'),

  /// The caller's Discover feed may no longer be accurate — their profile,
  /// partner preferences or psychology quiz answers changed, or a block was
  /// created/removed (see
  /// backend `FeedInvalidationService`/`FeedInvalidationReason`). Payload is
  /// `{ version: number, reason: string, at: string }` — deliberately not
  /// modeled here, same as every other [RealtimeEvent]: this is a refresh
  /// signal, not a delivery of feed content, so the client just re-fetches
  /// through the normal `GET /discover`/`GET /discover/search` endpoints.
  feedInvalidate('feed.invalidate');

  const RealtimeEvent(this.wireName);

  /// The exact string the backend emits.
  final String wireName;

  /// All wire names, for registering socket listeners.
  static List<String> get wireNames =>
      RealtimeEvent.values.map((e) => e.wireName).toList();

  static RealtimeEvent? fromWire(String name) {
    for (final e in RealtimeEvent.values) {
      if (e.wireName == name) return e;
    }
    return null;
  }
}

/// Chat socket events — unlike [RealtimeEvent]'s refresh signals, these carry a
/// full payload the client applies directly (a chat has to feel instant, so the
/// message renders with no REST round-trip). Delivered only to the affected
/// conversation's authenticated participants, so nothing private leaks. See the
/// backend `realtime.events.ts` `chat*` names.
enum ChatRealtimeEvent {
  /// A new message (full [MessageEntity] payload, per-viewer `isMine`).
  message('chat.message'),

  /// The peer read this user's messages in a room — `{ id: roomId, at }`.
  read('chat.read'),

  /// A message this user sent was delivered — `{ id, roomId, at }`.
  delivered('chat.delivered'),

  /// The peer's typing state changed — `{ roomId, isTyping }`.
  typing('chat.typing'),

  /// A message's text was edited (full updated [MessageEntity] payload).
  messageEdited('chat.messageEdited'),

  /// A message was deleted for everyone — `{ id, roomId, at }`.
  messageDeleted('chat.messageDeleted'),

  /// A conversation peer came online / went offline —
  /// `{ userId, isOnline, lastSeenAt }` (`lastSeenAt` ISO string or null).
  presence('chat.presence');

  const ChatRealtimeEvent(this.wireName);

  final String wireName;

  static List<String> get wireNames =>
      ChatRealtimeEvent.values.map((e) => e.wireName).toList();

  static ChatRealtimeEvent? fromWire(String name) {
    for (final e in ChatRealtimeEvent.values) {
      if (e.wireName == name) return e;
    }
    return null;
  }
}

/// One inbound chat socket event: which [ChatRealtimeEvent] and its raw payload
/// map (the Riverpod bridge decodes it — see `chat_realtime_sync.dart`).
class ChatRealtimePayload {
  const ChatRealtimePayload(this.event, this.data);

  final ChatRealtimeEvent event;
  final Map<String, dynamic> data;
}

/// Outbound chat socket event names the client emits to the server.
class ChatClientEvent {
  const ChatClientEvent._();

  /// Reconnect replay — the server re-delivers messages missed while offline.
  static const String sync = 'chat.sync';

  /// This client's typing state for a room — `{ roomId, isTyping }`.
  static const String typing = 'chat.typing';

  /// Presence heartbeat, so an idle-but-connected device stays "online".
  static const String presencePing = 'presence.ping';

  /// Sent when the app backgrounds — marks this user offline immediately (with
  /// a last-seen) rather than waiting for the socket to drop or age out.
  static const String presenceOffline = 'presence.offline';

  /// This device now has a conversation on screen — `{ conversationId }`. The
  /// server suppresses chat pushes for exactly that thread while it is open,
  /// since the member is already watching the message arrive.
  ///
  /// Being online is deliberately NOT enough: sitting in another conversation,
  /// or anywhere else in the app, still gets the push.
  static const String chatViewing = 'chat.viewing';

  /// This device left the chat screen — pushes for that thread resume.
  static const String chatStopViewing = 'chat.stopViewing';

  /// Explicit delivery acknowledgment — emitted the moment this client
  /// actually processes a live `chat.message` push addressed to it (see
  /// `chat_realtime_sync.dart`). `{ messageId }`. The authoritative
  /// "delivered" signal, correcting the one gap the server's presence-based
  /// guess at send time can't cover on its own — see the backend
  /// `ChatGateway.handleDeliveredAck`'s doc comment.
  static const String deliveredAck = 'chat.delivered.ack';
}
