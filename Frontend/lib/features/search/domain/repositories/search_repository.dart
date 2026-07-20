import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/search_filters_entity.dart';

/// A single page of search results.
class SearchResultPage {
  const SearchResultPage({
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

/// Pure abstract Dart interface. Concrete implementations live in `data/`.
/// Not wired to any provider today — `search_providers.dart` still filters
/// client-side over Discover's shared mock pool.
abstract interface class SearchRepository {
  /// `GET /search?query=&page=&limit=&<filters>`.
  Future<SearchResultPage> search({
    required String query,
    required SearchFilters filters,
    int page = 1,
    int limit = 20,
  });
}
