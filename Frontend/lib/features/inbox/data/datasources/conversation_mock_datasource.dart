import '../../../discover/domain/entities/compatibility_entity.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';

/// In-memory stand-in for a future `GET /chat/conversations` /
/// `GET /chat/messages` call — same role `DiscoverMockDataSource` plays for
/// the Discover feed. `photoUrls` are deliberately left empty (no real
/// photography exists yet), same reasoning as that datasource: a stand-in
/// URL would skip every avatar widget's gender-aware "no photo" placeholder.
///
/// Seeded to cover every state the Inbox UI needs to render at least once:
/// unread badges, online + typing, muted, pinned, archived, blocked, a
/// premium-locked conversation, every [ConversationSmartIndicator] value,
/// and all three read-receipt states.
class ConversationMockDataSource {
  ConversationMockDataSource() {
    _conversations = _seedConversations();
    _messages = _seedMessages();
  }

  late final List<ConversationEntity> _conversations;
  late final Map<String, List<MessageEntity>> _messages;

  Future<List<ConversationEntity>> fetchConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_conversations);
  }

  Future<List<MessageEntity>> fetchMessages(String conversationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return List.unmodifiable(_messages[conversationId] ?? const []);
  }

  static DiscoveryProfileEntity _profile({
    required String id,
    required String matrimonyId,
    required String name,
    required String gender,
    required int age,
    required String location,
    required String profession,
    int aiMatchPercent = 0,
    bool isVerified = false,
    bool isPremium = false,
    bool isOnline = false,
  }) {
    return DiscoveryProfileEntity(
      id: id,
      matrimonyId: matrimonyId,
      name: name,
      gender: gender,
      age: age,
      location: location,
      profession: profession,
      education: '',
      photoUrls: const [],
      isVerified: isVerified,
      isPremium: isPremium,
      isOnline: isOnline,
      compatibility: CompatibilityEntity(
        aiMatchPercent: aiMatchPercent,
        overallCompatibility: aiMatchPercent,
      ),
    );
  }

  List<ConversationEntity> _seedConversations() {
    final now = DateTime.now();

    return [
      ConversationEntity(
        id: 'c1',
        profile: _profile(
          id: 'c1', matrimonyId: 'NM100231', name: 'Priya Sharma', gender: 'Female',
          age: 26, location: 'Chennai', profession: 'Architect',
          aiMatchPercent: 92, isVerified: true, isOnline: true,
        ),
        lastMessage: "Thanks for connecting! I'd love to know more about your family.",
        lastMessageAt: now.subtract(const Duration(minutes: 20)),
        unreadCount: 3,
        isPinned: true,
      ),
      ConversationEntity(
        id: 'c2',
        profile: _profile(
          id: 'c2', matrimonyId: 'NM100232', name: 'Arjun Mehta', gender: 'Male',
          age: 29, location: 'Bengaluru', profession: 'Product Manager',
          aiMatchPercent: 88, isVerified: true, isPremium: true, isOnline: true,
        ),
        lastMessage: "Let's connect this weekend if you're free?",
        lastMessageAt: now.subtract(const Duration(hours: 3)),
        isTyping: true,
        lastMessageFromMe: true,
        lastMessageStatus: MessageDeliveryStatus.delivered,
      ),
      ConversationEntity(
        id: 'c3',
        profile: _profile(
          id: 'c3', matrimonyId: 'NM100233', name: 'Premium Member', gender: '',
          age: 0, location: '', profession: '',
        ),
        lastMessage: 'Unlock Premium to continue chatting.',
        lastMessageAt: now.subtract(const Duration(days: 1)),
        isLocked: true,
      ),
      ConversationEntity(
        id: 'c4',
        profile: _profile(
          id: 'c4', matrimonyId: 'NM100234', name: 'Kavya Iyer', gender: 'Female',
          age: 27, location: 'Coimbatore', profession: 'Doctor',
          aiMatchPercent: 79, isVerified: true,
        ),
        lastMessage: 'Sounds great, talk soon!',
        lastMessageAt: now.subtract(const Duration(hours: 6)),
        lastMessageFromMe: true,
        lastMessageStatus: MessageDeliveryStatus.read,
        isMuted: true,
      ),
      ConversationEntity(
        id: 'c5',
        profile: _profile(
          id: 'c5', matrimonyId: 'NM100235', name: 'Sanjay Rao', gender: 'Male',
          age: 31, location: 'Madurai', profession: 'Civil Engineer',
          aiMatchPercent: 95,
        ),
        lastMessage: 'You matched! Say hi 👋',
        lastMessageAt: now.subtract(const Duration(hours: 9)),
        unreadCount: 1,
        smartIndicator: ConversationSmartIndicator.newMatch,
      ),
      ConversationEntity(
        id: 'c6',
        profile: _profile(
          id: 'c6', matrimonyId: 'NM100236', name: 'Meera Nair', gender: 'Female',
          age: 28, location: 'Trichy', profession: 'Professor',
          aiMatchPercent: 84, isPremium: true,
        ),
        lastMessage: "I accepted your interest! Let's talk.",
        lastMessageAt: now.subtract(const Duration(hours: 14)),
        unreadCount: 1,
        smartIndicator: ConversationSmartIndicator.interestAccepted,
      ),
      ConversationEntity(
        id: 'c7',
        profile: _profile(
          id: 'c7', matrimonyId: 'NM100237', name: 'Divya Krishnan', gender: 'Female',
          age: 30, location: 'Salem', profession: 'Chartered Accountant',
          aiMatchPercent: 60,
        ),
        lastMessage: 'Thank you for considering my profile.',
        lastMessageAt: now.subtract(const Duration(days: 2)),
        smartIndicator: ConversationSmartIndicator.interestDeclined,
        isArchived: true,
      ),
      ConversationEntity(
        id: 'c8',
        profile: _profile(
          id: 'c8', matrimonyId: 'NM100238', name: 'Vignesh Raj', gender: 'Male',
          age: 32, location: 'Erode', profession: 'Software Engineer',
          aiMatchPercent: 71,
        ),
        lastMessage: 'Hi, would love to get to know you better.',
        lastMessageAt: now.subtract(const Duration(days: 1, hours: 3)),
        unreadCount: 1,
        smartIndicator: ConversationSmartIndicator.messageRequest,
      ),
      ConversationEntity(
        id: 'c9',
        profile: _profile(
          id: 'c9', matrimonyId: 'NM100239', name: 'Anitha Suresh', gender: 'Female',
          age: 27, location: 'Chennai', profession: 'Data Scientist',
          aiMatchPercent: 97, isVerified: true, isPremium: true,
        ),
        lastMessage: 'Our AI match score is 97% — worth a look!',
        lastMessageAt: now.subtract(const Duration(days: 3)),
        smartIndicator: ConversationSmartIndicator.aiSuggestedMatch,
      ),
      ConversationEntity(
        id: 'c10',
        profile: _profile(
          id: 'c10', matrimonyId: 'NM100240', name: 'Karthik Babu', gender: 'Male',
          age: 33, location: 'Vellore', profession: 'Sales Manager',
          aiMatchPercent: 55,
        ),
        lastMessage: 'This conversation has been blocked.',
        lastMessageAt: now.subtract(const Duration(days: 5)),
        isBlocked: true,
      ),
      ConversationEntity(
        id: 'c11',
        profile: _profile(
          id: 'c11', matrimonyId: 'NM100241', name: 'Lakshmi Venkat', gender: 'Female',
          age: 29, location: 'Madurai', profession: 'Pharmacist',
          aiMatchPercent: 68, isVerified: true,
        ),
        lastMessage: 'Thank you for the interest! I would love to know more.',
        lastMessageAt: now.subtract(const Duration(days: 28)),
        lastMessageFromMe: true,
        lastMessageStatus: MessageDeliveryStatus.delivered,
      ),
      ConversationEntity(
        id: 'c12',
        profile: _profile(
          id: 'c12', matrimonyId: 'NM100242', name: 'Rohan Das', gender: 'Male',
          age: 30, location: 'Chennai', profession: 'Marketing Lead',
          aiMatchPercent: 73,
        ),
        lastMessage: 'Looking forward to hearing from you.',
        lastMessageAt: now.subtract(const Duration(days: 4)),
        lastMessageFromMe: true,
        lastMessageStatus: MessageDeliveryStatus.sent,
      ),
      ConversationEntity(
        id: 'c13',
        profile: _profile(
          id: 'c13', matrimonyId: 'NM100243', name: 'Deepa Ramesh', gender: 'Female',
          age: 26, location: 'Coimbatore', profession: 'Interior Designer',
          aiMatchPercent: 90, isVerified: true, isOnline: true,
        ),
        lastMessage: 'Can we do a video call sometime this week?',
        lastMessageAt: now.subtract(const Duration(minutes: 2)),
        unreadCount: 5,
      ),
    ];
  }

  Map<String, List<MessageEntity>> _seedMessages() {
    final result = <String, List<MessageEntity>>{};

    for (final conversation in _conversations) {
      if (conversation.isLocked) {
        result[conversation.id] = const [];
        continue;
      }
      final base = conversation.lastMessageAt.subtract(const Duration(hours: 2));
      result[conversation.id] = [
        // c1 alone gets a long back-history so pagination ("scroll up to
        // load older messages") has something real to exercise in the
        // mock — every other conversation keeps a short 5-message thread.
        if (conversation.id == 'c1') ..._olderFillerMessages(conversation.id, base),
        MessageEntity(
          id: '${conversation.id}-m1',
          conversationId: conversation.id,
          text: 'Hi! I really liked your profile, it feels like we have a lot in common.',
          sentAt: base,
          isMine: false,
        ),
        MessageEntity(
          id: '${conversation.id}-m2',
          conversationId: conversation.id,
          text: 'Hi, thank you! I felt the same way when I read yours.',
          sentAt: base.add(const Duration(minutes: 8)),
          isMine: true,
          status: MessageStatus.read,
        ),
        MessageEntity(
          id: '${conversation.id}-m3',
          conversationId: conversation.id,
          text: 'What does a typical weekend look like for you?',
          sentAt: base.add(const Duration(minutes: 15)),
          isMine: false,
        ),
        MessageEntity(
          id: '${conversation.id}-m4',
          conversationId: conversation.id,
          text: 'Mostly time with family, and I try to get some travelling in when I can!',
          sentAt: base.add(const Duration(minutes: 22)),
          isMine: true,
          status: MessageStatus.read,
        ),
        MessageEntity(
          id: '${conversation.id}-m5',
          conversationId: conversation.id,
          text: conversation.lastMessage,
          sentAt: conversation.lastMessageAt,
          isMine: conversation.lastMessageFromMe,
          status: switch (conversation.lastMessageStatus) {
            MessageDeliveryStatus.sent => MessageStatus.sent,
            MessageDeliveryStatus.delivered => MessageStatus.delivered,
            MessageDeliveryStatus.read => MessageStatus.read,
            null => MessageStatus.sent,
          },
        ),
      ];
    }

    return result;
  }

  /// 40 generated messages ending well before [threadStart] — combined with
  /// the 5 messages appended after this, c1's thread totals 45, comfortably
  /// past `getMessages`' default 30-per-page limit, so `MessagesNotifier.
  /// loadOlder()` has a real older page to fetch when testing pagination
  /// instead of always getting everything back on the first load.
  List<MessageEntity> _olderFillerMessages(String conversationId, DateTime threadStart) {
    final start = threadStart.subtract(const Duration(days: 6));
    return List.generate(40, (i) {
      final mine = i.isOdd;
      return MessageEntity(
        id: '$conversationId-older-$i',
        conversationId: conversationId,
        text: mine
            ? 'Just checking in — how has your week been so far?'
            : 'Going well, thanks for asking! Busy with work but no complaints.',
        sentAt: start.add(Duration(hours: i * 3)),
        isMine: mine,
        status: mine ? MessageStatus.read : MessageStatus.sent,
      );
    });
  }
}
