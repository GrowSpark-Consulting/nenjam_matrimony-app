import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// A single page of the matches feed.
class MatchesResultPage {
  const MatchesResultPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<DiscoveryProfileEntity> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Not wired to any provider today — `matchCategoryFeedProvider` still
/// re-projects the shared Discover feed (see that provider's own doc
/// comment) and the Interested/Shortlist/Decline buttons in
/// `matches_page.dart` only update local widget state.
abstract interface class MatchesRepository {
  /// `GET /matches`.
  Future<MatchesResultPage> getMatches({int page = 1, int limit = 20});

  /// `POST /matches/interest`.
  Future<void> expressInterest(String profileId);

  /// `POST /matches/shortlist`.
  Future<void> shortlist(String profileId);

  /// `POST /matches/decline`.
  Future<void> decline(String profileId);

  /// `POST /matches/viewed`.
  Future<void> markViewed(String profileId);
}
