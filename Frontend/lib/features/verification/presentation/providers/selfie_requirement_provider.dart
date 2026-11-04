import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../registration/domain/models/selfie_verification_requirement.dart';

/// Whether the signed-in member's profile owes selfie verification — the
/// in-app entry points (profile tile, Verification Center card, the face
/// screen itself) all follow this, so a "Son"/"Friend"/referral profile is
/// never shown a selfie control.
///
/// Reads the saved draft's `profileCreatedFor` (the same cached
/// `GET /profiles/draft` the profile dashboard already uses — no extra
/// request). While loading or on error this is not `true`, so no selfie
/// control flashes up for a profile that turns out to be exempt; the backend
/// still decides what a Myself member may actually do.
final selfieVerificationRequiredProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final draft = await ref.watch(myProfileDraftProvider.future);
  var referralCreated = false;
  try {
    referralCreated = storageService.referralCreatedProfile;
  } catch (_) {
    // Storage not initialised (a harness): no marker to honour.
  }
  return selfieVerificationRequired(
    profileCreatedFor: draft.basicDetails.profileCreatedFor,
    referralCreated: referralCreated,
  );
});
