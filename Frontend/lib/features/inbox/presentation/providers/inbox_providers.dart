import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/datasources/conversation_mock_datasource.dart';
import '../../data/repositories/conversation_repository_impl.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';

final conversationMockDataSourceProvider = Provider<ConversationMockDataSource>(
  (ref) => ConversationMockDataSource(),
);

/// Swap point for a real backend: replace with
/// `ConversationApiRepositoryImpl(ref.watch(apiClientProvider),
/// currentUserId: () => ref.read(authRepositoryProvider).currentUser!.uid)`
/// (confirm that's really the id `senderId` uses first — see that class's
/// doc comment) once the `chat` controller ships.
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

  /// Resolves the conversation to open for Profile Detail's "Message"
  /// action (only ever called once the caller has already confirmed the
  /// interest is accepted — see `interest_button_copy.dart#handleMessageButtonTap`).
  /// Returns the already-loaded conversation for [profile] without a
  /// network round-trip if this list already has one; otherwise asks the
  /// repository to get-or-create it and merges the result in, so the
  /// Inbox list and Chat Detail never disagree about which conversation
  /// this is. Returns null (rather than throwing) on failure so the caller
  /// can show "Unable to open chat" and stay put, per the product
  /// requirement — Profile Detail must never navigate on a failed lookup.
  Future<ConversationEntity?> getOrCreateConversationFor(DiscoveryProfileEntity profile) async {
    final current = state.valueOrNull;
    if (current != null) {
      for (final c in current) {
        if (c.profile.id == profile.id) return c;
      }
    }
    try {
      final conversation =
          await ref.read(conversationRepositoryProvider).getOrCreateConversation(profile);
      final latest = state.valueOrNull;
      if (latest != null && !latest.any((c) => c.id == conversation.id)) {
        state = AsyncValue.data([conversation, ...latest]);
      }
      return conversation;
    } catch (_) {
      return null;
    }
  }

  /// Called after `messagesProvider(id).send(...)`/`.sendImage(...)` —
  /// keeps this list's "last message" preview in sync without a second
  /// network round-trip. [preview] lets a non-text message (e.g. an image)
  /// show a human-readable label instead of its empty/raw `text`.
  void applyLastMessage(String id, MessageEntity message, {String? preview}) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == id)
          c.copyWith(
            lastMessage: preview ?? message.text,
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

/// Monotonic discriminator so two client-generated ids constructed in the
/// same microsecond (rapid-fire sends) still never collide — same role as
/// `core/router/profile_navigation.dart`'s `_pageKeySeq`.
int _clientMessageIdSeq = 0;

String _newClientMessageId(String conversationId) =>
    'local-$conversationId-${DateTime.now().microsecondsSinceEpoch}-${_clientMessageIdSeq++}';

/// One thread's messages, keyed by conversation id — drives Chat Detail.
/// Oldest-to-newest, exactly as rendered (index 0 is the top of the list).
class MessagesNotifier extends FamilyAsyncNotifier<List<MessageEntity>, String> {
  int _page = 1;
  bool _hasMore = false;
  bool _isLoadingOlder = false;

  bool get hasMoreHistory => _hasMore;
  bool get isLoadingOlderHistory => _isLoadingOlder;

  @override
  Future<List<MessageEntity>> build(String conversationId) async {
    final result = await ref.watch(conversationRepositoryProvider).getMessages(conversationId);
    _page = result.page;
    _hasMore = result.hasMore;
    return result.items;
  }

  /// Fetches the next-older page and prepends it — called when the user
  /// scrolls near the top of the thread. No-ops while already loading or
  /// once the repository has said there's nothing older.
  Future<void> loadOlder() async {
    if (_isLoadingOlder || !_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;

    _isLoadingOlder = true;
    try {
      final result = await ref
          .read(conversationRepositoryProvider)
          .getMessages(arg, page: _page + 1);
      _page = result.page;
      _hasMore = result.hasMore;
      if (result.items.isNotEmpty) {
        state = AsyncValue.data([...result.items, ...current]);
      }
    } finally {
      _isLoadingOlder = false;
    }
  }

  /// Optimistically appends the outgoing message as `sending`, then
  /// resolves it once the (currently mocked) repository call returns —
  /// same "instant UI, reconciled after" approach `ConversationsNotifier`
  /// uses for pin/mute/archive/etc. Reconciliation is keyed by
  /// [MessageEntity.clientMessageId], not by list position, so it stays
  /// correct even if other messages (an incoming one, an older page) land
  /// in between the optimistic append and the repository call resolving.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final clientMessageId = _newClientMessageId(arg);
    final optimistic = MessageEntity(
      id: clientMessageId,
      conversationId: arg,
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      clientMessageId: clientMessageId,
    );
    final current = state.valueOrNull ?? const <MessageEntity>[];
    state = AsyncValue.data([...current, optimistic]);
    await _resolve(optimistic);
  }

  /// Re-attempts a message that previously landed in [MessageStatus.failed]
  /// — reuses the same [clientMessageId] (and therefore the same bubble/
  /// position) rather than appending a new one, so retrying never produces
  /// a duplicate-looking message.
  Future<void> retry(String clientMessageId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    MessageEntity? target;
    for (final m in current) {
      if (m.clientMessageId == clientMessageId) {
        target = m;
        break;
      }
    }
    if (target == null || target.status != MessageStatus.failed) return;

    state = AsyncValue.data([
      for (final m in current)
        if (m.clientMessageId == clientMessageId) m.copyWith(status: MessageStatus.sending) else m,
    ]);
    await _resolve(target.copyWith(status: MessageStatus.sending));
  }

  /// Sends [file] as an image attachment — same optimistic/reconcile
  /// lifecycle as [send]. The mock repository accepts the local file path
  /// as-is (no real upload endpoint exists yet — see
  /// docs/development/chat-backend-handoff.md); [ConversationApiRepositoryImpl]
  /// documents the proposed contract without implementing a fake one.
  Future<void> sendImage(String localFilePath) async {
    final clientMessageId = _newClientMessageId(arg);
    final optimistic = MessageEntity(
      id: clientMessageId,
      conversationId: arg,
      text: '',
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.image,
      attachmentUrl: localFilePath,
      clientMessageId: clientMessageId,
    );
    final current = state.valueOrNull ?? const <MessageEntity>[];
    state = AsyncValue.data([...current, optimistic]);
    await _resolve(optimistic);
  }

  /// Shared tail end of [send]/[retry]/[sendImage]: calls the repository
  /// for [optimistic], then either replaces it in place with the confirmed
  /// message or marks it [MessageStatus.failed] — matched by
  /// [MessageEntity.clientMessageId] both times, never by list index.
  Future<void> _resolve(MessageEntity optimistic) async {
    final conversationId = arg;
    final clientMessageId = optimistic.clientMessageId!;
    try {
      final sent = await ref.read(conversationRepositoryProvider).sendMessage(
            conversationId,
            optimistic.text,
            clientMessageId: clientMessageId,
            type: optimistic.type,
            attachmentUrl: optimistic.type == MessageType.text ? null : optimistic.attachmentUrl,
          );
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest) if (m.clientMessageId == clientMessageId) sent else m,
        ]);
      }
      ref.read(conversationsNotifierProvider.notifier).applyLastMessage(
            conversationId,
            sent,
            preview: optimistic.type == MessageType.text ? sent.text : '📷 Photo',
          );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest)
            if (m.clientMessageId == clientMessageId) m.copyWith(status: MessageStatus.failed) else m,
        ]);
      }
    }
  }
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, List<MessageEntity>, String>(
  MessagesNotifier.new,
);
