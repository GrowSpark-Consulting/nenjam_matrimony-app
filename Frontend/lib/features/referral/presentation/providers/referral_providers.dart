import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/repositories/api_referral_repository.dart';
import '../../data/repositories/mock_referral_repository.dart';
import '../../data/repositories/unavailable_referral_repository.dart';
import '../../data/services/pending_referral_store.dart';
import '../../domain/repositories/referral_repository.dart';
import '../../domain/services/referral_attachment_controller.dart';

/// Whether the backend's referral endpoints are live. They are **not** yet
/// (contract agreed, not built), so this is off unless a build passes
/// `--dart-define=REFERRAL_ENDPOINTS_LIVE=true` — and turning it on is the
/// one-line flip from mock to [ApiReferralRepository].
const bool kReferralEndpointsLive = bool.fromEnvironment(
  'REFERRAL_ENDPOINTS_LIVE',
);

/// Which backend the referral feature talks to.
enum ReferralBackendMode {
  /// The real endpoints ([ApiReferralRepository]).
  live,

  /// [MockReferralRepository] — debug builds only, never shipped.
  mock,

  /// Neither: no box on the name step, and nothing is ever attached.
  off,
}

/// The one rule deciding [ReferralBackendMode], pure so every build
/// configuration can be tested.
///
/// The mock exists only in debug builds. A profile or release build without
/// the flag gets [ReferralBackendMode.off] — never the mock — so a build a
/// real member could install can never show "Referred by …" or "Referral
/// code applied" off mock data.
ReferralBackendMode referralBackendMode({
  required bool endpointsLive,
  required bool debugBuild,
}) {
  if (endpointsLive) return ReferralBackendMode.live;
  return debugBuild ? ReferralBackendMode.mock : ReferralBackendMode.off;
}

final referralBackendModeProvider = Provider<ReferralBackendMode>(
  (ref) => referralBackendMode(
    endpointsLive: kReferralEndpointsLive,
    debugBuild: kDebugMode,
  ),
);

/// `POST /referrals/codes/validate` and `POST /registration/referral-code`.
/// In [ReferralBackendMode.off] nothing should reach this (the box is hidden
/// and the attach controller is disabled); if anything does, it is refused
/// rather than answered by the mock.
final referralRepositoryProvider = Provider<ReferralRepository>(
  (ref) => switch (ref.watch(referralBackendModeProvider)) {
    ReferralBackendMode.live => ApiReferralRepository(
      ref.watch(apiClientProvider),
    ),
    ReferralBackendMode.mock => const MockReferralRepository(),
    ReferralBackendMode.off => const UnavailableReferralRepository(),
  },
);

/// Whether the name step shows the "Have a referral code?" box, and whether
/// anything is ever attached. Off unless live, or a debug build on the mock.
final referralCodeEntryEnabledProvider = Provider<bool>(
  (ref) => ref.watch(referralBackendModeProvider) != ReferralBackendMode.off,
);

final pendingReferralStoreProvider = Provider<PendingReferralStore>(
  (ref) => StoragePendingReferralStore(storageService),
);

/// One controller for the process, so its single-flight guard covers every
/// trigger point.
final referralAttachmentControllerProvider =
    Provider<ReferralAttachmentController>(
      (ref) => ReferralAttachmentController(
        repository: ref.watch(referralRepositoryProvider),
        store: ref.watch(pendingReferralStoreProvider),
        isEnabled: () => ref.read(referralCodeEntryEnabledProvider),
        isSignedIn: () {
          try {
            return ref.read(firebaseAuthServiceProvider).currentUser != null;
          } catch (_) {
            return false;
          }
        },
      ),
    );
