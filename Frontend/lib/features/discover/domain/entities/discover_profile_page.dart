import 'discovery_profile_entity.dart';

/// One page of the flat Discover feed, for infinite-scroll surfaces (the
/// Matches reel). Distinct from [DiscoverFeedEntity], which partitions a single
/// page into the sectioned Discover screen.
class DiscoverProfilePage {
  final List<DiscoveryProfileEntity> items;
  final int page;
  final bool hasMore;

  /// Where the next page starts, as the backend named it. Pass it back as
  /// `cursor` to continue from exactly here; null means there is no next page.
  ///
  /// The reel pages by this rather than by [page] because the feed is ranked
  /// per request and demotes profiles it has already shown, so the meaning of
  /// "rows 20-40" changes between two requests: page 2 by offset skipped the
  /// twenty profiles that had just been pushed down. A cursor names a position
  /// in the ordering instead of counting from the start.
  final String? nextCursor;

  const DiscoverProfilePage({
    required this.items,
    required this.page,
    required this.hasMore,
    this.nextCursor,
  });
}
