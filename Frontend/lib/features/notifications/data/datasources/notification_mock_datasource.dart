import '../../domain/entities/notification_entity.dart';

/// In-memory stand-in for a future `GET /notifications` call — same role
/// `DiscoverMockDataSource`/`ConversationMockDataSource` play for their
/// features. Seeded to cover every state the Notifications UI needs to
/// render at least once: every [NotificationType], read + unread, today/
/// yesterday/older timestamps, an actor with a photo, an actor with no
/// photo (gender-aware placeholder), no actor at all (system/reminder), and
/// one deliberately long title+message to exercise text wrapping.
class NotificationMockDataSource {
  NotificationMockDataSource() {
    _notifications = _seedNotifications();
  }

  late final List<NotificationEntity> _notifications;

  Future<List<NotificationEntity>> fetchNotifications() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_notifications);
  }

  List<NotificationEntity> _seedNotifications() {
    final now = DateTime.now();

    return [
      NotificationEntity(
        id: 'n1',
        type: NotificationType.interestReceived,
        title: 'New interest received',
        message: 'Priya Sharma sent you an interest.',
        createdAt: now.subtract(const Duration(minutes: 2)),
        isRead: false,
        actor: const NotificationActor(
          id: 'u-priya',
          name: 'Priya Sharma',
          photoUrl: '',
        ),
        referenceId: 'interest-1',
      ),
      NotificationEntity(
        id: 'n2',
        type: NotificationType.interestAccepted,
        title: 'Interest accepted',
        message: 'Arjun Mehta accepted your interest. Say hello!',
        createdAt: now.subtract(const Duration(hours: 1)),
        isRead: false,
        actor: const NotificationActor(id: 'u-arjun', name: 'Arjun Mehta'),
        referenceId: 'interest-2',
      ),
      NotificationEntity(
        id: 'n3',
        type: NotificationType.newMatch,
        title: "It's a match!",
        message: 'You and Kavya Iyer both showed interest in each other.',
        createdAt: now.subtract(const Duration(hours: 4)),
        isRead: false,
        actor: const NotificationActor(id: 'u-kavya', name: 'Kavya Iyer'),
        referenceId: 'match-1',
      ),
      NotificationEntity(
        id: 'n4',
        type: NotificationType.messageReceived,
        title: 'New message',
        message: 'Sanjay Rao: "Looking forward to hearing from you soon!"',
        createdAt: now.subtract(const Duration(hours: 8)),
        isRead: true,
        actor: const NotificationActor(id: 'u-sanjay', name: 'Sanjay Rao'),
        referenceId: 'conversation-5',
      ),
      NotificationEntity(
        id: 'n5',
        type: NotificationType.shortlisted,
        title: 'You were shortlisted',
        message: 'Meera Nair added your profile to her shortlist.',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        isRead: true,
        actor: const NotificationActor(id: 'u-meera', name: 'Meera Nair'),
        referenceId: 'shortlist-1',
      ),
      NotificationEntity(
        id: 'n6',
        type: NotificationType.interestDeclined,
        title: 'Interest declined',
        message: 'Divya Krishnan is not interested at this time.',
        createdAt: now.subtract(const Duration(days: 1, hours: 6)),
        isRead: true,
        actor: const NotificationActor(id: 'u-divya', name: 'Divya Krishnan'),
        referenceId: 'interest-3',
      ),
      NotificationEntity(
        id: 'n7',
        type: NotificationType.profileCompletionReminder,
        title: 'Complete your story',
        message:
            'Your profile is 32% complete. Add your education, family and '
            'lifestyle details so better matches can find you — profiles '
            'above 60% complete get significantly more responses.',
        createdAt: now.subtract(const Duration(days: 2)),
        isRead: false,
      ),
      NotificationEntity(
        id: 'n8',
        type: NotificationType.verificationUpdate,
        title: 'Verification approved',
        message: 'Your mobile number has been successfully verified.',
        createdAt: now.subtract(const Duration(days: 3)),
        isRead: true,
      ),
      NotificationEntity(
        id: 'n9',
        type: NotificationType.profileViewed,
        title: 'Someone viewed your profile',
        message: 'Vignesh Raj viewed your profile.',
        createdAt: now.subtract(const Duration(days: 5)),
        isRead: true,
        actor: const NotificationActor(id: 'u-vignesh', name: 'Vignesh Raj'),
        referenceId: 'profile-9',
      ),
      NotificationEntity(
        id: 'n10',
        type: NotificationType.system,
        title: 'Welcome to Nenjam Matrimony',
        message:
            'Thanks for joining! Complete your profile to start discovering '
            'compatible matches curated for you.',
        createdAt: now.subtract(const Duration(days: 9)),
        isRead: true,
      ),
    ];
  }
}
