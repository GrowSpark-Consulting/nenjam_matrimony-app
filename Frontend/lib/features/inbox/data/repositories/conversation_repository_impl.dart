import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../datasources/conversation_mock_datasource.dart';

/// Mock-backed implementation — what `conversationRepositoryProvider`
/// actually wires up today. Holds the seeded list in memory as the single
/// source of truth so every write (pin/mute/archive/block/delete/
/// markRead/markUnread/sendMessage) is immediately reflected the next time
/// [getConversations]/[getMessages] is called, the same way a real backend
/// would be — `inbox_providers.dart`'s notifier never needs its own
/// parallel copy of this state.
class ConversationRepositoryImpl implements ConversationRepository {
  ConversationRepositoryImpl(this._dataSource);

  final ConversationMockDataSource _dataSource;

  List<ConversationEntity>? _cache;
  final Map<String, List<MessageEntity>> _messageCache = {};

  Future<List<ConversationEntity>> _load() async {
    return _cache ??= await _dataSource.fetchConversations();
  }

  @override
  Future<ConversationResultPage> getConversations({int page = 1, int limit = 20}) async {
    final all = await _load();
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, all.length);
    final items = start >= all.length ? const <ConversationEntity>[] : all.sublist(start, end);
    return ConversationResultPage(
      items: items,
      page: page,
      limit: limit,
      total: all.length,
      hasMore: end < all.length,
    );
  }

  Future<List<MessageEntity>> _fullThread(String conversationId) async {
    return _messageCache[conversationId] ??=
        await _dataSource.fetchMessages(conversationId);
  }

  @override
  Future<MessagePage> getMessages(String conversationId, {int page = 1, int limit = 30}) async {
    final thread = await _fullThread(conversationId);
    // Oldest-to-newest storage; "page 1" is the newest slice (the tail),
    // increasing page walks backwards toward the start — see MessagePage's
    // doc comment.
    final endExclusive = (thread.length - (page - 1) * limit).clamp(0, thread.length);
    final start = (endExclusive - limit).clamp(0, thread.length);
    return MessagePage(
      items: thread.sublist(start, endExclusive),
      page: page,
      hasMore: start > 0,
    );
  }

  @override
  Future<MessageEntity> sendMessage(
    String conversationId,
    String text, {
    String? clientMessageId,
    MessageType type = MessageType.text,
    String? attachmentUrl,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Mock-only failure simulation, isolated to this in-memory
    // implementation — never present in ConversationApiRepositoryImpl — so
    // the retry UI has a deterministic way to be exercised without relying
    // on random flakiness: send the literal text "fail" (case-insensitive).
    if (type == MessageType.text && text.trim().toLowerCase() == 'fail') {
      throw Exception('Mock send failure (message text was "fail")');
    }
    final message = MessageEntity(
      id: '$conversationId-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      text: text,
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sent,
      type: type,
      // No real upload endpoint exists yet (see chat-backend-handoff.md) —
      // this mock just accepts whatever URL/local path it was given as
      // already "hosted", so the UI can be exercised end-to-end.
      attachmentUrl: attachmentUrl,
      clientMessageId: clientMessageId,
    );
    final thread = await _fullThread(conversationId);
    _messageCache[conversationId] = [...thread, message];
    await _mutate(conversationId, (c) => c.copyWith(
          lastMessage: type == MessageType.text ? text : c.lastMessage,
          lastMessageAt: message.sentAt,
          lastMessageFromMe: true,
          lastMessageStatus: MessageDeliveryStatus.sent,
        ));
    return message;
  }

  @override
  Future<void> setTyping(String conversationId, bool isTyping) async {
    // No-op — see ConversationRepository.setTyping's doc comment.
  }

  @override
  Future<ConversationEntity> getOrCreateConversation(DiscoveryProfileEntity profile) async {
    final all = await _load();
    for (final c in all) {
      if (c.profile.id == profile.id) return c;
    }
    final created = ConversationEntity(
      id: 'room-${profile.id}-${DateTime.now().microsecondsSinceEpoch}',
      profile: profile,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
    );
    _cache = [created, ...all];
    _messageCache[created.id] = const [];
    return created;
  }

  @override
  Future<void> pin(String conversationId, bool pinned) =>
      _mutate(conversationId, (c) => c.copyWith(isPinned: pinned));

  @override
  Future<void> mute(String conversationId, bool muted) =>
      _mutate(conversationId, (c) => c.copyWith(isMuted: muted));

  @override
  Future<void> archive(String conversationId, bool archived) =>
      _mutate(conversationId, (c) => c.copyWith(isArchived: archived));

  @override
  Future<void> block(String conversationId, bool blocked) =>
      _mutate(conversationId, (c) => c.copyWith(isBlocked: blocked));

  @override
  Future<void> delete(String conversationId) async {
    final all = await _load();
    _cache = all.where((c) => c.id != conversationId).toList();
  }

  @override
  Future<void> markRead(String conversationId) =>
      _mutate(conversationId, (c) => c.copyWith(unreadCount: 0));

  @override
  Future<void> markUnread(String conversationId) =>
      _mutate(conversationId, (c) => c.copyWith(unreadCount: c.unreadCount > 0 ? c.unreadCount : 1));

  Future<void> _mutate(
    String conversationId,
    ConversationEntity Function(ConversationEntity) update,
  ) async {
    final all = await _load();
    _cache = [
      for (final c in all) if (c.id == conversationId) update(c) else c,
    ];
  }
}
