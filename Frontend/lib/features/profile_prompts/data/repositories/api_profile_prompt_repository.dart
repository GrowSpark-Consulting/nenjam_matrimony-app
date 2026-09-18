import 'package:dio/dio.dart' show CancelToken;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';

/// Maps backend/apps/api/.../entities/PromptCategory enum values
/// ("PERSONALITY", "MARRIAGE_COMPATIBILITY", …) to this app's
/// [PromptCategory]. Falls back to [PromptCategory.personality] for an
/// unrecognized value rather than throwing — a new backend category should
/// degrade gracefully, not crash the prompt bank.
PromptCategory _categoryFromBackend(String? raw) {
  switch (raw) {
    case 'MARRIAGE_COMPATIBILITY':
      return PromptCategory.marriageCompatibility;
    case 'FAMILY':
      return PromptCategory.family;
    case 'CAREER':
      return PromptCategory.career;
    case 'PERSONALITY':
    default:
      return PromptCategory.personality;
  }
}

/// Talks to backend/apps/api/src/modules/profiles' PromptsController.
class ApiProfilePromptRepository implements ProfilePromptRepository {
  ApiProfilePromptRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PromptBankItem>> getPrompts({
    PromptCategory? category,
    CancelToken? cancelToken,
  }) async {
    final response = await _apiClient.get<dynamic>(
      ApiEndpoints.profilePromptsBank,
      cancelToken: cancelToken,
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    final items = ((data as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((e) => PromptBankItem(
              id: e['id'] as String,
              category: _categoryFromBackend(e['category'] as String?),
              promptText: e['promptText'] as String,
            ))
        .toList();
    if (category == null) return items;
    return items.where((p) => p.category == category).toList();
  }

  @override
  Future<List<PromptAnswer>> getUserPrompts({CancelToken? cancelToken}) async {
    final response = await _apiClient.get<dynamic>(
      ApiEndpoints.profilePromptsMe,
      cancelToken: cancelToken,
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return ((data as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((e) => PromptAnswer(
              promptId: e['promptId'] as String,
              promptText: (e['prompt']?['promptText'] as String?) ??
                  (e['promptText'] as String? ?? ''),
              answerText: e['answerText'] as String? ?? '',
            ))
        .toList();
  }

  @override
  Future<void> saveUserPrompts(List<PromptAnswer> prompts) async {
    final response = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.profilePromptsMe,
      data: {
        'prompts': prompts
            .map((a) => {'promptId': a.promptId, 'answerText': a.answerText})
            .toList(),
      },
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> deletePrompt(String promptId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.profilePromptDelete(promptId),
    );
    // The backend returns 200 with an empty body — unwrapOrThrow only cares
    // about turning a 4xx (401 unauthenticated, 404 already-deleted) into an
    // ApiException; there's no payload to return on success. Same pattern as
    // SafetyRepositoryImpl.unblockUser's DELETE call.
    unwrapOrThrow(response.statusCode, response.data);
  }
}
