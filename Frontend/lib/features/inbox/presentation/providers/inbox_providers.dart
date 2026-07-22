import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/conversation_mock_datasource.dart';
import '../../data/repositories/conversation_repository_impl.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';

final conversationMockDataSourceProvider = Provider<ConversationMockDataSource>(
  (ref) => ConversationMockDataSource(),
);

/// Swap point for a real backend: replace with
/// `ConversationApiRepositoryImpl(ref.watch(apiClientProvider))` once the
/// `chat` controller ships (see that class's doc comment for the proposed
/// wire shapes).
final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => ConversationRepositoryImpl(ref.watch(conversationMockDataSourceProvider)),
);

/// The three Inbox tabs, left to right.
enum InboxTab { interestsReceived, interestsSent, messages }

final inboxTabProvider = StateProvider<InboxTab>((ref) => InboxTab.messages);

final inboxSearchQueryProvider = StateProvider<String>((ref) => '');

/// Filter Bottom Sheet options — applied as an AND across whatever's
/// selected. `archived`/`blocked` are also visibility gates: conversations
/// in either state are hidden from the default list unless their filter is
/// explicitly turned on (standard inbox behavior).
enum InboxFilter { unread, online, verified, premium, recent, archived, blocked }

final inboxFilterProvider = StateProvider<Set<InboxFilter>>((ref) => {});

/// Owns the conversations list — every mutation (swipe action, long-press
/// option, Chat Detail's composer) goes through this notifier so the
/// in-memory repository and the UI never disagree about current state.
class ConversationsNotifier extends AsyncNotifier<List<ConversationEntity>> {
  @override
  Future<List<ConversationEntity>> build() async {
    final page = await ref.watch(conversationRepositoryProvider).getConversations();
    return page.items;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref.read(conversationRepositoryProvider).getConversations();
      return page.items;
    });
  }

  Future<void> _apply(
    String id,
    ConversationEntity Function(ConversationEntity) optimisticUpdate,
    Future<void> Function(ConversationRepository repo) persist,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current) if (c.id == id) optimisticUpdate(c) else c,
    ]);
    await persist(ref.read(conversationRepositoryProvider));
  }

  Future<void> pin(String id, bool pinned) => _apply(
        id,
        (c) => c.copyWith(isPinned: pinned),
        (repo) => repo.pin(id, pinned),
      );

  Future<void> mute(String id, bool muted) => _apply(
        id,
        (c) => c.copyWith(isMuted: muted),
        (repo) => repo.mute(id, muted),
      );

  Future<void> archive(String id, bool archived) => _apply(
        id,
        (c) => c.copyWith(isArchived: archived),
        (repo) => repo.archive(id, archived),
      );

  Future<void> block(String id, bool blocked) => _apply(
        id,
        (c) => c.copyWith(isBlocked: blocked),
        (repo) => repo.block(id, blocked),
      );

  Future<void> markRead(String id) => _apply(
        id,
        (c) => c.copyWith(unreadCount: 0),
        (repo) => repo.markRead(id),
      );

  Future<void> markUnread(String id) => _apply(
        id,
        (c) => c.copyWith(unreadCount: c.unreadCount > 0 ? c.unreadCount : 1),
        (repo) => repo.markUnread(id),
      );

  Future<void> delete(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.where((c) => c.id != id).toList());
    await ref.read(conversationRepositoryProvider).delete(id);
  }

  /// Called after `messagesProvider(id).send(...)` — keeps this list's
  /// "last message" preview in sync without a second network round-trip.
  void applyLastMessage(String id, MessageEntity message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == id)
          c.copyWith(
            lastMessage: message.text,
            lastMessageAt: message.sentAt,
            lastMessageFromMe: true,
            lastMessageStatus: MessageDeliveryStatus.sent,
          )
        else
          c,
    ]);
  }
}

final conversationsNotifierProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationEntity>>(
  ConversationsNotifier.new,
);

/// Search + filter + pinned-first sort applied to the raw conversations
/// list — same "derive, don't duplicate" style as
/// `discover_providers.dart`'s `discoverProfilesProvider`.
final filteredConversationsProvider = Provider<AsyncValue<List<ConversationEntity>>>((ref) {
  final query = ref.watch(inboxSearchQueryProvider).trim().toLowerCase();
  final filters = ref.watch(inboxFilterProvider);
  final conversationsAsync = ref.watch(conversationsNotifierProvider);

  return conversationsAsync.whenData((all) {
    final showArchived = filters.contains(InboxFilter.archived);
    final showBlocked = filters.contains(InboxFilter.blocked);

    var result = all.where((c) {
      if (c.isArchived && !showArchived) return false;
      if (c.isBlocked && !showBlocked) return false;
      if (showArchived && !c.isArchived) return false;
      if (showBlocked && !c.isBlocked) return false;
      return true;
    });

    if (filters.contains(InboxFilter.unread)) {
      result = result.where((c) => c.unreadCount > 0);
    }
    if (filters.contains(InboxFilter.online)) {
      result = result.where((c) => c.profile.isOnline);
    }
    if (filters.contains(InboxFilter.verified)) {
      result = result.where((c) => c.profile.isVerified);
    }
    if (filters.contains(InboxFilter.premium)) {
      result = result.where((c) => c.profile.isPremium);
    }
    if (filters.contains(InboxFilter.recent)) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      result = result.where((c) => c.lastMessageAt.isAfter(cutoff));
    }

    if (query.isNotEmpty) {
      result = result.where((c) =>
          c.profile.name.toLowerCase().contains(query) ||
          c.profile.matrimonyId.toLowerCase().contains(query) ||
          c.lastMessage.toLowerCase().contains(query));
    }

    final list = result.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
    return list;
  });
});

/// Unread conversation count for the Messages tab's badge.
final unreadConversationsCountProvider = Provider<int>((ref) {
  final all = ref.watch(conversationsNotifierProvider).valueOrNull ?? const [];
  return all.where((c) => !c.isArchived && !c.isBlocked && c.unreadCount > 0).length;
});

/// One thread's messages, keyed by conversation id — drives Chat Detail.
class MessagesNotifier extends FamilyAsyncNotifier<List<MessageEntity>, String> {
  @override
  Future<List<MessageEntity>> build(String conversationId) {
    return ref.watch(conversationRepositoryProvider).getMessages(conversationId);
  }

  /// Optimistically appends the outgoing message as `sending`, then
  /// resolves it once the (currently mocked) repository call returns —
  /// same "instant UI, reconciled after" approach `ConversationsNotifier`
  /// uses for pin/mute/archive/etc.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conversationId = arg;
    final current = state.valueOrNull ?? const <MessageEntity>[];

    final optimistic = MessageEntity(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
    );
    state = AsyncValue.data([...current, optimistic]);

    final sent = await ref.read(conversationRepositoryProvider).sendMessage(conversationId, trimmed);
    final latest = state.valueOrNull ?? current;
    state = AsyncValue.data([
      for (final m in latest) if (m.id == optimistic.id) sent else m,
    ]);

    ref.read(conversationsNotifierProvider.notifier).applyLastMessage(conversationId, sent);
  }
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, List<MessageEntity>, String>(
  MessagesNotifier.new,
);
