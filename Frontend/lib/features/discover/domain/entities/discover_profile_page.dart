import 'discovery_profile_entity.dart';

/// One page of the flat Discover feed, for infinite-scroll surfaces (the
/// Matches reel). Distinct from [DiscoverFeedEntity], which partitions a single
/// page into the sectioned Discover screen.
class DiscoverProfilePage {
  final List<DiscoveryProfileEntity> items;
  final int page;
  final bool hasMore;

  const DiscoverProfilePage({
    required this.items,
    required this.page,
    required this.hasMore,
  });
}
