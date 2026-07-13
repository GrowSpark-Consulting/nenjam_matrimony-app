import '../domain/conversation_starter.dart';
import '../domain/repositories/conversation_starter_repository.dart';

/// In-memory mock — no network calls. Default implementation until a
/// Gemini-backed service ships (see [ConversationStarterRepository]).
class MockConversationStarterRepository
    implements ConversationStarterRepository {
  @override
  Future<List<ConversationStarter>> getStarters({
    required String targetUserId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return const [
      ConversationStarter(
        id: 'cs1',
        message:
            'Hi! I noticed we both value family closely — what does that look like for you day to day?',
      ),
      ConversationStarter(
        id: 'cs2',
        message:
            "Your profile mentioned travel — what's a trip you're still hoping to take?",
      ),
      ConversationStarter(
        id: 'cs3',
        message:
            'We seem to match well on lifestyle — what does a perfect weekend look like for you?',
      ),
    ];
  }
}
