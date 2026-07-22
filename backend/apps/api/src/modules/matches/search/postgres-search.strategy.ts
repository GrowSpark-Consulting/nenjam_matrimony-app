import { Injectable } from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { FeedRepository } from '../repositories/feed.repository';
import {
  SearchQuery,
  SearchResult,
  SearchStrategy,
} from './search.strategy';

/**
 * Interim search backend: case-insensitive PostgreSQL `contains` across the
 * text fields, reusing [FeedRepository.findMatching] so pagination + row shape
 * exactly match the feed. Fully verifiable today (no external infra).
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

  constructor(private readonly feedRepository: FeedRepository) {}

  search(
    currentUserId: string,
    q: string,
    { skip, take }: SearchQuery,
  ): Promise<SearchResult> {
    const term = q.trim();

    const and: Prisma.UserProfileWhereInput[] = [
      { userId: { not: currentUserId } },
      { user: { is: { deletedAt: null } } },
    ];

    if (term.length > 0) {
      and.push({
        OR: PostgresSearchStrategy.TEXT_FIELDS.map(
          (field) =>
            ({
              [field]: { contains: term, mode: 'insensitive' },
            }) as Prisma.UserProfileWhereInput,
        ),
      });
    }

    return this.feedRepository.findMatching({ AND: and }, { skip, take });
  }
}
