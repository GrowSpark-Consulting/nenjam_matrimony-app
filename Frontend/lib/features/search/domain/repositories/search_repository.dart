import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/search_filters_entity.dart';

/// A single page of search results — the backend's pagination envelope,
/// preserved field for field so the caller never has to infer it.
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

  /// Total matching profiles on the server, not the length of [items].
  final int total;

  /// The server's own answer to "is there another page?" — authoritative, so
  /// the client never computes it from [total] and [page] itself.
  final bool hasMore;
}

/// Server-side profile search.
///
/// `GET /discover/search?q=&page=&limit=`
///
/// Deliberately takes no [SearchFilters]: the endpoint accepts exactly three
/// query parameters — `q`, `page`, `limit` — and silently ignores anything
/// else (the global `ValidationPipe`'s `forbidNonWhitelisted` applies to
/// bodies, not query strings, so extra params are dropped rather than
/// rejected). Sending filter parameters would therefore look like it worked
/// while changing nothing about the result set, which is worse than not
/// sending them. [SearchFilters] is applied client-side over what comes back
/// — see `search_providers.dart`.
abstract interface class SearchRepository {
  Future<SearchResultPage> search({
    required String query,
    int page = 1,
    int limit = 20,
  });
}
