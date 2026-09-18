import 'package:dio/dio.dart' show CancelToken;
import '../models/prompt_bank_item.dart';

/// Relationship Intelligence — Profile Prompts (Hinge/Jeevansathi-style).
///
/// Fully independent of the registration feature — no [ProfileDraft],
/// [RegistrationNotifier] or [RegistrationRepository] involvement, per
/// architecture decision (prompts are optional profile enrichment, not
/// registration data). [ApiProfilePromptRepository] is what
/// `profilePromptRepositoryProvider` wires today.
abstract class ProfilePromptRepository {
  /// The pickable bank of prompts, optionally filtered by [category].
  Future<List<PromptBankItem>> getPrompts({
    PromptCategory? category,
    CancelToken? cancelToken,
  });

  /// The signed-in user's currently saved prompt answers (0-3).
  Future<List<PromptAnswer>> getUserPrompts({CancelToken? cancelToken});

  /// Replace-all save. Prompts are optional — an empty list is valid and
  /// clears any saved answers.
  Future<void> saveUserPrompts(List<PromptAnswer> prompts);

  /// Removes one saved prompt answer, identified by [promptId] (the
  /// prompt-bank id — [PromptAnswer.promptId] — not a row id; the backend
  /// scopes the delete to the caller's own row via the verified auth token,
  /// so this can only ever affect the signed-in user's own answer).
  /// `DELETE /profiles/prompts/me/:promptId`. Throws on failure (the data
  /// layer's `ApiException` in the real implementation), including a 404 if
  /// the prompt was already removed.
  Future<void> deletePrompt(String promptId);
}
