import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/profile_views_repository_impl.dart';
import '../../domain/entities/profile_viewer_entity.dart';
import '../../domain/repositories/profile_views_repository.dart';

final profileViewsRepositoryProvider = Provider<ProfileViewsRepository>(
  (ref) => ProfileViewsRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The Profile Viewers list. Refreshed on pull-to-refresh and whenever the
/// screen is reached from a PROFILE_VIEW notification, so a member who taps
/// "someone viewed your profile" sees that viewer rather than a stale page.
class ProfileViewersNotifier
    extends AsyncNotifier<List<ProfileViewerEntity>> {
  @override
  Future<List<ProfileViewerEntity>> build() {
    return ref.watch(profileViewsRepositoryProvider).getViewers();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(profileViewsRepositoryProvider).getViewers(),
    );
  }
}

final profileViewersNotifierProvider =
    AsyncNotifierProvider<ProfileViewersNotifier, List<ProfileViewerEntity>>(
  ProfileViewersNotifier.new,
);

/// Records that the signed-in user opened [profileId]'s profile.
///
/// Deliberately swallows every failure: this is analytics-grade telemetry
/// fired from Profile Detail's `initState`, and a member must never see an
/// error — or a blocked screen — because a view couldn't be logged.
Future<void> recordProfileView(WidgetRef ref, String profileId) async {
  try {
    await ref.read(profileViewsRepositoryProvider).recordView(profileId);
  } catch (_) {
    // Best-effort by design.
  }
}
