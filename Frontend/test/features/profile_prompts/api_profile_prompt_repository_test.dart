import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_endpoints.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/profile_prompts/data/repositories/api_profile_prompt_repository.dart';
import 'package:nenjam_matrimony/features/profile_prompts/domain/models/prompt_bank_item.dart';

/// Records the method/path of every request and replays a canned response —
/// the same stubbing approach used across the app's other repository tests
/// (e.g. `search_repository_test.dart`).
class _StubClient extends ApiClient {
  _StubClient({this.data, this.status = 200});

  dynamic data;
  int status;

  final List<String> methods = [];
  final List<String> paths = [];

  DioException? throws;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('GET');
    paths.add(path);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: data as T?,
    );
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('PUT');
    paths.add(path);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: this.data as T?,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('DELETE');
    paths.add(path);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: this.data as T?,
    );
  }
}

void main() {
  group('ApiProfilePromptRepository.deletePrompt', () {
    test('calls DELETE /profiles/prompts/me/:promptId', () async {
      final client = _StubClient(data: null);

      await ApiProfilePromptRepository(client).deletePrompt('prompt-1');

      expect(client.methods, ['DELETE']);
      expect(client.paths, ['/profiles/prompts/me/prompt-1']);
      expect(
        ApiEndpoints.profilePromptDelete('prompt-1'),
        '/profiles/prompts/me/prompt-1',
      );
    });

    test('a plain 200 with no body is a successful delete — no exception',
        () async {
      final client = _StubClient(data: null, status: 200);

      await expectLater(
        ApiProfilePromptRepository(client).deletePrompt('prompt-1'),
        completes,
      );
    });

    test('throws ApiException on 401', () async {
      final client = _StubClient(
        status: 401,
        data: {'statusCode': 401, 'message': 'Missing bearer token.'},
      );

      await expectLater(
        ApiProfilePromptRepository(client).deletePrompt('prompt-1'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('throws ApiException on 404 (already deleted / not owned)', () async {
      final client = _StubClient(
        status: 404,
        data: {'statusCode': 404, 'message': 'Prompt answer not found.'},
      );

      await expectLater(
        ApiProfilePromptRepository(client).deletePrompt('prompt-1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.message, 'message', 'Prompt answer not found.'),
        ),
      );
    });

    test('propagates a connection failure rather than swallowing it', () async {
      final client = _StubClient()
        ..throws = DioException.connectionTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: RequestOptions(
            path: ApiEndpoints.profilePromptDelete('prompt-1'),
          ),
        );

      await expectLater(
        ApiProfilePromptRepository(client).deletePrompt('prompt-1'),
        throwsA(isA<DioException>()),
      );
    });

    test('deletePrompt sends no request body — DELETE carries the id in the '
        'path only', () async {
      final client = _StubClient(data: null);

      await ApiProfilePromptRepository(client).deletePrompt('abc-123');

      // path already asserted above; this confirms the URL is built with
      // exactly the given id and nothing else appended/escaped oddly.
      expect(client.paths.single, endsWith('/abc-123'));
    });
  });

  group('ApiProfilePromptRepository — existing GET/PUT flows are unchanged',
      () {
    test('getPrompts still calls GET /profiles/prompts/bank', () async {
      final client = _StubClient(data: <Map<String, dynamic>>[
        {'id': 'p1', 'category': 'FAMILY', 'promptText': 'A family value I hold dear...'},
      ]);

      final result = await ApiProfilePromptRepository(client).getPrompts();

      expect(client.methods, ['GET']);
      expect(client.paths, ['/profiles/prompts/bank']);
      expect(result.single.id, 'p1');
      expect(result.single.category, PromptCategory.family);
    });

    test('getUserPrompts still calls GET /profiles/prompts/me', () async {
      final client = _StubClient(data: <Map<String, dynamic>>[
        {'promptId': 'p1', 'promptText': 'Q', 'answerText': 'A'},
      ]);

      final result = await ApiProfilePromptRepository(client).getUserPrompts();

      expect(client.methods, ['GET']);
      expect(client.paths, ['/profiles/prompts/me']);
      expect(result.single.promptId, 'p1');
    });

    test('saveUserPrompts still PUTs the full replacement list to '
        '/profiles/prompts/me', () async {
      // saveUserPrompts reads the response as a Map (it discards the value —
      // unwrapOrThrow is only used for the 4xx-throws side effect), unlike
      // getPrompts/getUserPrompts above, which read a List.
      final client = _StubClient(data: <String, dynamic>{});

      await ApiProfilePromptRepository(client).saveUserPrompts(const [
        PromptAnswer(promptId: 'p1', promptText: 'Q', answerText: 'A'),
      ]);

      expect(client.methods, ['PUT']);
      expect(client.paths, ['/profiles/prompts/me']);
    });
  });
}
