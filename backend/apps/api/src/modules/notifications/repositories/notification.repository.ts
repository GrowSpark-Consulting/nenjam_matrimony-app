import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  DevicePlatform,
  DevicePushToken,
  Notification,
  NotificationType,
  Prisma,
} from '../../../../../../libs/database/generated/client';

export interface CreateNotificationData {
  userId: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Prisma.InputJsonValue;
}

/** A short display snapshot of a notification's actor, resolved in one batch
 *  query for a whole page (never per-row — avoids N+1). */
export interface ActorSnapshot {
  userId: string;
  firstName: string;
  lastName: string;
  user: { photos: { s3Key: string }[] };
}

/**
 * A Prisma client that is either the base service or an interactive
 * transaction client. Notification creation accepts this so it can run inside
 * a caller's `$transaction` (interest send/respond, shortlist add) and commit
 * atomically with the domain write, or stand alone.
 */
export type PrismaClientLike = PrismaService | Prisma.TransactionClient;

@Injectable()
export class NotificationRepository {
  constructor(private readonly prisma: PrismaService) {}

  create(
    client: PrismaClientLike,
    data: CreateNotificationData,
  ): Promise<Notification> {
    return client.notification.create({
      data: {
        userId: data.userId,
        type: data.type,
        title: data.title,
        body: data.body,
        data: data.data,
      },
    });
  }

  /** One page of a user's notifications, newest first, plus the total — count
   *  and page share one WHERE in a single round trip so they never disagree. */
  listPaginated(
    userId: string,
    skip: number,
    take: number,
  ): Promise<[Notification[], number]> {
    return this.prisma.$transaction([
      this.prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip,
        take,
      }),
      this.prisma.notification.count({ where: { userId } }),
    ]);
  }

  countUnread(userId: string): Promise<number> {
    return this.prisma.notification.count({
      where: { userId, isRead: false },
    });
  }

  /**
   * Marks a single notification read. Scoped by `userId` in the WHERE so a
   * caller can only ever touch their OWN notification (ownership is enforced by
   * the query, not a separate fetch — no horizontal escalation). Returns the
   * number of rows changed: 0 means "not yours / doesn't exist / already read".
   */
  async markOneRead(userId: string, id: string): Promise<number> {
    const result = await this.prisma.notification.updateMany({
      where: { id, userId, isRead: false },
      data: { isRead: true, readAt: new Date() },
    });
    return result.count;
  }

  async markAllRead(userId: string): Promise<number> {
    const result = await this.prisma.notification.updateMany({
      where: { userId, isRead: false },
      data: { isRead: true, readAt: new Date() },
    });
    return result.count;
  }

  /** Distinguishes a genuine 404 (no such notification for this user) from an
   *  already-read no-op on PATCH /:id/read. */
  async existsForUser(userId: string, id: string): Promise<boolean> {
    const count = await this.prisma.notification.count({
      where: { id, userId },
    });
    return count > 0;
  }

  /** Batch-resolves actor display data for a page of notifications in one
   *  query. Only actors with a finalized profile are returned; callers treat a
   *  missing actor as "no actor" (system/verification notices have none). */
  findActorSnapshots(userIds: string[]): Promise<ActorSnapshot[]> {
    if (userIds.length === 0) return Promise.resolve([]);
    return this.prisma.userProfile.findMany({
      where: { userId: { in: userIds } },
      select: {
        userId: true,
        firstName: true,
        lastName: true,
        user: {
          select: {
            photos: {
              orderBy: [{ isPrimary: 'desc' }, { order: 'asc' }],
              take: 1,
              select: { s3Key: true },
            },
          },
        },
      },
    });
  }

  // ── Device push tokens (FCM) ────────────────────────────────────────────

  /** Registers or refreshes a device's FCM token. `fcmToken` is globally
   *  unique, so re-registering the same token — even for a different user,
   *  e.g. a shared/reset device — retargets it rather than erroring, and
   *  reactivates it if it had gone stale. */
  upsertDeviceToken(
    userId: string,
    fcmToken: string,
    platform: DevicePlatform,
  ): Promise<DevicePushToken> {
    return this.prisma.devicePushToken.upsert({
      where: { fcmToken },
      create: { userId, fcmToken, platform, isActive: true },
      update: { userId, platform, isActive: true },
    });
  }

  /** Deactivates one of the caller's own tokens (e.g. on logout). Scoped by
   *  userId in the WHERE so a caller can only ever deactivate their own
   *  device — a missing/foreign token is a silent no-op. */
  async deactivateOwnToken(userId: string, fcmToken: string): Promise<void> {
    await this.prisma.devicePushToken.updateMany({
      where: { userId, fcmToken },
      data: { isActive: false },
    });
  }

  /** Marks tokens FCM reported as permanently dead so they're never retried.
   *  Not scoped by user — the token value alone identifies the dead row. */
  async deactivateTokens(fcmTokens: string[]): Promise<void> {
    if (fcmTokens.length === 0) return;
    await this.prisma.devicePushToken.updateMany({
      where: { fcmToken: { in: fcmTokens } },
      data: { isActive: false },
    });
  }

  findActiveTokens(userId: string): Promise<DevicePushToken[]> {
    return this.prisma.devicePushToken.findMany({
      where: { userId, isActive: true },
    });
  }

  /**
   * Active tokens for `userId`, minus every device registered to
   * `excludeUserId`. Used by push dispatch to guarantee an actor is never
   * pushed their own action (chat: the sender).
   *
   * The exclusion set is deliberately NOT filtered by `isActive`: an inactive
   * row still identifies a physical device belonging to `excludeUserId` (e.g.
   * one they logged out of), and that device must stay excluded even if the
   * same token later reappears under the recipient. `fcmToken` is globally
   * unique, so the two sets can only overlap when a single device has been
   * retargeted between the two accounts — exactly the case a plain
   * `findActiveTokens(recipient)` cannot see.
   */
  async findActiveTokensExcludingUser(
    userId: string,
    excludeUserId: string,
  ): Promise<DevicePushToken[]> {
    const [tokens, excluded] = await Promise.all([
      this.prisma.devicePushToken.findMany({
        where: { userId, isActive: true },
      }),
      this.prisma.devicePushToken.findMany({
        where: { userId: excludeUserId },
        select: { fcmToken: true },
      }),
    ]);
    if (excluded.length === 0) return tokens;

    const excludedTokens = new Set(excluded.map((t) => t.fcmToken));
    return tokens.filter((t) => !excludedTokens.has(t.fcmToken));
  }

  /** Display name for a notification/push title. `null` when the user has no
   *  finalized profile — callers fall back to a generic title rather than
   *  showing an empty one. */
  async findDisplayName(userId: string): Promise<string | null> {
    const profile = await this.prisma.userProfile.findFirst({
      where: { userId },
      select: { firstName: true, lastName: true },
    });
    if (!profile) return null;
    const name = `${profile.firstName ?? ''} ${profile.lastName ?? ''}`.trim();
    return name.length > 0 ? name : null;
  }

  /** Most-recently-registered active device — used by POST /notifications/test. */
  findLatestActiveToken(userId: string): Promise<DevicePushToken | null> {
    return this.prisma.devicePushToken.findFirst({
      where: { userId, isActive: true },
      orderBy: { updatedAt: 'desc' },
    });
  }
}
