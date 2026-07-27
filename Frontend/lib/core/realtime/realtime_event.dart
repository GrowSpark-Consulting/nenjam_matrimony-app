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
  shortlistCreated('shortlist.created');

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
