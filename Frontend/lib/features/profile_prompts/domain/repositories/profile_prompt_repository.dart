import 'package:dio/dio.dart' show CancelToken;
import '../models/prompt_bank_item.dart';

/// Relationship Intelligence — Profile Prompts (Hinge/Jeevansathi-style).
///
/// Fully independent of the registration feature — no [ProfileDraft],
/// [RegistrationNotifier] or [RegistrationRepository] involvement, per
/// architecture decision (prompts are optional profile enrichment, not
/// registration data). [MockProfilePromptRepository] is wired as the
/// default today; swap the `profilePromptRepositoryProvider` override to
/// [ApiProfilePromptRepository] once the backend team's endpoints are ready.
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
}
