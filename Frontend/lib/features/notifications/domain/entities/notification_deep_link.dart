/// Every destination a notification tap can resolve to.
///
/// Deliberately separate from [NotificationType] (which is the *display*
/// category driving the notification list's icon/copy): two different
/// backend types can render identically in the list but must open different
/// screens (SUBSCRIPTION_EXPIRING vs SUBSCRIPTION_EXPIRED both render as
/// `system`, yet one opens Premium plans and the other the renewal
/// checkout). Routing therefore keys off the raw wire type, not the
/// collapsed display enum.
enum NotificationDeepLinkKind {
  /// Inbox → the specific conversation with the sender.
  chat,

  /// Inbox → Received Interests tab.
  interestReceived,

  /// Matches → My Matches category.
  interestAccepted,

  /// Inbox → Received Interests tab.
  interestDeclined,

  /// The shortlister's profile, else Shortlisted.
  shortlistAdded,

  /// The viewer's profile, else the Notification Center.
  profileView,

  /// Verification / trust badge screen.
  verificationApproved,

  /// Premium plans.
  subscriptionExpiring,

  /// Premium renewal checkout.
  subscriptionExpired,

  /// Discover.
  dailyRecommendations,

  /// Matches.
  newMatch,

  /// Profile completion.
  profileCompletion,

  /// Catch-all: the Notification Center. Anything the backend sends that
  /// this build doesn't recognise lands here rather than being guessed at.
  notificationCenter,
}

/// What a payload is missing, when it's missing something.
///
/// Reported by [NotificationDeepLink.issue] and acted on by
/// `NotificationNavigationService`, which maps each issue to a fallback
/// screen rather than dropping the tap — a member who taps a notification
/// must always land somewhere sensible, never nowhere.
enum NotificationPayloadIssue {
  /// The `type` field was absent, empty, or names an event this build has no
  /// destination for (a backend newer than the app).
  unknownType,

  /// A chat push with neither `conversationId` nor `senderId` — there is no
  /// way to tell which thread to open.
  missingConversationId,

  /// An interest push with no `interestId`. Diagnostic only: the
  /// destination is a list, so routing still succeeds.
  missingInterestId,

  /// A shortlist/profile-view push with no `userId` — no profile to open.
  missingUserId,
}

/// Maps every wire `type` string this app can receive onto its destination.
///
/// Keys are lower-cased, so both the Prisma enum spelling
/// (`INTEREST_RECEIVED`) and the lower-case push spelling
/// (`interest_received`) resolve to the same entry — the chat push already
/// ships `type: 'chat'` (see backend `MessagesService.send`) while every
/// other push ships the Prisma enum value (see
/// `NotificationsService.dispatchPush`), and both must keep working.
const Map<String, NotificationDeepLinkKind> _kindByWireType = {
  'chat': NotificationDeepLinkKind.chat,
  'new_message': NotificationDeepLinkKind.chat,
  'message_received': NotificationDeepLinkKind.chat,
  'interest_received': NotificationDeepLinkKind.interestReceived,
  'interest_accepted': NotificationDeepLinkKind.interestAccepted,
  'interest_declined': NotificationDeepLinkKind.interestDeclined,
  'interest_rejected': NotificationDeepLinkKind.interestDeclined,
  'shortlist_added': NotificationDeepLinkKind.shortlistAdded,
  'shortlisted': NotificationDeepLinkKind.shortlistAdded,
  'profile_view': NotificationDeepLinkKind.profileView,
  'profile_viewed': NotificationDeepLinkKind.profileView,
  'verification_approved': NotificationDeepLinkKind.verificationApproved,
  'verification_update': NotificationDeepLinkKind.verificationApproved,
  'kyc_approved': NotificationDeepLinkKind.verificationApproved,
  // A rejection opens the same screen — that's where the member sees why and
  // resubmits.
  'kyc_rejected': NotificationDeepLinkKind.verificationApproved,
  'subscription_expiring': NotificationDeepLinkKind.subscriptionExpiring,
  'subscription_renewed': NotificationDeepLinkKind.subscriptionExpiring,
  'subscription_expired': NotificationDeepLinkKind.subscriptionExpired,
  'daily_recommendations': NotificationDeepLinkKind.dailyRecommendations,
  'new_match': NotificationDeepLinkKind.newMatch,
  'profile_completion_reminder': NotificationDeepLinkKind.profileCompletion,
};

/// A notification payload parsed into "which screen, with which argument".
///
/// Built from the FCM `data` map (system-tray tap), the
/// flutter_local_notifications payload (foreground tap — same map, round
/// tripped through JSON), or a [NotificationEntity] (in-app list tap), so
/// all four entry points converge on one value before any navigation
/// happens.
class NotificationDeepLink {
  final NotificationDeepLinkKind kind;
  final String? conversationId;
  final String? senderId;
  final String? interestId;

  /// The other member this notification is about — the shortlister, the
  /// profile viewer, the interest sender.
  final String? userId;

  /// The `type` exactly as it arrived, kept for logging/diagnostics only.
  final String rawType;

  /// Identifies this *delivery* (FCM's own `messageId`), as opposed to
  /// [dedupeKey], which identifies the destination.
  ///
  /// FCM can hand the same launch tap to the app through both
  /// `onMessageOpenedApp` and `getInitialMessage()`; both carry the same
  /// message id, which is the only fully reliable way to recognise them as
  /// one tap. Null for in-app list taps, which have no delivery of their own
  /// and must stay re-tappable.
  final String? deliveryId;

  const NotificationDeepLink({
    required this.kind,
    required this.rawType,
    this.conversationId,
    this.senderId,
    this.interestId,
    this.userId,
    this.deliveryId,
  });

  /// Identity of the *destination*, not of the notification — two pushes
  /// about the same conversation share a key, which is exactly what
  /// duplicate-navigation suppression needs (see
  /// `NotificationNavigationService`).
  String get dedupeKey {
    final argument = conversationId ?? interestId ?? userId ?? '';
    return '${kind.name}:$argument';
  }

  /// What's wrong with this payload, or null when it carries everything its
  /// destination needs.
  ///
  /// Not every issue changes *where* the tap lands. Missing ids whose
  /// destination is a list — an interest id (Received Interests) or a
  /// profile-view's user id (Profile Viewers) — are reported for the debug
  /// log only; that screen never needed the id to open. The ones that do
  /// redirect are [NotificationPayloadIssue.unknownType] and
  /// [NotificationPayloadIssue.missingConversationId], plus
  /// [NotificationPayloadIssue.missingUserId] on a shortlist. See the
  /// fallback table on `NotificationNavigationService`.
  NotificationPayloadIssue? get issue {
    switch (kind) {
      case NotificationDeepLinkKind.notificationCenter:
        return NotificationPayloadIssue.unknownType;
      case NotificationDeepLinkKind.chat:
        // Either id is enough: the conversation can be found by its own id
        // or by who sent the message.
        return conversationId == null && senderId == null
            ? NotificationPayloadIssue.missingConversationId
            : null;
      case NotificationDeepLinkKind.interestReceived:
      case NotificationDeepLinkKind.interestAccepted:
      case NotificationDeepLinkKind.interestDeclined:
        return interestId == null
            ? NotificationPayloadIssue.missingInterestId
            : null;
      case NotificationDeepLinkKind.shortlistAdded:
      case NotificationDeepLinkKind.profileView:
        return userId == null ? NotificationPayloadIssue.missingUserId : null;
      case NotificationDeepLinkKind.verificationApproved:
      case NotificationDeepLinkKind.subscriptionExpiring:
      case NotificationDeepLinkKind.subscriptionExpired:
      case NotificationDeepLinkKind.dailyRecommendations:
      case NotificationDeepLinkKind.newMatch:
      case NotificationDeepLinkKind.profileCompletion:
        // Fixed destinations — nothing to validate.
        return null;
    }
  }

  /// Parses an FCM/local-notification `data` map.
  ///
  /// FCM flattens every data value to a string, so nothing here assumes a
  /// richer type. Each id is read from the field the spec names first, then
  /// from the generic `referenceId`/`actorId` fields the backend's shared
  /// notification pipeline already sends, so a payload works whether or not
  /// it carries the type-specific alias.
  ///
  /// Never throws: a malformed or hostile payload produces a link with
  /// [issue] set, which the navigation service turns into a safe fallback.
  factory NotificationDeepLink.fromData(Map<String, dynamic> data) {
    final rawType = _read(data, const ['type']) ?? '';
    final kind = _kindByWireType[rawType.toLowerCase()] ??
        NotificationDeepLinkKind.notificationCenter;

    return NotificationDeepLink(
      kind: kind,
      rawType: rawType,
      conversationId: _read(data, const ['conversationId', 'referenceId']),
      senderId: _read(data, const ['senderId', 'actorId']),
      interestId: _read(data, const ['interestId', 'referenceId']),
      userId: _read(data, const ['userId', 'actorId']),
      // `google.message_id` is what FCM itself puts in the data map on
      // Android; `deliveryId` is injected by PushNotificationService from
      // `RemoteMessage.messageId` for the cases where it isn't.
      deliveryId: _read(data, const ['deliveryId', 'google.message_id']),
    );
  }

  @override
  String toString() => 'NotificationDeepLink(${kind.name}, raw=$rawType, '
      'conversationId=$conversationId, senderId=$senderId, '
      'interestId=$interestId, userId=$userId, delivery=$deliveryId)';

  /// First non-empty value among [keys], stringified — FCM sends strings,
  /// but an in-app payload assembled from a decoded JSON body may not.
  static String? _read(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
