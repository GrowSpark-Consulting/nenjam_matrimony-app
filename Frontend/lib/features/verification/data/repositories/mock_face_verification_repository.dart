import '../../domain/models/face_verification.dart';
import '../../domain/repositories/face_verification_repository.dart';

/// For building/testing the UI before the backend team enables
/// `FACE_VERIFICATION_ENABLED` on a shared environment. Matches the real
/// `NOT_AVAILABLE` shape — it never fabricates a `VERIFIED` result, since the
/// entry gate must only ever trust a real backend response.
class MockFaceVerificationRepository implements FaceVerificationRepository {
  @override
  Future<FaceVerificationState> getState() async {
    return const FaceVerificationState(
      status: FaceVerificationStatus.unverified,
      verifiedAt: null,
      canStart: false,
      blockedReason: FaceBlockedReason.notAvailable,
      attemptsRemainingToday: 0,
      retryAfter: null,
    );
  }

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) {
    throw UnimplementedError(
      'Face verification is not available in the mock repository.',
    );
  }

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) {
    throw UnimplementedError(
      'Face verification is not available in the mock repository.',
    );
  }
}
