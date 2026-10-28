import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { PaginationQueryDto } from '@app/common';
import type {
  ExpressInterest,
  UserStatus,
} from '../../../../../../libs/database/generated/client';
import { ProfileFeedMapper } from '../../matches/mappers/profile-feed.mapper';
import { NotificationsService } from '../../notifications/services/notifications.service';
import { EmailDispatchService } from '../../notifications/services/email-dispatch.service';
import type { CreateNotificationData } from '../../notifications/repositories/notification.repository';
import { RealtimeGateway } from '../../realtime/realtime.gateway';
import { RealtimeEvents } from '../../realtime/realtime.events';
import { MembershipService } from '../../entitlements/services/membership.service';
import { InterestsRepository } from '../repositories/interests.repository';
import { MatchInterestDto } from '../dto/match-interest.dto';
import {
  InterestListItemDto,
  SendInterestResponseDto,
  interestStatusToWire,
} from '../dto/interest-response.dto';

// A member in any of these states cannot receive interests (mirrors the feed's
// denylist — PENDING_VERIFICATION is deliberately still allowed to be matched).
const NON_RECEIVING_STATUSES = new Set<UserStatus>([
  'SUSPENDED',
  'DEACTIVATED',
  'BANNED',
]);

function isUniqueViolation(error: unknown): boolean {
  return (error as { code?: string })?.code === 'P2002';
}

/**
 * Interest lifecycle owner. Send/respond/withdraw each run their domain write
 * and the resulting notification in ONE Prisma transaction (atomic — a failed
 * notification rolls back the interest and vice versa); the unread-count cache
 * is invalidated only after the transaction commits.
 *
 * Every state transition is guarded to be idempotent and race-safe: the
 * unique `[senderId, receiverId]` constraint plus status-conditional
 * update/delete queries mean concurrent duplicate actions collapse to one
 * winner and a clean 409 for the loser.
 */
@Injectable()
export class InterestsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly interestsRepository: InterestsRepository,
    private readonly notifications: NotificationsService,
    private readonly profileMapper: ProfileFeedMapper,
    private readonly realtime: RealtimeGateway,
    private readonly emailDispatch: EmailDispatchService,
    private readonly membership: MembershipService,
  ) {}

  /** Dispatches the polymorphic `POST /matches/interest` body to send or
   *  respond (see MatchInterestDto). `async` so a bad-body throw surfaces as a
   *  rejected promise, consistent with the send/respond paths. */
  async dispatchMatchInterest(
    userId: string,
    dto: MatchInterestDto,
  ): Promise<SendInterestResponseDto> {
    if (dto.profileId) {
      return this.send(userId, dto.profileId);
    }
    if (dto.interestId && typeof dto.accept === 'boolean') {
      return this.respond(userId, dto.interestId, dto.accept);
    }
    throw new BadRequestException(
      'Provide { profileId } to send an interest, or { interestId, accept } to respond.',
    );
  }

  async send(
    senderId: string,
    receiverId: string,
  ): Promise<SendInterestResponseDto> {
    if (senderId === receiverId) {
      throw new BadRequestException('You cannot send an interest to yourself.');
    }

    // These four eligibility reads are independent — run them in one parallel
    // batch instead of four sequential Neon round trips, then evaluate in the
    // same precedence order (this is the dominant cost of the send latency,
    // and thus of how fast the receiver's real-time event arrives).
    //
    // The sender's plan rides in the same batch when limits are enforced, so
    // the interest quota adds no round trip before the transaction.
    const [
      receiver,
      blocked,
      senderProfileComplete,
      reverseActive,
      senderMembership,
    ] = await Promise.all([
      this.interestsRepository.findReceiverState(receiverId),
      this.interestsRepository.isBlockedBetween(senderId, receiverId),
      this.interestsRepository.isProfileComplete(senderId),
      this.interestsRepository.findReverseActive(senderId, receiverId),
      this.membership.mode === 'enforce'
        ? this.membership.resolve(senderId)
        : undefined,
    ]);

    if (!receiver || receiver.deletedAt) {
      throw new NotFoundException('This member is no longer available.');
    }
    if (NON_RECEIVING_STATUSES.has(receiver.status)) {
      throw new ForbiddenException('This member cannot receive interests.');
    }
    if (blocked) {
      throw new ForbiddenException(
        'You cannot send an interest to this member.',
      );
    }
    if (!senderProfileComplete) {
      throw new ForbiddenException(
        'Complete your profile before sending interests.',
      );
    }
    if (reverseActive) {
      throw new ConflictException(
        'This member has already sent you an interest.',
      );
    }

    let notificationData: CreateNotificationData | undefined;

    try {
      const interest = await this.prisma.$transaction(async (tx) => {
        const existing = await this.interestsRepository.findByPair(
          tx,
          senderId,
          receiverId,
        );

        if (existing && existing.status !== 'DECLINED') {
          throw new ConflictException(
            'You have already sent an interest to this member.',
          );
        }

        // Every real send — a new interest or a re-send after a decline —
        // spends one from the sender's monthly allowance. Charged inside this
        // transaction, so a send that fails for any reason costs nothing.
        await this.membership.consume('interests.send', {
          userId: senderId,
          tx,
          membership: senderMembership,
        });

        // Re-sending after a decline is allowed — reset to PENDING.
        const record: ExpressInterest = existing
          ? await this.interestsRepository.resetToPending(tx, existing.id)
          : await this.interestsRepository.create(tx, senderId, receiverId);

        notificationData = {
          userId: receiverId,
          type: 'INTEREST_RECEIVED',
          title: 'New interest received',
          body: 'Someone has expressed interest in your profile.',
          // `interestId` duplicates `referenceId` under the name the
          // client's deep-link parser looks for first.
          data: {
            actorId: senderId,
            userId: senderId,
            referenceId: record.id,
            interestId: record.id,
          },
        };
        await this.notifications.create(tx, notificationData);

        return record;
      });

      await this.notifications.invalidateUnread(receiverId);
      // Push, like the cache invalidation above, only happens after the
      // transaction has actually committed.
      void this.notifications.dispatchPush(notificationData!);

      // Real-time: signal the receiver's devices to refresh (after commit).
      const at = interest.createdAt.toISOString();
      this.realtime.emitToUser(receiverId, RealtimeEvents.interestCreated, {
        id: interest.id,
        at,
      });
      this.realtime.emitToUser(receiverId, RealtimeEvents.notificationCreated, {
        id: interest.id,
        at,
      });

      return this.toSendResponse(interest);
    } catch (error) {
      // A concurrent create for the same pair loses the unique race — surface
      // the same 409 the sequential path returns.
      if (isUniqueViolation(error)) {
        throw new ConflictException(
          'You have already sent an interest to this member.',
        );
      }
      throw error;
    }
  }

  async respond(
    currentUserId: string,
    interestId: string,
    accept: boolean,
  ): Promise<SendInterestResponseDto> {
    const interest = await this.interestsRepository.findById(interestId);
    if (!interest) {
      throw new NotFoundException('Interest not found.');
    }
    if (interest.receiverId !== currentUserId) {
      throw new ForbiddenException(
        'You can only respond to interests sent to you.',
      );
    }

    const target = accept ? 'ACCEPTED' : 'DECLINED';
    if (interest.status === target) {
      // Idempotent: already in the requested state.
      return this.toSendResponse(interest);
    }
    if (interest.status !== 'PENDING') {
      throw new ConflictException(
        'This interest has already been responded to.',
      );
    }

    let notificationData: CreateNotificationData | undefined;

    await this.prisma.$transaction(async (tx) => {
      const changed = await this.interestsRepository.respondIfPending(
        tx,
        interestId,
        target,
      );
      if (changed === 0) {
        // Lost the race to a concurrent response.
        throw new ConflictException(
          'This interest has already been responded to.',
        );
      }
      notificationData = {
        userId: interest.senderId,
        type: accept ? 'INTEREST_ACCEPTED' : 'INTEREST_DECLINED',
        title: accept ? 'Interest accepted' : 'Interest declined',
        body: accept
          ? 'Your interest was accepted.'
          : 'Your interest was declined.',
        data: {
          actorId: currentUserId,
          userId: currentUserId,
          referenceId: interestId,
          interestId,
        },
      };
      await this.notifications.create(tx, notificationData);
    });

    await this.notifications.invalidateUnread(interest.senderId);
    // Push, like the cache invalidation above, only happens after the
    // transaction has actually committed.
    void this.notifications.dispatchPush(notificationData!);

    // Real-time: tell the original sender's devices their interest was answered.
    const at = new Date().toISOString();
    this.realtime.emitToUser(
      interest.senderId,
      accept
        ? RealtimeEvents.interestAccepted
        : RealtimeEvents.interestRejected,
      { id: interest.id, at },
    );
    this.realtime.emitToUser(
      interest.senderId,
      RealtimeEvents.notificationCreated,
      { id: interest.id, at },
    );

    // Match email — only on acceptance, and only after commit. A declined
    // interest deliberately sends nothing: the in-app notification above is
    // enough, and emailing a rejection would be gratuitous.
    if (accept) {
      void this.emailDispatch
        .sendMatchFound(interest.senderId, currentUserId)
        // EmailDispatchService already swallows its own failures. This is
        // belt-and-braces: an unhandled rejection from a `void`-ed promise
        // terminates the Node process, so the API must not depend on that
        // invariant holding through a future refactor.
        .catch(() => undefined);
    }

    return {
      id: interest.id,
      sentAt: interest.createdAt.toISOString(),
      status: interestStatusToWire(target),
    };
  }

  async withdraw(currentUserId: string, interestId: string): Promise<void> {
    const interest = await this.interestsRepository.findById(interestId);
    if (!interest) {
      throw new NotFoundException('Interest not found.');
    }
    if (interest.senderId !== currentUserId) {
      throw new ForbiddenException('You can only withdraw interests you sent.');
    }
    if (interest.status !== 'PENDING') {
      throw new ConflictException('Only a pending interest can be withdrawn.');
    }

    const removed = await this.interestsRepository.deletePendingSent(
      currentUserId,
      interestId,
    );
    if (removed === 0) {
      // Lost the race to a concurrent withdraw / response.
      throw new NotFoundException('Interest not found.');
    }
  }

  listReceived(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsRepository
      .listReceived(userId, pagination.skip, pagination.take)
      .then(([rows]) => this.toItems(rows, (r) => r.senderId, userId));
  }

  listSent(
    userId: string,
    pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsRepository
      .listSent(userId, pagination.skip, pagination.take)
      .then(([rows]) => this.toItems(rows, (r) => r.receiverId, userId));
  }

  // ── internals ────────────────────────────────────────────────────────────

  private toSendResponse(record: ExpressInterest): SendInterestResponseDto {
    return {
      id: record.id,
      sentAt: record.createdAt.toISOString(),
      status: interestStatusToWire(record.status),
    };
  }

  /** Joins each interest row to its counterpart's public profile card, in one
   *  batched profile query (no N+1). Rows whose counterpart has no finalized
   *  profile are skipped — there's nothing to render. */
  private async toItems(
    rows: ExpressInterest[],
    counterpartOf: (row: ExpressInterest) => string,
    /** The caller, so photo privacy is resolved against THEIR connections. */
    userId: string,
  ): Promise<InterestListItemDto[]> {
    if (rows.length === 0) return [];

    const counterpartIds = [...new Set(rows.map(counterpartOf))];
    const profileRows =
      await this.interestsRepository.findFeedProfilesByUserIds(
        counterpartIds,
        userId,
      );
    const dtos = await this.profileMapper.toDtoList(profileRows);
    const profileByUserId = new Map(dtos.map((dto) => [dto.id, dto]));

    const items: InterestListItemDto[] = [];
    for (const row of rows) {
      const profile = profileByUserId.get(counterpartOf(row));
      if (!profile) continue;
      items.push({
        id: row.id,
        sentAt: row.createdAt.toISOString(),
        status: interestStatusToWire(row.status),
        profile,
      });
    }
    return items;
  }
}
