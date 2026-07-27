import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/conversation_entity.dart';
import '../entities/message_entity.dart';

/// A single page of a conversation's messages, oldest-to-newest within the
/// page. [page] 1 is the most recent slice (what a freshly-opened thread
/// shows); increasing [page] moves further into the past — i.e. what
/// scrolling up to load older history requests next.
class MessagePage {
  const MessagePage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<MessageEntity> items;
  final int page;

  /// Whether an older page still exists beyond this one.
  final bool hasMore;
}

/// A single page of the conversations list — mirrors
/// `features/matches/domain/repositories/matches_repository.dart`'s
/// `MatchesResultPage` shape for consistency across list features.
class ConversationResultPage {
  const ConversationResultPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<ConversationEntity> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

/// Pure abstract Dart interface. Concrete implementations live in `data/`:
/// [ConversationRepositoryImpl] (in-memory, mock-backed — what's actually
/// wired via `conversationRepositoryProvider` today) and
/// [ConversationApiRepositoryImpl] (dormant, hits `ApiEndpoints.conversations`
/// /`.messages` — the swap-in once a real chat backend exists).
abstract interface class ConversationRepository {
  Future<ConversationResultPage> getConversations({int page = 1, int limit = 20});

  /// Resolves the conversation with [profile] — the caller (Profile
  /// Detail's Message action, once an interest is accepted) already knows
  /// *who* to message but not necessarily which [ConversationEntity.id]
  /// that maps to. Returns the existing conversation if one's already
  /// started, otherwise creates one. Callers MUST only invoke this once
  /// the relationship is actually chat-eligible (an accepted interest) —
  /// this method itself does not re-check that; see
  /// docs/development/chat-backend-handoff.md for why a real backend
  /// implementation has to enforce it server-side regardless of what the
  /// frontend checks first.
  Future<ConversationEntity> getOrCreateConversation(DiscoveryProfileEntity profile);

  Future<MessagePage> getMessages(String conversationId, {int page = 1, int limit = 30});

  /// [clientMessageId], when supplied, must be echoed back unchanged on the
  /// returned [MessageEntity] — see that field's doc comment for why. [type]/
  /// [attachmentUrl] together describe a non-text message (an image today);
  /// leave both at their defaults for plain text.
  Future<MessageEntity> sendMessage(
    String conversationId,
    String text, {
    String? clientMessageId,
    MessageType type,
    String? attachmentUrl,
  });

  Future<void> pin(String conversationId, bool pinned);

  Future<void> mute(String conversationId, bool muted);

  Future<void> archive(String conversationId, bool archived);

  Future<void> block(String conversationId, bool blocked);

  Future<void> delete(String conversationId);

  Future<void> markRead(String conversationId);

  Future<void> markUnread(String conversationId);

  /// Signals this client's own typing state for [conversationId] so a real
  /// backend can relay it to the other participant. A no-op today (see
  /// [ConversationRepositoryImpl]) — deliberately NOT wired to
  /// `core/realtime/RealtimeService` yet, since that would mean hardcoding
  /// a guessed socket event name; wire it once the backend's actual chat
  /// event contract exists (see docs/development/chat-backend-handoff.md).
  Future<void> setTyping(String conversationId, bool isTyping);
}
