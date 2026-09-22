import { Injectable } from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { buildFeedWhere } from '../filters/partner-preference-where.builder';
import { FeedRepository } from '../repositories/feed.repository';
import { PreferenceRepository } from '../repositories/preference.repository';
import { SearchQuery, SearchResult, SearchStrategy } from './search.strategy';

/**
 * Interim search backend: case-insensitive PostgreSQL `contains` across the
 * text fields, reusing [FeedRepository.findMatching] so pagination + row shape
 * exactly match the feed. Fully verifiable today (no external infra).
 *
 * Shares [buildFeedWhere] with the Discover feed so search results are subject
 * to the exact same rules — opposite-gender matching, saved partner
 * preferences, and invalid-profile exclusion (deleted/suspended/blocked/
 * incomplete) — rather than a separately hand-rolled, weaker filter.
 *
 * When Elasticsearch is running, an ElasticsearchStrategy binds to the same
 * SEARCH_STRATEGY token instead — it would query ES for matching ids and
 * hydrate the rows from Postgres — and nothing else changes.
 */
@Injectable()
export class PostgresSearchStrategy implements SearchStrategy {
  private static readonly TEXT_FIELDS: Array<
    keyof Prisma.UserProfileWhereInput
  > = [
    'firstName',
    'lastName',
    'profession',
    'highestEducation',
    'currentCity',
    'currentState',
    'country',
    'religion',
    'motherTongue',
    'bio',
  ];

  constructor(
    private readonly feedRepository: FeedRepository,
    private readonly preferenceRepository: PreferenceRepository,
  ) {}

  async search(
    currentUserId: string,
    q: string,
    { skip, take }: SearchQuery,
  ): Promise<SearchResult> {
    const term = q.trim();

    const [self, pref] = await Promise.all([
      this.feedRepository.findSelf(currentUserId),
      this.preferenceRepository.findByUserId(currentUserId),
    ]);

    const where = buildFeedWhere({
      currentUserId,
      myGender: self?.gender ?? null,
      self,
      pref,
    });

    if (term.length > 0) {
      const and = where.AND as Prisma.UserProfileWhereInput[];
      and.push({
        OR: PostgresSearchStrategy.TEXT_FIELDS.map(
          (field) =>
            ({
              [field]: { contains: term, mode: 'insensitive' },
            }) as Prisma.UserProfileWhereInput,
        ),
      });
    }

    return this.feedRepository.findMatching(
      where,
      { skip, take },
      currentUserId,
    );
  }
}
