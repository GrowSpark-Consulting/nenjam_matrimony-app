import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  Gender,
} from '../../../../../../libs/database/generated/client';

// The columns every feed/search card needs. Centralised so the feed query,
// the search query, and the mapper all agree on one row shape.
export const FEED_PROFILE_INCLUDE: Prisma.UserProfileInclude = {
  user: {
    select: {
      phone: true,
      photos: {
        orderBy: [{ isPrimary: 'desc' }, { order: 'asc' }],
        select: { s3Key: true },
      },
    },
  },
};

// A finalized profile row plus the joined user/photos the card needs.
export type FeedProfileRow = Record<string, unknown>;

@Injectable()
export class FeedRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** The caller's own gender (for opposite-gender matching); null if they
   *  haven't finalized a profile yet. */
  async findGender(userId: string): Promise<Gender | null> {
    const row = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: { gender: true },
    });
    return row?.gender ?? null;
  }

  /**
   * Runs the (already-built) dynamic WHERE against user_profiles, newest
   * first, paginated. Count + page share the same WHERE in one transaction so
   * `total`/`hasMore` are always consistent with the returned page.
   */
  async findMatching(
    where: Prisma.UserProfileWhereInput,
    { skip, take }: { skip: number; take: number },
  ): Promise<{ rows: FeedProfileRow[]; total: number }> {
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.userProfile.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
        include: FEED_PROFILE_INCLUDE,
      }),
      this.prisma.userProfile.count({ where }),
    ]);
    return { rows: rows as FeedProfileRow[], total };
  }
}
