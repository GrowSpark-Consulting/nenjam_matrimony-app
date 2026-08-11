import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { PaginationQueryDto } from '@app/common';
import { ProfileViewerDto } from '../dto/profile-view.dto';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { NotificationsService } from '../../notifications/services/notifications.service';
import type { CreateNotificationData } from '../../notifications/repositories/notification.repository';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { ProfileViewRepository } from '../repositories/profile-view.repository';

/**
 * How long a viewer stays "already counted" for notification purposes.
 *
 * POLICY, not a technical constraint: without it, browsing back and forth
 * between the feed and someone's profile would fire a PROFILE_VIEW push per
 * visit. One notification per viewer per day is the conservative default —
 * raise, lower, or premium-gate it here; nothing else needs to change.
 */
const VIEW_NOTIFICATION_THROTTLE_MS = 24 * 60 * 60 * 1000;

/**
 * "Who viewed my profile" — records view events and serves the viewer list.
 *
 * Mirrors {@link ShortlistService} exactly: the write is idempotent-ish and
 * commits atomically with its notification, blocked relationships are softly
 * skipped rather than erroring, and the list reuses the Discover card shape
 * (ProfileFeedMapper) so viewers render identically to any other profile grid.
 */
@Injectable()
export class ProfileViewService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly profileViewRepository: ProfileViewRepository,
    private readonly notifications: NotificationsService,
    private readonly profileMapper: ProfileFeedMapper,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * Records that [viewerId] opened [viewedUserId]'s profile.
   *
   * The row is always written (it's an event log); the PROFILE_VIEW
   * notification is raised only on the viewer's first view inside
   * {@link VIEW_NOTIFICATION_THROTTLE_MS}. Viewing your own profile, and
   * viewing across a block, are silent no-ops rather than errors — the client
   * fires this on every profile open and must never see it fail for a reason
   * the member can't act on.
   */
  async record(viewerId: string, viewedUserId: string): Promise<void> {
    if (viewerId === viewedUserId) {
      throw new BadRequestException('You cannot view your own profile.');
    }
    if (!(await this.profileViewRepository.isTargetAvailable(viewedUserId))) {
      throw new NotFoundException('This member is no longer available.');
    }
    if (
      await this.profileViewRepository.isBlockedBetween(viewerId, viewedUserId)
    ) {
      return;
    }

    const throttleSince = new Date(Date.now() - VIEW_NOTIFICATION_THROTTLE_MS);
    const alreadyNotified = await this.profileViewRepository.hasViewedSince(
      viewerId,
      viewedUserId,
      throttleSince,
    );

    let notificationData: CreateNotificationData | undefined;

    await this.prisma.$transaction(async (tx) => {
      await this.profileViewRepository.create(tx, viewerId, viewedUserId);
      if (alreadyNotified) return;

      notificationData = {
        userId: viewedUserId,
        type: 'PROFILE_VIEW',
        title: 'Someone viewed your profile',
        body: 'Your profile was viewed. See who is interested.',
        // `userId` duplicates `actorId` under the name the client's
        // deep-link parser reads first — it is the member who did the
        // viewing. There is no reference row worth linking, so the tap
        // opens the Profile Viewers list.
        data: { actorId: viewerId, userId: viewerId },
      };
      await this.notifications.create(tx, notificationData);
    });

    if (!notificationData) return;

    await this.notifications.invalidateUnread(viewedUserId);
    // Push, like the cache invalidation above, only happens after the
    // transaction has actually committed.
    void this.notifications.dispatchPush(notificationData);

    this.realtime.emitToUser(viewedUserId, RealtimeEvents.notificationCreated, {
      id: viewedUserId,
      at: new Date().toISOString(),
    });
  }

  /** Distinct members who viewed [userId], most recently seen first. */
  async listViewers(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<ProfileViewerDto[]> {
    const [rows] = await this.profileViewRepository.listViewers(
      userId,
      pagination.skip,
      pagination.take,
    );
    if (rows.length === 0) return [];

    const viewerIds = rows.map((row) => row.viewerId);
    const profileRows =
      await this.profileViewRepository.findFeedProfilesByUserIds(viewerIds);
    const dtos = await this.profileMapper.toDtoList(profileRows);

    // Preserve most-recent-first order and drop viewers with no finalized
    // profile (a half-registered account can still generate view rows).
    const byUserId = new Map(dtos.map((dto: DiscoverProfileDto) => [dto.id, dto]));
    return rows
      .map((row) => {
        const profile = byUserId.get(row.viewerId);
        return profile
          ? { profile, viewedAt: row.lastViewedAt.toISOString() }
          : undefined;
      })
      .filter((dto): dto is ProfileViewerDto => Boolean(dto));
  }
}
