import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';
import '../../data/repositories/mock_profile_prompt_repository.dart';

/// Default implementation is the in-memory mock. Override this provider
/// with an `ApiProfilePromptRepository` once the backend team's endpoints
/// are ready — no other code needs to change.
final profilePromptRepositoryProvider = Provider<ProfilePromptRepository>(
  (ref) => MockProfilePromptRepository(),
);

/// The pickable prompt bank, optionally filtered by category.
final promptBankProvider = FutureProvider.autoDispose
    .family<List<PromptBankItem>, PromptCategory?>((ref, category) {
  return ref
      .watch(profilePromptRepositoryProvider)
      .getPrompts(category: category);
});

/// The signed-in user's currently saved prompt answers (0-3). Used by
/// ProfilePage, the Profile Intelligence hub, and profile_review_page.dart's
/// edit-mode summary — all read-only consumers of this single provider.
final myPromptsProvider =
    FutureProvider.autoDispose<List<PromptAnswer>>((ref) {
  return ref.watch(profilePromptRepositoryProvider).getUserPrompts();
});
