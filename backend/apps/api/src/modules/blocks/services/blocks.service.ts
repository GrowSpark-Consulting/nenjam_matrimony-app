import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PaginationQueryDto } from '@app/common';
import { BlocksRepository } from '../repositories/blocks.repository';
import { ProfileFeedMapper } from '../../matches/mappers/profile-feed.mapper';
import { BlockedUsersPageDto } from '../dto/blocked-user.response.dto';
import { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';

/**
 * User-level blocking. A block is directional in storage (`blockerId` ->
 * `blockedUserId`) but every consumer (Discover/Search filtering,
 * Interests/Shortlist list filtering, send-interest/send-message guards, chat's
 * own conversation-scoped block check) treats it as mutually disqualifying —
 * see `filters/block-exclusion.builder.ts` and the `isBlockedBetween` checks
 * already in `interests`/`matches`/`chat`.
 *
 * Both operations are idempotent: blocking an already-blocked member or
 * unblocking a member who isn't blocked are both silent no-ops, matching the
 * add/remove semantics already used by ShortlistService.
 */
@Injectable()
export class BlocksService {
  constructor(
    private readonly feedInvalidation: FeedInvalidationService,
    private readonly blocksRepository: BlocksRepository,
    private readonly profileMapper: ProfileFeedMapper,
  ) {}

  async block(userId: string, targetUserId: string): Promise<void> {
    if (userId === targetUserId) {
      throw new BadRequestException('You cannot block yourself.');
    }
    if (!(await this.blocksRepository.isTargetAvailable(targetUserId))) {
      throw new NotFoundException('This member is no longer available.');
    }
    await this.blocksRepository.block(userId, targetUserId);

    // A block changes BOTH feeds — the blocker stops seeing the blocked, and
    // the blocked stops seeing the blocker. Invalidating only the actor would
    // leave the other side's version untouched, so their client would keep
    // believing its feed was current.
    await this.feedInvalidation.invalidatePair(
      userId,
      targetUserId,
      'block_created',
    );
  }

  async unblock(userId: string, targetUserId: string): Promise<void> {
    await this.blocksRepository.unblock(userId, targetUserId);
    await this.feedInvalidation.invalidatePair(
      userId,
      targetUserId,
      'block_removed',
    );
  }

  /** The caller's blocked members as Discover cards, newest-blocked first,
   *  each carrying when the block happened. Rows whose target has no
   *  finalized profile are skipped — there's nothing to render. */
  async listBlocked(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<BlockedUsersPageDto> {
    const { skip, take, pageNumber } = pagination;
    const [rows, total] = await this.blocksRepository.listBlocked(
      userId,
      skip,
      take,
    );
    if (rows.length === 0) {
      return {
        items: [],
        page: pageNumber,
        limit: take,
        total,
        hasMore: false,
      };
    }

    const blockedIds = rows.map((row) => row.blockedUserId);
    const profileRows =
      await this.blocksRepository.findFeedProfilesByUserIds(blockedIds);
    const dtos = await this.profileMapper.toDtoList(profileRows);
    const profileByUserId = new Map(dtos.map((dto) => [dto.id, dto]));

    const items = rows.flatMap((row) => {
      const profile = profileByUserId.get(row.blockedUserId);
      return profile
        ? [
            {
              id: row.blockedUserId,
              blockedAt: row.createdAt.toISOString(),
              profile,
            },
          ]
        : [];
    });

    return {
      items,
      page: pageNumber,
      limit: take,
      total,
      hasMore: skip + rows.length < total,
    };
  }
}
