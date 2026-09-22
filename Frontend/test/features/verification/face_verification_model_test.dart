import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';

void main() {
  group('FaceVerificationState.satisfiesEntryGate', () {
    test('VERIFIED satisfies the gate', () {
      final state = FaceVerificationState.fromJson({
        'status': 'VERIFIED',
        'verifiedAt': '2026-09-21T10:00:00.000Z',
        'canStart': false,
        'blockedReason': 'ALREADY_VERIFIED',
        'attemptsRemainingToday': 3,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isTrue);
    });

    test('NOT_AVAILABLE is a pass-through, not equivalent to verified', () {
      final state = FaceVerificationState.fromJson({
        'status': 'UNVERIFIED',
        'verifiedAt': null,
        'canStart': false,
        'blockedReason': 'NOT_AVAILABLE',
        'attemptsRemainingToday': 0,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isTrue);
      expect(state.status, FaceVerificationStatus.unverified);
    });

    test('UNVERIFIED with canStart true blocks entry', () {
      final state = FaceVerificationState.fromJson({
        'status': 'UNVERIFIED',
        'verifiedAt': null,
        'canStart': true,
        'blockedReason': null,
        'attemptsRemainingToday': 3,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isFalse);
    });

    test('REVOKED blocks entry until re-verified', () {
      final state = FaceVerificationState.fromJson({
        'status': 'REVOKED',
        'verifiedAt': '2026-09-01T00:00:00.000Z',
        'canStart': true,
        'blockedReason': null,
        'attemptsRemainingToday': 3,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isFalse);
    });

    test('NO_PRIMARY_PHOTO blocks entry (not a pass-through)', () {
      final state = FaceVerificationState.fromJson({
        'status': 'UNVERIFIED',
        'verifiedAt': null,
        'canStart': false,
        'blockedReason': 'NO_PRIMARY_PHOTO',
        'attemptsRemainingToday': 3,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isFalse);
    });

    test('an unrecognized blockedReason still blocks entry', () {
      final state = FaceVerificationState.fromJson({
        'status': 'UNVERIFIED',
        'verifiedAt': null,
        'canStart': false,
        'blockedReason': 'SOME_FUTURE_REASON',
        'attemptsRemainingToday': 0,
        'retryAfter': null,
      });
      expect(state.satisfiesEntryGate, isFalse);
      expect(state.blockedReason, FaceBlockedReason.unknown);
    });
  });

  group('FaceVerificationResult.fromJson', () {
    test('maps VERIFIED status to verified=true', () {
      final result = FaceVerificationResult.fromJson({
        'attemptId': 'a1',
        'status': 'VERIFIED',
        'reason': null,
        'canRetry': false,
        'attemptsRemainingToday': 2,
      });
      expect(result.verified, isTrue);
      expect(result.reason, isNull);
    });

    test('maps FAILED status with a known reason', () {
      final result = FaceVerificationResult.fromJson({
        'attemptId': 'a1',
        'status': 'FAILED',
        'reason': 'FAILED_MATCH',
        'canRetry': true,
        'attemptsRemainingToday': 1,
      });
      expect(result.verified, isFalse);
      expect(result.reason, FaceVerificationFailureReason.failedMatch);
      expect(result.reason!.suggestsPhotoUpdate, isTrue);
    });

    test('an unrecognized reason maps to error, not a crash', () {
      final result = FaceVerificationResult.fromJson({
        'attemptId': 'a1',
        'status': 'FAILED',
        'reason': 'SOME_NEW_REASON',
        'canRetry': true,
        'attemptsRemainingToday': 1,
      });
      expect(result.reason, FaceVerificationFailureReason.error);
    });
  });

  test('LivenessSessionTicket.toString hides every secret field', () {
    final ticket = LivenessSessionTicket.fromJson({
      'attemptId': 'a1',
      'sessionId': 's1',
      'region': 'ap-south-1',
      'expiresAt': '2026-09-21T10:03:00.000Z',
      'credentials': {
        'accessKeyId': 'ASIASECRET',
        'secretAccessKey': 'topsecret',
        'sessionToken': 'sessiontoken',
        'expiration': '2026-09-21T10:15:00.000Z',
      },
    });
    final text = ticket.toString();
    expect(text, isNot(contains('ASIASECRET')));
    expect(text, isNot(contains('topsecret')));
    expect(text, isNot(contains('sessiontoken')));
    expect(text, contains('a1'));
  });
}
