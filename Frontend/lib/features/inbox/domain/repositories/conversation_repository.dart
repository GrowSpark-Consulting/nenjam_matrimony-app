import '../entities/conversation_entity.dart';
import '../entities/message_entity.dart';

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

  Future<List<MessageEntity>> getMessages(String conversationId, {int page = 1, int limit = 30});

  Future<MessageEntity> sendMessage(String conversationId, String text);

  Future<void> pin(String conversationId, bool pinned);

  Future<void> mute(String conversationId, bool muted);

  Future<void> archive(String conversationId, bool archived);

  Future<void> block(String conversationId, bool blocked);

  Future<void> delete(String conversationId);

  Future<void> markRead(String conversationId);

  Future<void> markUnread(String conversationId);
}
