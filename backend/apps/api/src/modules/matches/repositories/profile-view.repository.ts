import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  ProfileView,
} from '../../../../../../libs/database/generated/client';
import { FEED_PROFILE_SELECT, type FeedProfileRow } from './feed.repository';
import { notBlockedWith } from '../../blocks/filters/block-exclusion.builder';
import type { PrismaClientLike } from './shortlist.repository';

/** One distinct viewer plus when they last looked at the profile. */
export interface ProfileViewerRow {
  viewerId: string;
  lastViewedAt: Date;
}

/**
 * Read/write access to the `ProfileView` event log — the data behind "who
 * viewed my profile".
 *
 * The table has existed (and been indexed) since the initial migration but had
 * neither a reader nor a writer; this is both. Deliberately an append-only log
 * rather than an upsert-per-pair: keeping every view leaves "viewed you 3
 * times" answerable later, and [listViewers] collapses repeats down to one row
 * per viewer, which is what the screen shows.
 */
@Injectable()
export class ProfileViewRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Whether the target user is a live account (exists and not soft-deleted). */
  async isTargetAvailable(targetUserId: string): Promise<boolean> {
    const user = await this.prisma.user.findUnique({
      where: { id: targetUserId },
      select: { deletedAt: true },
    });
    return Boolean(user) && !user!.deletedAt;
  }

  async isBlockedBetween(a: string, b: string): Promise<boolean> {
    const count = await this.prisma.userBlock.count({
      where: {
        OR: [
          { blockerId: a, blockedUserId: b },
          { blockerId: b, blockedUserId: a },
        ],
      },
    });
    return count > 0;
  }

  create(
    client: PrismaClientLike,
    viewerId: string,
    viewedUserId: string,
  ): Promise<ProfileView> {
    return client.profileView.create({ data: { viewerId, viewedUserId } });
  }

  /**
   * Whether [viewerId] already viewed [viewedUserId] at or after [since].
   *
   * Drives notification throttling: a member browsing back and forth must not
   * fire a push per visit. The row is still written every time — only the
   * notification is suppressed.
   */
  async hasViewedSince(
    viewerId: string,
    viewedUserId: string,
    since: Date,
  ): Promise<boolean> {
    const count = await this.prisma.profileView.count({
      where: { viewerId, viewedUserId, viewedAt: { gte: since } },
    });
    return count > 0;
  }

  /**
   * Distinct viewers of [viewedUserId], most recently seen first.
   *
   * Uses `groupBy` rather than `findMany({ distinct })` on purpose: Prisma
   * applies `distinct` in the query engine *after* the database has already
   * applied `skip`/`take`, so paginating a distinct findMany silently returns
   * short (or duplicate-collapsed) pages. Grouping pushes both the dedupe and
   * the ordering into SQL, so page N is correct by construction.
   *
   * Viewers with a mutual block are excluded, mirroring how the shortlist list
   * hides blocked members from existing rows and not only from future ones.
   */
  async listViewers(
    viewedUserId: string,
    skip: number,
    take: number,
  ): Promise<[ProfileViewerRow[], number]> {
    const where: Prisma.ProfileViewWhereInput = {
      viewedUserId,
      viewer: { is: notBlockedWith(viewedUserId) },
    };

    const [page, allViewers] = await Promise.all([
      this.prisma.profileView.groupBy({
        by: ['viewerId'],
        where,
        _max: { viewedAt: true },
        orderBy: { _max: { viewedAt: 'desc' } },
        skip,
        take,
      }),
      // Total is a count of distinct VIEWERS, not of raw view events — a raw
      // count would badly overstate the total for a member viewed repeatedly
      // by the same person.
      this.prisma.profileView.groupBy({ by: ['viewerId'], where }),
    ]);

    const rows = page.map((group) => ({
      viewerId: group.viewerId,
      // `_max.viewedAt` is only null for an empty group, which groupBy never
      // returns; the fallback keeps the type honest without inventing a time.
      lastViewedAt: group._max.viewedAt ?? new Date(0),
    }));
    return [rows, allViewers.length];
  }

  findFeedProfilesByUserIds(userIds: string[]): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: FEED_PROFILE_SELECT,
    });
  }
}
