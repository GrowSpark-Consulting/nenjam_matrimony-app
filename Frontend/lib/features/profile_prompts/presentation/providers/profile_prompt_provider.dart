import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';
import '../../data/repositories/api_profile_prompt_repository.dart';

final profilePromptRepositoryProvider = Provider<ProfilePromptRepository>(
  (ref) => ApiProfilePromptRepository(ref.watch(apiClientProvider)),
);

/// The pickable prompt bank, optionally filtered by category.
final promptBankProvider = FutureProvider.autoDispose
    .family<List<PromptBankItem>, PromptCategory?>((ref, category) {
  final cancelToken = CancelToken();
  // Cancelled when the Choose Prompt screen is popped — see
  // mySettingsProvider for the rationale.
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(profilePromptRepositoryProvider)
      .getPrompts(category: category, cancelToken: cancelToken);
});

/// The signed-in user's currently saved prompt answers (0-3). Used by
/// ProfilePage, the Profile Intelligence hub, and profile_review_page.dart's
/// edit-mode summary — all read-only consumers of this single provider.
final myPromptsProvider =
    FutureProvider.autoDispose<List<PromptAnswer>>((ref) {
  final cancelToken = CancelToken();
  // Cancelled when the Choose Prompt screen is popped — see
  // mySettingsProvider for the rationale.
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(profilePromptRepositoryProvider)
      .getUserPrompts(cancelToken: cancelToken);
});
