import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';

/// Real backend implementation — not wired by default (see
/// `profilePromptRepositoryProvider`). Ready for the backend team to
/// connect by flipping that provider's override once their endpoints are
/// live; no UI changes required.
///
/// TODO(backend): GET /profiles/prompts/bank, GET/PUT /profiles/prompts/me
/// — no `profile_prompts`/`prompts` backend code exists yet (confirmed:
/// zero files anywhere in the backend repo mention "prompt"), so every call
/// here 404s until that module is built.
class ApiProfilePromptRepository implements ProfilePromptRepository {
  ApiProfilePromptRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PromptBankItem>> getPrompts({PromptCategory? category}) async {
    final response = await _apiClient.get<dynamic>(
      ApiEndpoints.profilePromptsBank,
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return ((data as List<dynamic>?) ?? [])
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
        await _apiClient.get<dynamic>(ApiEndpoints.profilePromptsMe);
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
}
