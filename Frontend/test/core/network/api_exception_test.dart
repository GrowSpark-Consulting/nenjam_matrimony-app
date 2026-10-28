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
      expect(e.feature, isNull);
      expect(e.limit, isNull);
      expect(e.resetsAt, isNull);
      expect(e.upgradeTo, isNull);
      expect(e.isMembershipDenial, isFalse);
      expect(e.toString(), 'ApiException(500): boom');
    });
  });

  group('unwrapOrThrow membership refusal details', () {
    ApiException thrownBy(Map<String, dynamic> body) {
      try {
        unwrapOrThrow<Map<String, dynamic>>(403, body);
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('keeps every field of a full refusal (contract example)', () {
      final e = thrownBy({
        'statusCode': 403,
        'error': 'Forbidden',
        'code': 'MEMBERSHIP_LIMIT_REACHED',
        'feature': 'interests.send',
        'message':
            "You've used all 5 interests included in your Free plan "
            'this month. Upgrade to Gold to get more.',
        'plan': 'FREE',
        'limit': 5,
        'used': 5,
        'resetsAt': '2026-10-31T18:30:00.000Z',
        'upgradeTo': 'GOLD',
      });
      expect(e.statusCode, 403);
      expect(e.code, 'MEMBERSHIP_LIMIT_REACHED');
      expect(e.message, startsWith("You've used all 5 interests"));
      expect(e.isMembershipDenial, isTrue);
      expect(e.feature, 'interests.send');
      expect(e.limit, 5);
      expect(e.resetsAt, DateTime.utc(2026, 10, 31, 18, 30));
      expect(e.upgradeTo, 'GOLD');
    });

    test('a partial refusal leaves the missing fields null', () {
      // FEATURE_UNAVAILABLE carries no limit or reset; FAIR_USE has a null
      // upgradeTo, which must not be replaced by any plan.
      final unavailable = thrownBy({
        'code': 'MEMBERSHIP_FEATURE_UNAVAILABLE',
        'message': 'Starting a chat is not included in your Free plan.',
        'feature': 'chat.initiate',
        'upgradeTo': 'GOLD',
      });
      expect(unavailable.feature, 'chat.initiate');
      expect(unavailable.upgradeTo, 'GOLD');
      expect(unavailable.limit, isNull);
      expect(unavailable.resetsAt, isNull);

      final fairUse = thrownBy({
        'code': 'MEMBERSHIP_FAIR_USE_LIMIT',
        'message': 'x',
        'feature': 'interests.send',
        'limit': 0,
        'resetsAt': '2026-10-31T18:30:00.000Z',
        'upgradeTo': null,
      });
      expect(fairUse.limit, 0);
      expect(fairUse.resetsAt, isNotNull);
      expect(fairUse.upgradeTo, isNull);
    });

    test('a refusal with no detail fields keeps code and message only', () {
      final e = thrownBy({'code': 'MEMBERSHIP_LIMIT_REACHED', 'message': 'x'});
      expect(e.code, 'MEMBERSHIP_LIMIT_REACHED');
      expect(e.message, 'x');
      expect(e.feature, isNull);
      expect(e.limit, isNull);
      expect(e.resetsAt, isNull);
      expect(e.upgradeTo, isNull);
    });

    test('malformed values become null, never a guessed value', () {
      final e = thrownBy({
        'code': 'MEMBERSHIP_LIMIT_REACHED',
        'message': 'x',
        'feature': 42,
        'limit': '5',
        'resetsAt': 'next month',
        'upgradeTo': '',
      });
      expect(e.feature, isNull);
      expect(e.limit, isNull);
      expect(e.resetsAt, isNull);
      expect(e.upgradeTo, isNull);

      for (final limit in [-1, 2.5, double.nan, double.infinity]) {
        expect(
          thrownBy({
            'code': 'MEMBERSHIP_LIMIT_REACHED',
            'message': 'x',
            'limit': limit,
          }).limit,
          isNull,
          reason: 'limit: $limit',
        );
      }
    });

    test('ignores the same keys on a non-membership error', () {
      // The account-blocked 403 has no code at all; other features use their
      // own codes. Neither is a membership refusal.
      for (final code in [null, 'ATTEMPT_LIMIT']) {
        final e = thrownBy({
          'code': code,
          'message': 'x',
          'feature': 'interests.send',
          'limit': 5,
          'resetsAt': '2026-10-31T18:30:00.000Z',
          'upgradeTo': 'GOLD',
        });
        expect(e.isMembershipDenial, isFalse, reason: 'code: $code');
        expect(e.feature, isNull);
        expect(e.limit, isNull);
        expect(e.resetsAt, isNull);
        expect(e.upgradeTo, isNull);
      }
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
