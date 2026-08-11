/// Every notification category the UI knows how to render/route. `system`
/// is the catch-all for anything the backend sends that the frontend
/// doesn't recognise yet — see [NotificationType.fromBackendValue] — so a
/// new backend event type never crashes the list, it just renders generic.
///
/// Not every value here has a matching backend `NotificationType` enum
/// value today (`backend/libs/database/prisma/schema.prisma`'s enum only has
/// INTEREST_RECEIVED/INTEREST_ACCEPTED/INTEREST_DECLINED/NEW_MESSAGE/
/// PROFILE_VIEW/SHORTLIST_ADDED/SUBSCRIPTION_EXPIRING/SUBSCRIPTION_RENEWED/
/// KYC_APPROVED/KYC_REJECTED/SYSTEM) — [profileLiked], [newMatch], and
/// [profileCompletionReminder] are frontend-only categories the mock data
/// source uses so the UI has real coverage for them now; they'll start
/// arriving for real once the backend adds the corresponding event, with no
/// UI change needed.
enum NotificationType {
  interestReceived,
  interestAccepted,
  interestDeclined,
  profileLiked,
  profileViewed,
  shortlisted,
  newMatch,
  messageReceived,
  profileCompletionReminder,
  verificationUpdate,
  system;

  /// Maps a raw backend `NotificationType` enum string (e.g.
  /// `"INTEREST_RECEIVED"`) onto the closest frontend category. Unknown/null
  /// values fall back to [system] rather than throwing, since a partial
  /// backend rollout must never crash the notification list.
  static NotificationType fromBackendValue(String? raw) {
    switch (raw) {
      case 'INTEREST_RECEIVED':
        return NotificationType.interestReceived;
      case 'INTEREST_ACCEPTED':
        return NotificationType.interestAccepted;
      case 'INTEREST_DECLINED':
        return NotificationType.interestDeclined;
      case 'NEW_MESSAGE':
        return NotificationType.messageReceived;
      case 'SHORTLIST_ADDED':
        return NotificationType.shortlisted;
      case 'PROFILE_VIEW':
        return NotificationType.profileViewed;
      case 'KYC_APPROVED':
      case 'KYC_REJECTED':
        return NotificationType.verificationUpdate;
      case 'SUBSCRIPTION_EXPIRING':
      case 'SUBSCRIPTION_RENEWED':
      case 'SYSTEM':
      default:
        return NotificationType.system;
    }
  }
}

/// The person a notification is about (who sent the interest, whose message
/// arrived, etc). Absent for notifications with no single actor — profile
/// completion reminders, verification updates, system notices.
class NotificationActor {
  final String id;
  final String name;
  final String? photoUrl;

  const NotificationActor({
    required this.id,
    required this.name,
    this.photoUrl,
  });
}

/// A single notification, backend-shape-ready — mirrors the proposed
/// `GET /notifications` item payload (`id, type, title, message, isRead,
/// createdAt, actor{id,name,photoUrl}, referenceId, metadata`) so swapping
/// the mock repository for a real one (see
/// `data/repositories/notification_api_repository_impl.dart`) needs no
/// changes here.
class NotificationEntity {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final NotificationActor? actor;

  /// Opaque id of whatever this notification is about (an interest id, a
  /// conversation id, a profile id...) — carried through for future deep
  /// linking; the UI never parses it, only the tap-routing layer would.
  final String? referenceId;

  /// Free-form extra data from the backend, forward-compatible with fields
  /// the UI doesn't know how to use yet.
  final Map<String, dynamic> metadata;

  /// The backend's `type` string exactly as received (e.g.
  /// `"SUBSCRIPTION_EXPIRING"`), before [type] collapsed it into a display
  /// category.
  ///
  /// Tap routing needs the raw value: several distinct backend types map to
  /// the same [NotificationType] for rendering purposes but open different
  /// screens — SUBSCRIPTION_EXPIRING and SUBSCRIPTION_EXPIRED both render as
  /// [NotificationType.system], yet one opens Premium plans and the other
  /// the renewal checkout. Empty only for entities built without a wire
  /// payload.
  final String rawType;

  const NotificationEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.actor,
    this.referenceId,
    this.metadata = const {},
    this.rawType = '',
  });

  /// The payload an in-app list tap hands to
  /// `NotificationNavigationService`, in the same shape a push `data` map
  /// arrives in — so both entry points go through one parser and one
  /// routing switch.
  Map<String, dynamic> toDeepLinkData() => {
        ...metadata,
        'type': rawType.isNotEmpty ? rawType : type.name,
        if (referenceId != null) 'referenceId': referenceId,
        if (actor != null) 'actorId': actor!.id,
      };

  NotificationEntity copyWith({bool? isRead}) {
    return NotificationEntity(
      id: id,
      type: type,
      title: title,
      message: message,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      actor: actor,
      referenceId: referenceId,
      metadata: metadata,
      rawType: rawType,
    );
  }
}
