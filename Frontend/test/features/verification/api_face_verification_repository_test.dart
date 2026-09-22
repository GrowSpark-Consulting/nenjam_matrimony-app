import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/verification/data/repositories/api_face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.onFetch);
  final Response<dynamic> Function(RequestOptions) onFetch;
  RequestOptions? lastRequest;
  dynamic lastData;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    lastData = options.data;
    final response = onFetch(options);
    return ResponseBody.fromString(
      response.data is String ? response.data as String : '',
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

ApiClient _buildClient(Response<dynamic> Function(RequestOptions) onFetch) {
  final client = ApiClient();
  client.dio.httpClientAdapter = _FakeAdapter(onFetch);
  client.dio.options.responseType = ResponseType.json;
  return client;
}

void main() {
  group('ApiFaceVerificationRepository', () {
    test('getState hits GET /verification/face and maps the response', () async {
      RequestOptions? captured;
      final client = _buildClient((options) {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data:
              '{"status":"VERIFIED","verifiedAt":"2026-09-21T10:00:00.000Z","canStart":false,"blockedReason":null,"attemptsRemainingToday":3,"retryAfter":null}',
        );
      });
      final repo = ApiFaceVerificationRepository(client);

      final state = await repo.getState();

      expect(captured!.method, 'GET');
      expect(captured!.path, '/verification/face');
      expect(state.status, FaceVerificationStatus.verified);
      expect(state.canStart, isFalse);
    });

    test('startSession posts consent:true and maps the ticket', () async {
      final client = _buildClient((options) {
        return Response(
          requestOptions: options,
          statusCode: 201,
          data:
              '{"attemptId":"a1","sessionId":"s1","region":"ap-south-1","expiresAt":"2026-09-21T10:03:00.000Z","credentials":{"accessKeyId":"k","secretAccessKey":"s","sessionToken":"t","expiration":"2026-09-21T10:15:00.000Z"}}',
        );
      });
      final repo = ApiFaceVerificationRepository(client);

      final ticket = await repo.startSession(consent: true);

      expect(ticket.attemptId, 'a1');
      expect(ticket.sessionId, 's1');
      expect(ticket.region, 'ap-south-1');
    });

    test('a 422 NO_PRIMARY_PHOTO response throws ApiException with that code', () async {
      final client = _buildClient((options) {
        return Response(
          requestOptions: options,
          statusCode: 422,
          data:
              '{"statusCode":422,"message":"No primary photo","code":"NO_PRIMARY_PHOTO"}',
        );
      });
      final repo = ApiFaceVerificationRepository(client);

      await expectLater(
        () => repo.startSession(consent: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.code, 'code', 'NO_PRIMARY_PHOTO'),
        ),
      );
    });

    test('complete posts attemptId and clientOutcome, maps a FAILED result', () async {
      RequestOptions? captured;
      final client = _buildClient((options) {
        captured = options;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data:
              '{"attemptId":"a1","status":"FAILED","reason":"FAILED_MATCH","canRetry":true,"attemptsRemainingToday":2}',
        );
      });
      final repo = ApiFaceVerificationRepository(client);

      final result = await repo.complete(
        attemptId: 'a1',
        clientOutcome: ClientLivenessOutcome.completed,
      );

      expect(captured!.method, 'POST');
      expect(captured!.path, '/verification/face/complete');
      expect(result.verified, isFalse);
      expect(result.reason, FaceVerificationFailureReason.failedMatch);
      expect(result.canRetry, isTrue);
    });
  });
}
