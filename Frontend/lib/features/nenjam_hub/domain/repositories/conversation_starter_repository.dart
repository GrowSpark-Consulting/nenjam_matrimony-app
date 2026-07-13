import '../conversation_starter.dart';

/// [MockConversationStarterRepository] is wired as the default today; swap
/// the `conversationStarterRepositoryProvider` override to a Gemini-backed
/// implementation once that service exists — no widget changes required.
abstract class ConversationStarterRepository {
  Future<List<ConversationStarter>> getStarters({required String targetUserId});
}
