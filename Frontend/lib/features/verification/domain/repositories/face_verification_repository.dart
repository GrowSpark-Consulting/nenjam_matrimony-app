import '../models/face_verification.dart';

/// Backend contract for `backend/apps/api/src/modules/verification`'s face
/// (selfie liveness) endpoints — see
/// `docs/development/selfie-verification-frontend-handoff.md` §4.
abstract class FaceVerificationRepository {
  /// `GET /verification/face` — the caller's own current state.
  Future<FaceVerificationState> getState();

  /// `POST /verification/face/sessions` — starts an attempt. Throws
  /// [ApiException] with `code` set to one of `NOT_AVAILABLE`,
  /// `ALREADY_VERIFIED`, `NO_PRIMARY_PHOTO`, `UNSUPPORTED_PHOTO`,
  /// `ATTEMPT_LIMIT`, or `PROVIDER_UNAVAILABLE` on rejection.
  Future<LivenessSessionTicket> startSession({required bool consent});

  /// `POST /verification/face/complete` — call on every native outcome
  /// (completed, cancelled, or errored), immediately. Idempotent: calling it
  /// again for an already-decided attempt returns the same decision. May
  /// throw [ApiException] with `code` `ATTEMPT_IN_PROGRESS` or
  /// `RESULT_NOT_READY` — both mean "retry shortly", not failure.
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  });
}
