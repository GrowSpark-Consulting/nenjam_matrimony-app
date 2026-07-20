import '../../../registration/domain/models/profile_draft.dart';

/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Not wired to any provider today — `verification_page.dart` (standalone
/// feature) and the registration wizard's `step_verification.dart` both
/// toggle [VerificationStatus] locally with no backend call. Reuses
/// [VerificationStatus] (defined in the registration feature, step 13's
/// model) rather than a parallel type, so both screens can eventually
/// share one provider/state once wired.
abstract interface class VerificationRepository {
  /// `GET /verification/status`.
  Future<VerificationStatus> getStatus();

  /// `POST /verification/id` — government ID document verification.
  Future<void> submitIdVerification({required String documentUrl});

  /// `POST /verification/photo` — face/selfie verification.
  Future<void> submitPhotoVerification({required String photoUrl});
}
