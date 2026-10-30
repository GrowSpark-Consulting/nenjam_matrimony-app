import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_providers.dart';
import '../../data/repositories/api_membership_repository.dart';
import '../../domain/models/membership_models.dart';
import '../../domain/repositories/membership_repository.dart';

/// The membership API. Real by default — the endpoints are deployed. Tests
/// and offline UI work override it with `MockMembershipRepository`.
final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => ApiMembershipRepository(ref.watch(apiClientProvider)),
);

/// `GET /membership/plans` — the catalogue. Not member-specific, so it is
/// simply re-fetched each time the Premium page opens.
final membershipPlansProvider = FutureProvider.autoDispose<MembershipCatalog>(
  (ref) => ref.watch(membershipRepositoryProvider).getPlans(),
);

/// `GET /membership/me` — the signed-in member's plan, caps and options.
///
/// Root-scoped (not autoDispose) because the photo cap reads it from several
/// screens. Per-user, so `main.dart`'s auth listener invalidates it on every
/// sign-out and sign-in, and the app re-reads it on resume. It is never
/// updated locally: after any purchase it is invalidated and re-fetched.
final myMembershipProvider = FutureProvider<MyMembership>(
  (ref) => ref.watch(membershipRepositoryProvider).getMe(),
);

/// `GET /membership/history` — newest first, at most 50.
final membershipHistoryProvider =
    FutureProvider.autoDispose<List<MembershipHistoryItem>>(
      (ref) => ref.watch(membershipRepositoryProvider).getHistory(),
    );

/// Feature id of the profile-photo cap in `effectiveCaps`.
const String kProfilePhotosCapKey = 'profile.photos';

/// The server's photo cap when it isn't enforcing membership limits — the
/// contract's documented `effectiveCaps['profile.photos']` value in shadow
/// mode. Used only until `/membership/me` answers (or if it fails); the
/// server stays the authority and refuses an upload over its real cap.
const int kPreMembershipPhotoCap = 6;

/// How many profile photos the member may hold right now, from
/// `effectiveCaps['profile.photos']`. Null means the server sets no cap.
final profilePhotoCapProvider = Provider<int?>((ref) {
  final me = ref.watch(myMembershipProvider).valueOrNull;
  if (me == null || !me.effectiveCaps.containsKey(kProfilePhotosCapKey)) {
    return kPreMembershipPhotoCap;
  }
  return me.effectiveCaps[kProfilePhotosCapKey];
});

/// The latest membership refusal from a chat send. Chat sends are optimistic
/// (a refused one just turns the bubble red), so the notifier parks the 403
/// here and the open chat page shows the plan sheet once, then clears it.
final chatMembershipDenialProvider = StateProvider<ApiException?>(
  (ref) => null,
);
