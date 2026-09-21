import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';

void main() {
  group('unwrapOrThrow', () {
    test('returns the data for a successful response', () {
      expect(unwrapOrThrow<Map<String, dynamic>>(200, {'ok': true}), {
        'ok': true,
      });
    });

    test('carries a structured backend code alongside the message', () {
      expect(
        () => unwrapOrThrow<Map<String, dynamic>>(429, {
          'statusCode': 429,
          'code': 'ATTEMPT_LIMIT',
          'message': "You've reached today's face verification limit.",
        }),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.code, 'code', 'ATTEMPT_LIMIT')
              .having(
                (e) => e.message,
                'message',
                "You've reached today's face verification limit.",
              ),
        ),
      );
    });

    test('leaves code null for the default Nest error shape', () {
      expect(
        () => unwrapOrThrow<Map<String, dynamic>>(400, {
          'statusCode': 400,
          'message': ['consent must be true', 'attemptId must be a UUID'],
          'error': 'Bad Request',
        }),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', isNull)
              .having(
                (e) => e.message,
                'message',
                'consent must be true, attemptId must be a UUID',
              ),
        ),
      );
    });

    test('ignores a non-string or empty code', () {
      for (final code in [42, '', null]) {
        expect(
          () => unwrapOrThrow<Map<String, dynamic>>(409, {
            'message': 'x',
            'code': code,
          }),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', isNull)),
        );
      }
    });

    test('keeps the positional constructor working for existing callers', () {
      final e = ApiException(500, 'boom');
      expect(e.code, isNull);
      expect(e.toString(), 'ApiException(500): boom');
    });
  });
}
