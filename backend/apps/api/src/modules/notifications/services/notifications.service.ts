import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { S3Service } from '@app/storage';
import { RedisService } from '@app/cache';
import { PaginationQueryDto } from '@app/common';
import type { Notification } from '../../../../../../libs/database/generated/client';
import {
  ActorSnapshot,
  CreateNotificationData,
  NotificationRepository,
  PrismaClientLike,
} from '../repositories/notification.repository';
import {
  NotificationActorDto,
  NotificationItemDto,
  NotificationsPageDto,
} from '../dto/notification-response.dto';
import { PushDispatchService } from './push-dispatch.service';

// Unread-count cache: keyed per user, short TTL as a backstop so a missed
// invalidation self-heals quickly. Invalidated eagerly on every event that
// changes the count (new notification, mark-read, mark-all-read).
const UNREAD_CACHE_TTL_SECONDS = 300;
const unreadCacheKey = (userId: string): string => `notif:unread:${userId}`;

/**
 * Notification center backend. Other modules (Interests, Shortlist) create
 * notifications through [create] — passing their own Prisma transaction client
 * so the notification commits atomically with the domain write — then call
 * [invalidateUnread] after the transaction commits.
 *
 * Reads are optimized for the notification bell/list: the unread count is Redis
 * cached (the most frequently polled value), and the list resolves all actor
 * avatars for a page in one batched query (never per-row).
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly notificationRepository: NotificationRepository,
    private readonly redis: RedisService,
    private readonly s3: S3Service,
    private readonly pushDispatch: PushDispatchService,
  ) {}

  /**
   * Persists a notification using the supplied Prisma client — pass a
   * transaction client to make it atomic with the caller's domain write. Cache
   * invalidation is deliberately NOT done here (a transaction can roll back
   * after this line); the caller invalidates via [invalidateUnread] once
   * committed. Push delivery follows the identical rule — see [dispatchPush].
   */
  create(
    client: PrismaClientLike,
    data: CreateNotificationData,
  ): Promise<Notification> {
    return this.notificationRepository.create(client, data);
  }

  /**
   * Sends `data` as a push notification to every active device of
   * `data.userId`. Call this AFTER the transaction that [create]d the
   * matching in-app notification has committed — same rule as
   * [invalidateUnread], and for the same reason: a transaction can still roll
   * back, and a rolled-back write must never reach a device as a push. Never
   * throws (best-effort — see PushDispatchService.dispatchToUser).
   */
  async dispatchPush(data: CreateNotificationData): Promise<void> {
    const payloadData = {
      type: data.type,
      ...((data.data as Record<string, unknown> | undefined) ?? {}),
    };
    await this.pushDispatch.dispatchToUser(data.userId, {
      title: data.title,
      body: data.body,
      data: payloadData,
    });
  }

  async list(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<NotificationsPageDto> {
    const { skip, take, pageNumber } = pagination;
    const [rows, total] = await this.notificationRepository.listPaginated(
      userId,
      skip,
      take,
    );

    const actorsById = await this.resolveActors(rows);

    const items = rows.map((row) => this.toItem(row, actorsById));

    return {
      items,
      page: pageNumber,
      limit: take,
      total,
      hasMore: skip + rows.length < total,
    };
  }

  /** Redis-cached unread count. Fail-open: a Redis miss/outage falls back to
   *  the authoritative DB count and never blocks the request. */
  async getUnreadCount(userId: string): Promise<number> {
    const cached = await this.readCachedUnread(userId);
    if (cached !== null) return cached;

    const count = await this.notificationRepository.countUnread(userId);
    await this.writeCachedUnread(userId, count);
    return count;
  }

  /** Marks one notification read (ownership enforced in the repository WHERE).
   *  Idempotent: marking an already-read or non-existent-for-this-user id is a
   *  no-op. Throws NotFound only when the id doesn't belong to the user at all
   *  so the client can distinguish that from "already read". */
  async markRead(userId: string, id: string): Promise<void> {
    const changed = await this.notificationRepository.markOneRead(userId, id);
    if (changed > 0) {
      await this.invalidateUnread(userId);
      return;
    }
    // 0 rows changed — either already read (fine, no-op) or not the user's.
    const exists = await this.notificationRepository.existsForUser(userId, id);
    if (!exists) {
      throw new NotFoundException('Notification not found.');
    }
  }

  async markAllRead(userId: string): Promise<void> {
    await this.notificationRepository.markAllRead(userId);
    // The count is now zero — set it directly rather than deleting, so the
    // next read is a cache hit instead of a DB recount.
    await this.writeCachedUnread(userId, 0);
  }

  /** Call AFTER a transaction that created a notification commits, so the next
   *  unread-count read recomputes. Best-effort. */
  async invalidateUnread(userId: string): Promise<void> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return;
    try {
      await client.del(unreadCacheKey(userId));
    } catch (error) {
      this.logger.warn(
        `Failed to invalidate unread cache for ${userId}: ${(error as Error).message}`,
      );
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  private async resolveActors(
    rows: Notification[],
  ): Promise<Map<string, NotificationActorDto>> {
    const actorIds = [
      ...new Set(
        rows
          .map((row) => this.actorIdOf(row))
          .filter((id): id is string => Boolean(id)),
      ),
    ];
    if (actorIds.length === 0) return new Map();

    const snapshots =
      await this.notificationRepository.findActorSnapshots(actorIds);

    const entries = await Promise.all(
      snapshots.map(async (snap): Promise<[string, NotificationActorDto]> => [
        snap.userId,
        {
          id: snap.userId,
          name: `${snap.firstName ?? ''} ${snap.lastName ?? ''}`.trim(),
          photoUrl: await this.presignActorPhoto(snap),
        },
      ]),
    );
    return new Map(entries);
  }

  private async presignActorPhoto(snap: ActorSnapshot): Promise<string | null> {
    const key = snap.user?.photos?.[0]?.s3Key;
    if (!key || !this.s3.isConfigured()) return null;
    try {
      return await this.s3.getPresignedGetUrl(key);
    } catch {
      return null;
    }
  }

  private toItem(
    row: Notification,
    actorsById: Map<string, NotificationActorDto>,
  ): NotificationItemDto {
    const data = (row.data ?? {}) as Record<string, unknown>;
    const actorId = this.actorIdOf(row);
    const referenceId =
      typeof data.referenceId === 'string' ? data.referenceId : null;

    return {
      id: row.id,
      type: row.type,
      title: row.title,
      message: row.body,
      isRead: row.isRead,
      createdAt: row.createdAt.toISOString(),
      actor: actorId ? (actorsById.get(actorId) ?? null) : null,
      referenceId,
      metadata: data,
    };
  }

  private actorIdOf(row: Notification): string | null {
    const data = (row.data ?? {}) as Record<string, unknown>;
    return typeof data.actorId === 'string' ? data.actorId : null;
  }

  private async readCachedUnread(userId: string): Promise<number | null> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return null;
    try {
      const raw = await client.get(unreadCacheKey(userId));
      if (raw === null) return null;
      const n = Number(raw);
      return Number.isFinite(n) ? n : null;
    } catch {
      return null;
    }
  }

  private async writeCachedUnread(
    userId: string,
    count: number,
  ): Promise<void> {
    const client = this.redis.getClient();
    if (client.status !== 'ready') return;
    try {
      await client.set(
        unreadCacheKey(userId),
        String(count),
        'EX',
        UNREAD_CACHE_TTL_SECONDS,
      );
    } catch {
      // Non-fatal — the next read just recomputes from the DB.
    }
  }
}
