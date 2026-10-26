import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../data/datasources/profile_detail_remote_datasource.dart';
import '../../data/repositories/profile_detail_repository_impl.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/repositories/profile_detail_repository.dart';

final profileDetailRemoteDataSourceProvider =
    Provider<ProfileDetailRemoteDataSource>(
  (ref) => ProfileDetailRemoteDataSource(ref.watch(apiClientProvider)),
);

final profileDetailRepositoryProvider = Provider<ProfileDetailRepository>(
  (ref) => ProfileDetailRepositoryImpl(
    ref.watch(profileDetailRemoteDataSourceProvider),
  ),
);

/// Family-keyed by the base profile so navigating Discover → Detail(A) →
/// similar → Detail(B) → back never refetches or leaks state across
/// different members. `.autoDispose` keeps the cache from growing
/// unbounded as the user browses many profiles in one session.
final profileDetailProvider = FutureProvider.autoDispose
    .family<ProfileDetailEntity, DiscoveryProfileEntity>((ref, base) {
  return ref.watch(profileDetailRepositoryProvider).getProfileDetail(base);
});

/// Re-projects the existing Discover feed pool into a "similar profiles"
/// shelf — no new repository, no new mock pool. Heuristic: same religion
/// or community, excluding the viewed profile itself, capped at 10.
final similarProfilesProvider = Provider.autoDispose
    .family<AsyncValue<List<DiscoveryProfileEntity>>, DiscoveryProfileEntity>(
  (ref, base) {
    final feedAsync = ref.watch(discoverFeedProvider);
    return feedAsync.whenData((feed) {
      final pool = [
        ...feed.aiRecommended,
        ...feed.verifiedProfiles,
        ...feed.premiumMembers,
        ...feed.recentlyJoined,
        ...feed.nearYou,
      ];
      final others = pool.where((p) => p.id != base.id);
      final matches = others.where(
        (p) =>
            (p.religion.isNotEmpty && p.religion == base.religion) ||
            (p.community.isNotEmpty && p.community == base.community),
      );
      final ranked = matches.isNotEmpty ? matches : others;
      final seen = <String>{};
      return ranked.where((p) => seen.add(p.id)).take(10).toList();
    });
  },
);
