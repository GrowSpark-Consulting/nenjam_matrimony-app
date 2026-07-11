import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';

/// Real backend implementation — not wired by default (see
/// `profilePromptRepositoryProvider`). Ready for the backend team to
/// connect by flipping that provider's override once their endpoints are
/// live; no UI changes required.
class ApiProfilePromptRepository implements ProfilePromptRepository {
  ApiProfilePromptRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PromptBankItem>> getPrompts({PromptCategory? category}) async {
    final response = await _apiClient.get<List<dynamic>>(
      ApiEndpoints.profilePromptsBank,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map((e) => PromptBankItem(
              id: e['id'] as String,
              category: PromptCategory.personality,
              promptText: e['promptText'] as String,
            ))
        .toList();
  }

  @override
  Future<List<PromptAnswer>> getUserPrompts() async {
    final response =
        await _apiClient.get<List<dynamic>>(ApiEndpoints.profilePromptsMe);
    return (response.data ?? [])
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
    await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.profilePromptsMe,
      data: {
        'prompts': prompts
            .map((a) => {'promptId': a.promptId, 'answerText': a.answerText})
            .toList(),
      },
    );
  }
}
