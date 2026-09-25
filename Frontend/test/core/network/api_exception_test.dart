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
      expect(e.retryAfterSeconds, isNull);
      expect(e.toString(), 'ApiException(500): boom');
    });
  });

  group('unwrapOrThrow retryAfterSeconds', () {
    test(
      'carries a positive retryAfterSeconds from the body (cooldown 429)',
      () {
        expect(
          () => unwrapOrThrow<Map<String, dynamic>>(429, {
            'statusCode': 429,
            'error': 'Too Many Requests',
            'message': 'You can change your quiz answers again in 3 days.',
            'retryAfterSeconds': 259200,
          }),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 429)
                .having(
                  (e) => e.retryAfterSeconds,
                  'retryAfterSeconds',
                  259200,
                ),
          ),
        );
      },
    );

    test('a fractional value rounds up, never down to zero', () {
      expect(
        () => unwrapOrThrow<Map<String, dynamic>>(429, {
          'message': 'x',
          'retryAfterSeconds': 0.2,
        }),
        throwsA(
          isA<ApiException>().having(
            (e) => e.retryAfterSeconds,
            'retryAfterSeconds',
            1,
          ),
        ),
      );
    });

    test('is null for the plain rate-limit 429 and for unusable values', () {
      for (final value in [null, 0, -5, '3600', double.infinity, double.nan]) {
        expect(
          () => unwrapOrThrow<Map<String, dynamic>>(429, {
            'statusCode': 429,
            'message': 'ThrottlerException: Too Many Requests',
            'retryAfterSeconds': value,
          }),
          throwsA(
            isA<ApiException>().having(
              (e) => e.retryAfterSeconds,
              'retryAfterSeconds',
              isNull,
            ),
          ),
          reason: 'retryAfterSeconds: $value',
        );
      }
    });
  });
}
