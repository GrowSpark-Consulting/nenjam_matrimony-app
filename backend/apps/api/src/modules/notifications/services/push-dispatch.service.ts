import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { FirebaseService } from '@app/firebase';
import type {
  DevicePlatform,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import { NotificationRepository } from '../repositories/notification.repository';

export interface PushPayload {
  title: string;
  body: string;
  /** Arbitrary JSON (e.g. `{ type, actorId, referenceId }`) — flattened to
   *  FCM's string-only data map before sending. */
  data?: Prisma.InputJsonValue;
}

export interface PushDispatchOptions {
  /**
   * Never deliver to a device registered to this user. Chat passes the
   * message's sender here so a sender can never receive a push for their own
   * message — including on a device that is, or once was, registered to both
   * accounts (shared/handed-over phone, account switch), which targeting the
   * recipient's token list alone does not rule out.
   */
  excludeUserId?: string;
}

/**
 * Owns FCM device-token lifecycle (register/unregister/cleanup) and fan-out.
 * Domain services never call FirebaseService directly for push — they go
 * through NotificationsService.create/.dispatchPush the same way they
 * already do for in-app notifications; this service is NotificationsService's
 * push-delivery collaborator.
 */
@Injectable()
export class PushDispatchService {
  private readonly logger = new Logger(PushDispatchService.name);

  constructor(
    private readonly notificationRepository: NotificationRepository,
    private readonly firebase: FirebaseService,
  ) {}

  async registerDevice(
    userId: string,
    fcmToken: string,
    platform: DevicePlatform,
  ): Promise<void> {
    await this.notificationRepository.upsertDeviceToken(
      userId,
      fcmToken,
      platform,
    );
  }

  unregisterDevice(userId: string, fcmToken: string): Promise<void> {
    return this.notificationRepository.deactivateOwnToken(userId, fcmToken);
  }

  /**
   * Sends `payload` to every active device of `userId`, minus any device
   * belonging to `options.excludeUserId` (see {@link PushDispatchOptions}).
   * Best-effort: a push failure is logged, never thrown back to the domain
   * write that triggered it (a member's interest/shortlist action must not
   * fail because FCM is down). Tokens FCM reports as permanently dead are
   * deactivated automatically so they stop being retried.
   */
  async dispatchToUser(
    userId: string,
    payload: PushPayload,
    options: PushDispatchOptions = {},
  ): Promise<void> {
    const { excludeUserId } = options;
    try {
      // Recipient and excluded actor are the same person — there is no one
      // left to notify. Only reachable from a degenerate self-conversation;
      // suppress rather than push someone their own action.
      if (excludeUserId !== undefined && excludeUserId === userId) {
        this.logger.warn(
          `Suppressed push: recipient ${userId} is also the excluded actor.`,
        );
        return;
      }

      const tokens =
        excludeUserId === undefined
          ? await this.notificationRepository.findActiveTokens(userId)
          : await this.notificationRepository.findActiveTokensExcludingUser(
              userId,
              excludeUserId,
            );
      if (tokens.length === 0) return;

      const { invalidTokens } = await this.firebase.sendMulticastPush(
        tokens.map((t) => t.fcmToken),
        { title: payload.title, body: payload.body },
        toStringDataMap(payload.data),
      );

      if (invalidTokens.length > 0) {
        await this.notificationRepository.deactivateTokens(invalidTokens);
      }
    } catch (error) {
      this.logger.error(
        `Push dispatch failed for user ${userId}: ${(error as Error).message}`,
      );
    }
  }

  /** POST /notifications/test — sends a fixed test payload to the caller's
   *  most-recently-registered active device. Unlike [dispatchToUser], this is
   *  a direct diagnostic call so failures ARE surfaced to the caller. */
  async sendTestToLatestDevice(userId: string): Promise<void> {
    const token =
      await this.notificationRepository.findLatestActiveToken(userId);
    if (!token) {
      throw new NotFoundException(
        'No registered device to send a test push to.',
      );
    }

    const { invalidTokens } = await this.firebase.sendMulticastPush(
      [token.fcmToken],
      {
        title: 'Test notification',
        body: 'Push notifications are working.',
      },
      { type: 'SYSTEM' },
    );

    if (invalidTokens.length > 0) {
      await this.notificationRepository.deactivateTokens(invalidTokens);
      throw new NotFoundException(
        'That device token is no longer valid — re-register and try again.',
      );
    }
  }
}

function toStringDataMap(
  data: Prisma.InputJsonValue | undefined,
): Record<string, string> | undefined {
  if (!data || typeof data !== 'object') return undefined;
  const entries = Object.entries(data as Record<string, unknown>)
    .filter(([, value]) => value !== null && value !== undefined)
    .map(([key, value]): [string, string] => [
      key,
      typeof value === 'string' ? value : JSON.stringify(value),
    ]);
  return entries.length > 0 ? Object.fromEntries(entries) : undefined;
}
