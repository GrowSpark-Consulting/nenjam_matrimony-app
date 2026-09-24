import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_endpoints.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/psychology/data/repositories/api_personality_repository.dart';

import 'psychology_test_support.dart';

/// Records every request and replays a canned response — the same stubbing
/// approach `partner_preferences_repository_test.dart` uses.
class _StubClient extends ApiClient {
  _StubClient({this.data, this.status = 200});

  Map<String, dynamic>? data;
  int status;

  final List<String> methods = [];
  final List<String> paths = [];
  final List<dynamic> bodies = [];

  Response<T> _reply<T>(String path) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: data as T?,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('GET');
    paths.add(path);
    bodies.add(null);
    return _reply<T>(path);
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    methods.add('POST');
    paths.add(path);
    bodies.add(data);
    return _reply<T>(path);
  }
}

void main() {
  group('GET /psychology/quiz/active', () {
    test('hits the active endpoint and parses the quiz', () async {
      final client = _StubClient(data: activeQuizJson(id: 'live-id'));
      final quiz = await ApiPersonalityRepository(client).getActiveQuiz();

      expect(client.methods, ['GET']);
      expect(client.paths, [ApiEndpoints.psychologyQuizActive]);
      expect(ApiEndpoints.psychologyQuizActive, '/psychology/quiz/active');
      expect(quiz.id, 'live-id');
      expect(quiz.questions.first.options, hasLength(4));
    });

    test('404 (no active quiz) throws ApiException(404)', () async {
      final client = _StubClient(
        status: 404,
        data: {
          'statusCode': 404,
          'message': 'No active psychology quiz is configured.',
        },
      );
      await expectLater(
        ApiPersonalityRepository(client).getActiveQuiz(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });

  group('POST /psychology/quiz/submit', () {
    test(
      'sends exactly { quizId, answers: [{questionId, selectedKey}] }',
      () async {
        final client = _StubClient(data: myResponseJson(quizId: 'live-id'));
        final result = await ApiPersonalityRepository(client).submitAnswers(
          quizId: 'live-id',
          answers: {'q1': 'B', 'q2': 'C', 'q3': 'A'},
        );

        expect(client.methods, ['POST']);
        expect(client.paths, ['/psychology/quiz/submit']);
        expect(client.bodies.single, {
          'quizId': 'live-id',
          'answers': [
            {'questionId': 'q1', 'selectedKey': 'B'},
            {'questionId': 'q2', 'selectedKey': 'C'},
            {'questionId': 'q3', 'selectedKey': 'A'},
          ],
        });
        // No legacy Likert field anywhere in the payload.
        final answers = (client.bodies.single as Map)['answers'] as List;
        for (final a in answers) {
          expect((a as Map).containsKey('score'), isFalse);
        }
        expect(result.quizId, 'live-id');
        expect(result.selectedKeys, {'q1': 'B', 'q2': 'C', 'q3': 'A'});
      },
    );

    test('a 400 validation error surfaces as ApiException(400)', () async {
      final client = _StubClient(
        status: 400,
        data: {
          'statusCode': 400,
          'message': 'quizId does not match the active quiz.',
          'error': 'Bad Request',
        },
      );
      await expectLater(
        ApiPersonalityRepository(
          client,
        ).submitAnswers(quizId: 'old', answers: {'q1': 'A'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });
  });

  group('GET /psychology/quiz/me', () {
    test('parses the saved response', () async {
      final client = _StubClient(data: myResponseJson());
      final me = await ApiPersonalityRepository(client).getMyResponse();

      expect(client.paths, ['/psychology/quiz/me']);
      expect(me, isNotNull);
      expect(me!.answers.map((a) => a.selectedLabel), [
        'Q1 option B',
        'Q2 option C',
        'Q3 option A',
      ]);
    });

    test('404 means "not completed" — returns null, does not throw', () async {
      final client = _StubClient(
        status: 404,
        data: {
          'statusCode': 404,
          'message': 'You have not taken the psychology quiz yet.',
        },
      );
      expect(await ApiPersonalityRepository(client).getMyResponse(), isNull);
    });

    test('other errors still throw', () async {
      final client = _StubClient(
        status: 401,
        data: {'statusCode': 401, 'message': 'Unauthorized'},
      );
      await expectLater(
        ApiPersonalityRepository(client).getMyResponse(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
