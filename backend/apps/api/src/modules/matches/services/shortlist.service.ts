import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { PaginationQueryDto } from '@app/common';
import type { Shortlist } from '../../../../../../libs/database/generated/client';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { NotificationsService } from '../../notifications/services/notifications.service';
import type { CreateNotificationData } from '../../notifications/repositories/notification.repository';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { ShortlistRepository } from '../repositories/shortlist.repository';

function isUniqueViolation(error: unknown): boolean {
  return (error as { code?: string })?.code === 'P2002';
}

/**
 * Shortlist (bookmark) management. Add is idempotent and race-safe (unique
 * `[userId, targetUserId]`), and — when it creates a NEW row — raises a
 * SHORTLIST_ADDED notification in the same transaction. Existence checks are
 * O(1) against the unique index. List reuses the Discover card shape
 * (ProfileFeedMapper) so shortlisted profiles render identically to the feed.
 */
@Injectable()
export class ShortlistService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly shortlistRepository: ShortlistRepository,
    private readonly notifications: NotificationsService,
    private readonly profileMapper: ProfileFeedMapper,
    private readonly realtime: RealtimeGateway,
  ) {}

  /** Adds [targetUserId] to [userId]'s shortlist. Idempotent — re-adding an
   *  existing entry is a no-op. Blocked relationships are softly skipped (no
   *  row, no notification) rather than erroring. */
  async add(userId: string, targetUserId: string): Promise<void> {
    if (userId === targetUserId) {
      throw new BadRequestException('You cannot shortlist yourself.');
    }
    if (!(await this.shortlistRepository.isTargetAvailable(targetUserId))) {
      throw new NotFoundException('This member is no longer available.');
    }
    // Soft block validation: never persist/notify across a block, but don't
    // hard-fail the caller's optimistic action either.
    if (await this.shortlistRepository.isBlockedBetween(userId, targetUserId)) {
      return;
    }
    if (await this.shortlistRepository.exists(userId, targetUserId)) {
      return; // already shortlisted — idempotent no-op
    }

    let notificationData: CreateNotificationData | undefined;

    try {
      await this.prisma.$transaction(async (tx) => {
        const created = await this.shortlistRepository.create(
          tx,
          userId,
          targetUserId,
        );
        notificationData = {
          userId: targetUserId,
          type: 'SHORTLIST_ADDED',
          title: 'You were shortlisted',
          body: 'Someone added you to their shortlist.',
          data: { actorId: userId, referenceId: created.id },
        };
        await this.notifications.create(tx, notificationData);
      });
      await this.notifications.invalidateUnread(targetUserId);
      // Push, like the cache invalidation above, only happens after the
      // transaction has actually committed.
      void this.notifications.dispatchPush(notificationData!);

      // Real-time: signal the shortlisted member's devices (after commit).
      const at = new Date().toISOString();
      this.realtime.emitToUser(targetUserId, RealtimeEvents.shortlistCreated, {
        id: targetUserId,
        at,
      });
      this.realtime.emitToUser(
        targetUserId,
        RealtimeEvents.notificationCreated,
        { id: targetUserId, at },
      );
    } catch (error) {
      // Concurrent add lost the unique race — the end state is identical
      // (shortlisted), so treat as a successful no-op.
      if (isUniqueViolation(error)) return;
      throw error;
    }
  }

  /** Removes [targetUserId] from [userId]'s shortlist. Idempotent. */
  async remove(userId: string, targetUserId: string): Promise<void> {
    await this.shortlistRepository.remove(userId, targetUserId);
  }

  /** [userId]'s shortlisted profiles as Discover cards, newest first. */
  async list(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<DiscoverProfileDto[]> {
    const [rows] = await this.shortlistRepository.list(
      userId,
      pagination.skip,
      pagination.take,
    );
    if (rows.length === 0) return [];

    const targetIds = rows.map((row: Shortlist) => row.targetUserId);
    const profileRows =
      await this.shortlistRepository.findFeedProfilesByUserIds(targetIds);
    const dtos = await this.profileMapper.toDtoList(profileRows);

    // Preserve shortlist order (newest first) and drop targets with no
    // finalized profile.
    const byUserId = new Map(dtos.map((dto) => [dto.id, dto]));
    return rows
      .map((row) => byUserId.get(row.targetUserId))
      .filter((dto): dto is DiscoverProfileDto => Boolean(dto));
  }
}
