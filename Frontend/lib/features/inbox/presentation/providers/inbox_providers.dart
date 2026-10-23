import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/repositories/conversation_api_repository_impl.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';
import 'package:cross_file/cross_file.dart';

/// The live chat repository — talks to the real backend over REST + the shared
/// realtime socket (typing). Incoming socket events are applied by
/// `chatRealtimeSyncProvider`.
final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => ConversationApiRepositoryImpl(
    ref.watch(apiClientProvider),
    realtime: ref.watch(realtimeServiceProvider),
  ),
);

/// Conversation ids whose message thread is currently loaded (Chat Detail
/// open). The realtime bridge applies incoming message/edit/delete/receipt
/// events to a thread only when it's active — an event for an unopened room
/// updates just the conversation list (unread + preview), and the thread picks
/// up the change from a fresh history fetch when it's next opened.
class ChatActiveThreads extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String conversationId) => state = {...state, conversationId};

  void remove(String conversationId) =>
      state = state.where((id) => id != conversationId).toSet();
}

final chatActiveThreadsProvider =
    NotifierProvider<ChatActiveThreads, Set<String>>(ChatActiveThreads.new);

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

  /// Re-fetches the list *without* dropping the current data into a loading
  /// state, and keeps the existing data if the fetch fails. For background
  /// re-syncs the user didn't ask for — a socket reconnect, or returning to
  /// the foreground — where [refresh]'s `AsyncValue.loading()` would blink
  /// every derived consumer through "no data": the Inbox list would flash a
  /// spinner and, more visibly, the bottom-nav unread badge would pop out to
  /// zero and back on every reconnect. Pull-to-refresh still uses [refresh],
  /// where a visible loading state is exactly what the user asked for.
  Future<void> refreshSilently() async {
    final result = await AsyncValue.guard(() async {
      final page = await ref.read(conversationRepositoryProvider).getConversations();
      return page.items;
    });
    if (result.hasValue) state = result;
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

  /// Unblock with rollback: `_apply` (shared with `block`, `pin`, `mute`, …)
  /// applies its optimistic update unconditionally and never reverts it if
  /// `persist` throws — fine for a first cut, but wrong for unblock, whose
  /// failure the caller needs to react to (Chat's confirmation flow rolls
  /// back to a "still blocked" banner and shows an error). Wraps `block`
  /// rather than duplicating its logic; only adds a rollback on top.
  Future<void> unblock(String id) async {
    final previous = state.valueOrNull;
    try {
      await block(id, false);
    } catch (_) {
      if (previous != null) state = AsyncValue.data(previous);
      rethrow;
    }
  }

  /// Syncs the blocked flag onto whichever conversation belongs to
  /// [profileId] — local-state-only, no repository call. Used after a
  /// block/unblock performed through a different entry point (Profile
  /// Detail's "More" menu calls `SafetyRepository` directly, not this
  /// notifier) so the Inbox list and Chat Detail banner don't go stale until
  /// the next full refresh. No-ops if there's no conversation with them yet.
  void applyBlockedFlag(String profileId, bool isBlocked) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.profile.id == profileId) c.copyWith(isBlocked: isBlocked) else c,
    ]);
  }

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

  /// A message was edited (this user's own confirmed edit, or a
  /// `chat.messageEdited` push from the peer/another device) — if it's
  /// still this conversation's current last message (matched by `sentAt`,
  /// which an edit never changes), refresh the preview text to the edited
  /// content. An edit to an older message that's no longer the last one is
  /// a no-op here — the preview must only ever reflect the actual last
  /// message, exactly like a fresh fetch would show.
  void applyEditedMessage(String conversationId, MessageEntity message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == conversationId && c.lastMessageAt.isAtSameMomentAs(message.sentAt))
          c.copyWith(lastMessage: message.text)
        else
          c,
    ]);
  }

  /// Applies a message that arrived over the socket (from the peer, or an echo
  /// of this user's own send on another device) to the list: refreshes the
  /// preview/timestamp, and bumps the unread badge for an incoming message.
  /// If the conversation isn't in the list yet (a peer's very first message
  /// starting a brand-new thread), re-fetches the list so it appears.
  void applyIncomingMessage(MessageEntity message, {bool bumpUnread = true}) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.any((c) => c.id == message.conversationId)) {
      unawaited(refresh());
      return;
    }
    // Don't bump unread for this user's own echo, or when the thread is open
    // (the caller passes bumpUnread: false then — the reader is looking at it).
    final increments = bumpUnread && !message.isMine;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == message.conversationId)
          c.copyWith(
            lastMessage: conversationPreview(message),
            lastMessageAt: message.sentAt,
            lastMessageFromMe: message.isMine,
            lastMessageStatus:
                message.isMine ? MessageDeliveryStatus.sent : c.lastMessageStatus,
            unreadCount: increments ? c.unreadCount + 1 : c.unreadCount,
          )
        else
          c,
    ]);
  }

  /// The peer read this user's messages in [id] — reflect it on the row's
  /// last-message tick.
  void applyPeerRead(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == id && c.lastMessageFromMe)
          c.copyWith(lastMessageStatus: MessageDeliveryStatus.read)
        else
          c,
    ]);
  }

  /// A message this user sent in [id] was delivered to the peer — advance
  /// the row's tick from sent to delivered (mirrors [MessagesNotifier.
  /// applyDelivered] for the open thread). Never regresses an already-read
  /// tick back to delivered.
  void applyDelivered(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == id &&
            c.lastMessageFromMe &&
            c.lastMessageStatus == MessageDeliveryStatus.sent)
          c.copyWith(lastMessageStatus: MessageDeliveryStatus.delivered)
        else
          c,
    ]);
  }

  /// The peer's typing state changed for [id].
  void setTyping(String id, bool isTyping) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        if (c.id == id) c.copyWith(isTyping: isTyping) else c,
    ]);
  }
}

/// A human-readable last-message preview for the conversation list — mirrors the
/// backend's own label logic for media so both sides read the same.
String conversationPreview(MessageEntity message) => switch (message.type) {
      MessageType.text => message.text,
      MessageType.image => '📷 Photo',
      MessageType.voice => '🎤 Voice message',
      MessageType.document => '📄 Document',
    };

final conversationsNotifierProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<ConversationEntity>>(
  ConversationsNotifier.new,
);

/// Search + filter + pinned-first sort applied to a raw conversations list.
///
/// With no [query] and no [filters] this is the Inbox's default view:
/// archived and blocked conversations hidden, pinned first, newest next.
List<ConversationEntity> filterConversations(
  Iterable<ConversationEntity> all, {
  String query = '',
  Set<InboxFilter> filters = const {},
}) {
  final normalizedQuery = query.trim().toLowerCase();
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

  if (normalizedQuery.isNotEmpty) {
    result = result.where((c) =>
        c.profile.name.toLowerCase().contains(normalizedQuery) ||
        c.profile.matrimonyId.toLowerCase().contains(normalizedQuery) ||
        c.lastMessage.toLowerCase().contains(normalizedQuery));
  }

  return result.toList()
    ..sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
}

/// The Inbox page's list: [filterConversations] driven by its own search box
/// and filter sheet — same "derive, don't duplicate" style as
/// `discover_providers.dart`'s `discoverProfilesProvider`.
final filteredConversationsProvider = Provider<AsyncValue<List<ConversationEntity>>>((ref) {
  final query = ref.watch(inboxSearchQueryProvider);
  final filters = ref.watch(inboxFilterProvider);
  return ref.watch(conversationsNotifierProvider).whenData(
        (all) => filterConversations(all, query: query, filters: filters),
      );
});

/// The Inbox's default view, deliberately blind to the Inbox page's search box
/// and filter sheet: a query typed there must not empty a preview shown
/// somewhere else.
final inboxPreviewConversationsProvider =
    Provider<AsyncValue<List<ConversationEntity>>>((ref) {
  return ref.watch(conversationsNotifierProvider).whenData(filterConversations);
});

/// Unread conversation count for the Messages tab's badge.
final unreadConversationsCountProvider = Provider<int>((ref) {
  final all = ref.watch(conversationsNotifierProvider).valueOrNull ?? const [];
  return all.where((c) => !c.isArchived && !c.isBlocked && c.unreadCount > 0).length;
});

/// Total unread *messages* across the active inbox — the app-wide number the
/// bottom nav's Inbox badge shows (Instagram/WhatsApp style).
///
/// Deliberately different from [unreadConversationsCountProvider], which
/// counts *threads* with anything unread and drives the Inbox "Messages"
/// tab: on the tab, next to a list of conversations, "3" meaning three
/// conversations reads correctly; on the nav icon it has to mean three
/// messages, which is what every other app trains people to expect.
///
/// Derived rather than fetched — there is no app-wide unread endpoint, and
/// none is needed: `GET /conversations` already returns each room's
/// `unreadCount` (the per-user `ChatParticipantState`), so summing here keeps
/// one source of truth and gets every optimistic update for free. Archived
/// and blocked conversations are excluded to match which rows the default
/// Inbox list actually shows; muted ones still count — mute silences
/// notifications, it doesn't mark anything read.
final unreadMessagesCountProvider = Provider<int>((ref) {
  final all = ref.watch(conversationsNotifierProvider).valueOrNull ?? const [];
  var total = 0;
  for (final c in all) {
    if (c.isArchived || c.isBlocked) continue;
    total += c.unreadCount;
  }
  return total;
});

/// Monotonic discriminator so two client-generated ids constructed in the
/// same microsecond (rapid-fire sends) still never collide — same role as
/// `core/router/profile_navigation.dart`'s `_pageKeySeq`.
int _clientMessageIdSeq = 0;

String _newClientMessageId(String conversationId) =>
    'local-$conversationId-${DateTime.now().microsecondsSinceEpoch}-${_clientMessageIdSeq++}';

/// Two [MessageEntity] values represent "the same logical message" if they
/// share a server [MessageEntity.id] OR a [MessageEntity.clientMessageId] —
/// checked both directions, since it doesn't matter whether the REST
/// response, the socket echo, or a reconnect replay happens to be the one
/// that arrives first, nor which side's `id` still holds a client-generated
/// value at that moment (an unconfirmed optimistic entry's `id` IS its
/// `clientMessageId`, until [MessagesNotifier._resolve] replaces it).
bool _isSameMessage(MessageEntity a, MessageEntity b) {
  if (a.id == b.id) return true;
  if (a.clientMessageId != null && a.clientMessageId == b.clientMessageId) {
    return true;
  }
  return false;
}

/// Stable chronological order: [MessageEntity.sentAt] first, then `id` as a
/// tiebreaker (mirrors the backend's own keyset-pagination secondary sort —
/// `[{createdAt:'desc'},{id:'desc'}]` in `message.repository.ts`) so two
/// messages created in the same millisecond still compare consistently
/// instead of by arrival order.
int _compareMessages(MessageEntity a, MessageEntity b) {
  final byTime = a.sentAt.compareTo(b.sentAt);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}

/// The index a genuinely new message should be inserted at to keep
/// [messages] (assumed already correctly ordered) in order — a linear scan
/// rather than a blind append, so an out-of-order arrival (reconnect replay
/// delivering an old message after newer ones are already loaded, or a
/// clock-skewed peer message) lands in the right place instead of at the
/// tail. Every other message's index is left untouched.
int _insertionIndex(List<MessageEntity> messages, MessageEntity toInsert) {
  for (var i = 0; i < messages.length; i++) {
    if (_compareMessages(toInsert, messages[i]) < 0) return i;
  }
  return messages.length;
}

/// The single place a full [MessageEntity] gets inserted into or reconciled
/// with a thread's list — the one merge function every path that can
/// produce or receive a complete message (the optimistic append in
/// [MessagesNotifier.send]/[MessagesNotifier.sendImage]/
/// [MessagesNotifier.sendVoice], the REST response in
/// [MessagesNotifier._resolve]/[MessagesNotifier._resolveMediaUpload], and
/// the socket's [MessagesNotifier.applyIncoming] — which also carries
/// reconnect replay, since the server re-emits `chat.message` for that too)
/// funnels through. So "does this message already exist, and where does it
/// belong" is answered exactly once, the same way, everywhere — this is the
/// single source of truth for message identity and order. A match (see
/// [_isSameMessage]) is replaced in place at its existing index — a
/// message's chronological position never changes after creation, only its
/// content/status can. A genuinely new message is inserted at its correct
/// sorted position (see [_insertionIndex]) rather than appended, without
/// disturbing any other message's current index — in the overwhelmingly
/// common case (a message newer than everything loaded) this still lands at
/// the end, identical to a plain append; the sorted insert only changes
/// behavior for the rare out-of-order arrival.
List<MessageEntity> _mergeMessage(List<MessageEntity> current, MessageEntity incoming) {
  final index = current.indexWhere((m) => _isSameMessage(m, incoming));
  if (index != -1) {
    return [
      for (var i = 0; i < current.length; i++)
        if (i == index) incoming else current[i],
    ];
  }
  final insertAt = _insertionIndex(current, incoming);
  return [
    ...current.sublist(0, insertAt),
    incoming,
    ...current.sublist(insertAt),
  ];
}

/// One thread's messages, keyed by conversation id — drives Chat Detail.
/// Oldest-to-newest, exactly as rendered (index 0 is the top of the list).
class MessagesNotifier extends FamilyAsyncNotifier<List<MessageEntity>, String> {
  int _page = 1;
  // Set from the repository's echoed `nextCursor` once the first page loads.
  // Non-null means the repository supports keyset pagination — [loadOlder]
  // then always walks by cursor (stable under concurrent inserts) rather
  // than by [_page]; null (e.g. the in-memory mock) falls back to paging.
  String? _cursor;
  bool _hasMore = false;
  bool _isLoadingOlder = false;

  bool get hasMoreHistory => _hasMore;
  bool get isLoadingOlderHistory => _isLoadingOlder;

  @override
  Future<List<MessageEntity>> build(String conversationId) async {
    // Mark this thread active so the realtime bridge applies live events to it
    // (see [chatActiveThreadsProvider]). Registered after build via a microtask
    // so we never mutate another provider mid-build; deregistered on dispose.
    ref.onDispose(
      () => ref.read(chatActiveThreadsProvider.notifier).remove(conversationId),
    );
    Future.microtask(
      () => ref.read(chatActiveThreadsProvider.notifier).add(conversationId),
    );

    // Empty-string cursor opts into keyset mode's first page; a repository
    // that doesn't support it (the mock) just ignores the argument.
    final result = await ref
        .watch(conversationRepositoryProvider)
        .getMessages(conversationId, cursor: '');
    _page = result.page;
    _cursor = result.nextCursor;
    _hasMore = result.hasMore;
    return result.items;
  }

  /// Fetches the next-older page and prepends it — called when the user
  /// scrolls near the top of the thread. No-ops while already loading or
  /// once the repository has said there's nothing older. Dedups by
  /// [_isSameMessage] (id OR clientMessageId, same key every other merge
  /// path uses) regardless of paging mode.
  Future<void> loadOlder() async {
    if (_isLoadingOlder || !_hasMore) return;
    if (state.valueOrNull == null) return;

    _isLoadingOlder = true;
    try {
      final result = await ref.read(conversationRepositoryProvider).getMessages(
            arg,
            page: _page + 1,
            cursor: _cursor,
          );
      _page = result.page;
      _cursor = result.nextCursor;
      _hasMore = result.hasMore;
      if (result.items.isEmpty) return;

      // Re-read fresh here — NOT a `current` captured before the await
      // above. State can change while this request is in flight (e.g. a
      // live message arriving via the socket), and rebuilding from a stale
      // pre-await snapshot would silently discard that update.
      final latest = state.valueOrNull;
      if (latest == null) return;
      final fresh = result.items.where(
        (item) => !latest.any((existing) => _isSameMessage(existing, item)),
      );
      // Older-page items are structurally guaranteed to predate everything
      // already loaded (that's what makes them "older"), and are already
      // correctly ordered relative to each other — a plain prepend of the
      // deduped subset stays correctly ordered, no per-item sorted-insert
      // needed here (unlike `_mergeMessage`, which handles the arbitrary
      // "could belong anywhere" case for socket/REST arrivals).
      state = AsyncValue.data([...fresh, ...latest]);
    } finally {
      _isLoadingOlder = false;
    }
  }

  /// Re-fetches just the newest page and merges each item in via
  /// [_mergeMessage] — called after a socket reconnect (see
  /// `chatRealtimeSyncProvider`'s `onReady` listener) so this open thread
  /// picks up any delivery/read status transition its live events might
  /// have missed while disconnected (in particular: this user is the
  /// SENDER of a message whose `chat.delivered`/`chat.read` broadcast
  /// arrived with nobody home to receive it — nothing else ever re-tells
  /// them). Deliberately does NOT touch `_page`/`_cursor`/`_hasMore` — this
  /// is a top-up merge, not a pagination reset, so scroll position and
  /// history already loaded further up are completely undisturbed.
  /// Best-effort: a failed resync just waits for the next live event or the
  /// next reconnect.
  Future<void> resyncLatest() async {
    if (state.valueOrNull == null) return;
    try {
      final result =
          await ref.read(conversationRepositoryProvider).getMessages(arg, cursor: '');
      // Re-read fresh — not a value captured before the await — same reason
      // as [loadOlder].
      final latest = state.valueOrNull;
      if (latest == null) return;
      var merged = latest;
      for (final message in result.items) {
        merged = _mergeMessage(merged, message);
      }
      state = AsyncValue.data(merged);
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  /// Optimistically appends the outgoing message as `sending`, then
  /// resolves it once the (currently mocked) repository call returns —
  /// same "instant UI, reconciled after" approach `ConversationsNotifier`
  /// uses for pin/mute/archive/etc. Reconciliation is keyed by
  /// [MessageEntity.clientMessageId], not by list position, so it stays
  /// correct even if other messages (an incoming one, an older page) land
  /// in between the optimistic append and the repository call resolving.
  ///
  /// [replyTo], when supplied, is the message being replied to — the caller
  /// (`ChatDetailPage`) is responsible for resolving it to its freshest
  /// known state first (see that page's `_resolveReplyTarget`), so this
  /// never has to special-case a reply target that was itself still
  /// `sending` at the moment the user chose to reply to it.
  Future<void> send(String text, {MessageEntity? replyTo}) async {
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
      replyTo: replyTo == null ? null : MessageReplyPreview.fromMessage(replyTo),
    );
    final current = state.valueOrNull ?? const <MessageEntity>[];
    state = AsyncValue.data(_mergeMessage(current, optimistic));
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
    final retrying = target.copyWith(status: MessageStatus.sending);
    // Image/voice must always retry through the upload-first path — never
    // [_resolve], which would hand the repository the local file's path as
    // if it were already hosted (see [_resolveMediaUpload]'s doc comment).
    switch (retrying.type) {
      case MessageType.voice:
        await _resolveMediaUpload(
          retrying,
          (repo) => repo.uploadVoiceAttachment(retrying.attachmentUrl!),
          '🎤 Voice message',
        );
      case MessageType.image:
        await _resolveMediaUpload(
          retrying,
          // Re-wraps the pending message's own local reference. `XFile`
          // reads a device path on mobile and re-fetches the `blob:` URL on
          // web, so a retry works on both without having kept the original
          // pick alive.
          (repo) => repo.uploadImageAttachment(XFile(retrying.attachmentUrl!)),
          '📷 Photo',
        );
      case MessageType.text:
      case MessageType.document:
        await _resolve(retrying);
    }
  }

  /// Sends [file] as an image attachment — uploads it first (see
  /// [_resolveMediaUpload]), then the same optimistic/reconcile lifecycle
  /// as [send]. See [send]'s doc comment on [replyTo].
  Future<void> sendImage(XFile file, {MessageEntity? replyTo}) async {
    final clientMessageId = _newClientMessageId(arg);
    final optimistic = MessageEntity(
      id: clientMessageId,
      conversationId: arg,
      text: '',
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.image,
      // `XFile.path` is a device path on mobile and a `blob:` object URL on
      // web; either way it is what the optimistic bubble renders from until
      // the hosted URL replaces it (see NmLocalMediaImage).
      attachmentUrl: file.path,
      clientMessageId: clientMessageId,
      replyTo: replyTo == null ? null : MessageReplyPreview.fromMessage(replyTo),
    );
    final current = state.valueOrNull ?? const <MessageEntity>[];
    state = AsyncValue.data(_mergeMessage(current, optimistic));
    await _resolveMediaUpload(
      optimistic,
      (repo) => repo.uploadImageAttachment(file),
      '📷 Photo',
    );
  }

  /// Sends a recorded voice note — uploads it first (see
  /// [_resolveMediaUpload]), then the same optimistic/reconcile lifecycle
  /// as [send]. See [send]'s doc comment on [replyTo].
  Future<void> sendVoice(String localFilePath, Duration duration, {MessageEntity? replyTo}) async {
    final clientMessageId = _newClientMessageId(arg);
    final optimistic = MessageEntity(
      id: clientMessageId,
      conversationId: arg,
      text: '',
      sentAt: DateTime.now(),
      isMine: true,
      status: MessageStatus.sending,
      type: MessageType.voice,
      attachmentUrl: localFilePath,
      voiceDuration: duration,
      clientMessageId: clientMessageId,
      replyTo: replyTo == null ? null : MessageReplyPreview.fromMessage(replyTo),
    );
    final current = state.valueOrNull ?? const <MessageEntity>[];
    state = AsyncValue.data(_mergeMessage(current, optimistic));
    await _resolveMediaUpload(
      optimistic,
      (repo) => repo.uploadVoiceAttachment(localFilePath),
      '🎤 Voice message',
    );
  }

  /// Shared upload-first resolution for [sendImage]/[sendVoice]/[retry] on a
  /// media message — never hands [ConversationRepository.sendMessage] a
  /// local file path directly; [upload] must return a real hosted URL
  /// first. [optimistic.attachmentUrl] is the local file path;
  /// [optimistic.voiceDuration] (voice only) is preserved onto the
  /// confirmed message since the backend has no column to echo it back
  /// from (see [MessageEntity.voiceDuration]'s doc comment).
  Future<void> _resolveMediaUpload(
    MessageEntity optimistic,
    Future<String> Function(ConversationRepository repo) upload,
    String preview,
  ) async {
    final conversationId = arg;
    final clientMessageId = optimistic.clientMessageId!;
    final repo = ref.read(conversationRepositoryProvider);
    try {
      final hostedUrl = await upload(repo);
      final sent = await repo.sendMessage(
        conversationId,
        '',
        clientMessageId: clientMessageId,
        type: optimistic.type,
        attachmentUrl: hostedUrl,
        replyToMessageId: optimistic.replyTo?.id,
      );
      final resolved = optimistic.voiceDuration == null
          ? sent
          : sent.copyWith(voiceDuration: optimistic.voiceDuration);
      final latest = state.valueOrNull;
      if (latest != null) {
        // A `chat.messageDeleted` push (deleting a not-yet-confirmed
        // message is a narrow, separate edge case, but this guard costs
        // nothing to keep consistent with edit's own rule) can land while
        // this was in flight — never resurrect it.
        final alreadyDeleted = latest.any(
          (m) => m.clientMessageId == clientMessageId && m.isDeleted,
        );
        if (!alreadyDeleted) {
          state = AsyncValue.data(_mergeMessage(latest, resolved));
        }
      }
      ref.read(conversationsNotifierProvider.notifier).applyLastMessage(
            conversationId,
            resolved,
            preview: preview,
          );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest)
            if (m.clientMessageId == clientMessageId)
              m.copyWith(status: MessageStatus.failed)
            else
              m,
        ]);
      }
    }
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
            replyToMessageId: optimistic.replyTo?.id,
          );
      final latest = state.valueOrNull;
      if (latest != null) {
        // Same "don't resurrect a since-deleted message" guard as
        // `_resolveMediaUpload`.
        final alreadyDeleted = latest.any(
          (m) => m.clientMessageId == clientMessageId && m.isDeleted,
        );
        if (!alreadyDeleted) {
          state = AsyncValue.data(_mergeMessage(latest, sent));
        }
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

  // ── live socket application (driven by chatRealtimeSyncProvider) ─────────

  /// Applies a message that arrived over the socket — a live push, a
  /// multi-device echo of this user's own send, or a reconnect replay (the
  /// server re-emits `chat.message` for that too). Routed through
  /// [_mergeMessage], the single merge point every full-message path
  /// shares: reconciles an optimistic bubble by [MessageEntity.clientMessageId],
  /// dedupes by server `id`, and inserts a genuinely new message at its
  /// correct chronological position rather than blindly at the tail — which
  /// matters specifically for reconnect replay, since it can deliver a
  /// message older than others already loaded live during the outage.
  void applyIncoming(MessageEntity message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(_mergeMessage(current, message));
  }

  /// Replaces a message with its edited version (from a `chat.messageEdited`).
  /// Never resurrects a message that's since been marked deleted locally —
  /// a delete always wins over a (possibly stale) edit event for the same id.
  void applyEdited(MessageEntity message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == message.id && !m.isDeleted) message else m,
    ]);
  }

  /// Marks a message deleted-for-everyone (from a `chat.messageDeleted`).
  void applyDeleted(String messageId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == messageId) m.copyWith(isDeleted: true) else m,
    ]);
  }

  /// The peer read this thread — advance every one of this user's sent/delivered
  /// messages to read (from a `chat.read`).
  void applyPeerRead() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.isMine &&
            (m.status == MessageStatus.sent ||
                m.status == MessageStatus.delivered))
          m.copyWith(status: MessageStatus.read)
        else
          m,
    ]);
  }

  /// A message this user sent was delivered to the peer (from a
  /// `chat.delivered`) — advance it from sent to delivered.
  void applyDelivered(String messageId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == messageId && m.status == MessageStatus.sent)
          m.copyWith(status: MessageStatus.delivered)
        else
          m,
    ]);
  }

  // ── user edit / delete actions ──────────────────────────────────────────

  /// Ids currently mid-edit — a message already saving can't be edited again
  /// until this resolves (checked by [edit] itself, and exposed via
  /// [isEditPending] so the UI can hide/disable the action too). This rules
  /// out two overlapping `edit()` calls for the same id racing each other's
  /// optimistic update/revert against different "original" snapshots.
  final Set<String> _pendingEditIds = {};

  bool isEditPending(String messageId) => _pendingEditIds.contains(messageId);

  /// Edits [messageId]'s text — optimistic in-place update, reconciled with
  /// the server's response (and reflected onto the conversation list's
  /// preview if this is still its last message), or reverted and rethrown
  /// on failure so the caller can show an error. [isMessageEditWindowExpired]
  /// is only a fast client-side pre-check — the server independently
  /// re-enforces sender-only / text-only / the edit window and is always the
  /// final word.
  Future<void> edit(String messageId, String newText) async {
    final trimmed = newText.trim();
    final current = state.valueOrNull;
    if (current == null || trimmed.isEmpty || _pendingEditIds.contains(messageId)) {
      return;
    }
    MessageEntity? found;
    for (final m in current) {
      if (m.id == messageId) {
        found = m;
        break;
      }
    }
    final original = found;
    if (original == null || original.isDeleted || original.text == trimmed) {
      return;
    }
    if (isMessageEditWindowExpired(original.sentAt)) {
      throw const MessageEditWindowExpiredException();
    }

    _pendingEditIds.add(messageId);
    state = AsyncValue.data([
      for (final m in current)
        if (m.id == messageId)
          m.copyWith(text: trimmed, editedAt: DateTime.now())
        else
          m,
    ]);
    try {
      final updated = await ref
          .read(conversationRepositoryProvider)
          .editMessage(messageId, trimmed);
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest)
            // A `chat.messageDeleted` push can land while this was in
            // flight — never resurrect a message that's since been deleted.
            if (m.id == messageId && !m.isDeleted) updated else m,
        ]);
      }
      ref.read(conversationsNotifierProvider.notifier).applyEditedMessage(arg, updated);
    } catch (error) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest)
            if (m.id == messageId && !m.isDeleted) original else m,
        ]);
      }
      rethrow;
    } finally {
      _pendingEditIds.remove(messageId);
    }
  }

  /// Deletes [messageId] for everyone — optimistic tombstone, reverted if the
  /// server rejects (e.g. not the sender).
  Future<void> deleteMessage(String messageId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    MessageEntity? found;
    for (final m in current) {
      if (m.id == messageId) {
        found = m;
        break;
      }
    }
    final original = found;
    if (original == null) return;

    state = AsyncValue.data([
      for (final m in current)
        if (m.id == messageId) m.copyWith(isDeleted: true) else m,
    ]);
    try {
      await ref.read(conversationRepositoryProvider).deleteMessage(messageId);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data([
          for (final m in latest) if (m.id == messageId) original else m,
        ]);
      }
    }
  }

  // ── expired media URL refresh (driven by ChatMediaImage) ─────────────────

  /// In-flight refresh requests keyed by message id — a message's image
  /// bubble and the fullscreen viewer can both detect the same expired URL
  /// at once; sharing the same [Future] means they get exactly one HTTP
  /// request and the same real outcome, instead of each firing its own and
  /// possibly disagreeing about whether it succeeded.
  final Map<String, Future<bool>> _mediaRefreshInFlight = {};

  /// Called when a message's presigned media URL has expired (detected by a
  /// 403 loading it, in `ChatMediaImage`) — fetches a fresh one and swaps it
  /// into this message's [MessageEntity.attachmentUrl] in place. Every
  /// widget currently showing this message (the bubble, and the fullscreen
  /// viewer if it's open on it) picks up the fix through the normal
  /// provider rebuild — no separate "retry" plumbing needed. Returns
  /// whether it succeeded so the caller knows whether to keep waiting or
  /// fall back to its error state (offline, or the backend couldn't
  /// presign).
  Future<bool> refreshMediaUrl(String messageId) {
    final existing = _mediaRefreshInFlight[messageId];
    if (existing != null) return existing;

    final future = _doRefreshMediaUrl(messageId);
    _mediaRefreshInFlight[messageId] = future;
    unawaited(future.whenComplete(() => _mediaRefreshInFlight.remove(messageId)));
    return future;
  }

  Future<bool> _doRefreshMediaUrl(String messageId) async {
    try {
      final freshUrl =
          await ref.read(conversationRepositoryProvider).refreshMediaUrl(messageId);
      if (freshUrl == null) return false;
      final latest = state.valueOrNull;
      if (latest == null) return false;
      state = AsyncValue.data([
        for (final m in latest)
          if (m.id == messageId) m.copyWith(attachmentUrl: freshUrl) else m,
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, List<MessageEntity>, String>(
  MessagesNotifier.new,
);
