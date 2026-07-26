import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
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
}
