import type { FeedProfileRow } from '../repositories/feed.repository';

// DI token for the active search backend. SearchService depends only on this
// interface, so today's PostgresSearchStrategy can later be swapped for an
// ElasticsearchStrategy (query ES for ids → hydrate rows from Postgres) with
// zero change to the service, controller, or Flutter.
export const SEARCH_STRATEGY = Symbol('SEARCH_STRATEGY');

export interface SearchQuery {
  skip: number;
  take: number;
}

export interface SearchResult {
  rows: FeedProfileRow[];
  total: number;
}

export interface SearchStrategy {
  search(
    currentUserId: string,
    q: string,
    query: SearchQuery,
  ): Promise<SearchResult>;
}
