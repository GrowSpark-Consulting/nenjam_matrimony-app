import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// A contextual hint about *why* this conversation exists / what just
/// happened in it — rendered as a small colored chip on the row. `none` is
/// the common case (an ordinary ongoing conversation).
enum ConversationSmartIndicator {
  none,
  newMatch,
  interestAccepted,
  interestDeclined,
  messageRequest,
  aiSuggestedMatch,
}

/// Delivery state of the *last* message, when it was sent by the current
/// user (read-receipt ticks). Irrelevant (null on the entity) when the last
/// message came from the other person.
enum MessageDeliveryStatus { sent, delivered, read }

/// A single conversation thread shown in the Inbox's Messages tab.
///
/// Embeds [DiscoveryProfileEntity] for everything about the other person
/// (name, age, location, photo, verified/premium/online, compatibility %)
/// instead of redefining those fields — same approach
/// `features/interests`'s `InterestRecord.profile` already takes.
class ConversationEntity {
  final String id;
  final DiscoveryProfileEntity profile;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool isTyping;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isBlocked;
  /// True when this conversation requires a premium subscription to view/
  /// continue — renders as [PremiumConversationCard] instead of the normal
  /// [ConversationCard].
  final bool isLocked;
  final bool lastMessageFromMe;
  /// Only meaningful when [lastMessageFromMe] is true.
  final MessageDeliveryStatus? lastMessageStatus;
  final ConversationSmartIndicator smartIndicator;

  /// The peer's presence at fetch time — used only to seed the live presence
  /// cache (see `presenceProvider`); the UI reads presence from that cache, not
  /// these snapshots, so live socket updates always win.
  final bool isOnline;
  final DateTime? lastSeen;

  const ConversationEntity({
    required this.id,
    required this.profile,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.isTyping = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.isBlocked = false,
    this.isLocked = false,
    this.lastMessageFromMe = false,
    this.lastMessageStatus,
    this.smartIndicator = ConversationSmartIndicator.none,
    this.isOnline = false,
    this.lastSeen,
  });

  ConversationEntity copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isTyping,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    bool? isBlocked,
    bool? isLocked,
    bool? lastMessageFromMe,
    MessageDeliveryStatus? lastMessageStatus,
    ConversationSmartIndicator? smartIndicator,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return ConversationEntity(
      id: id,
      profile: profile,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isTyping: isTyping ?? this.isTyping,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      isBlocked: isBlocked ?? this.isBlocked,
      isLocked: isLocked ?? this.isLocked,
      lastMessageFromMe: lastMessageFromMe ?? this.lastMessageFromMe,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      smartIndicator: smartIndicator ?? this.smartIndicator,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
