import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_conversation_starter_repository.dart';
import '../../domain/conversation_starter.dart';
import '../../domain/repositories/conversation_starter_repository.dart';

/// Default implementation is the in-memory mock. Override this provider
/// with a Gemini-backed repository once that service is ready — no other
/// code needs to change.
final conversationStarterRepositoryProvider =
    Provider<ConversationStarterRepository>(
  (ref) => MockConversationStarterRepository(),
);

final conversationStarterProvider = FutureProvider.autoDispose
    .family<List<ConversationStarter>, String>((ref, targetUserId) {
  return ref
      .watch(conversationStarterRepositoryProvider)
      .getStarters(targetUserId: targetUserId);
});
