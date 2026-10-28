import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  PaymentTransaction,
  Prisma,
  SubscriptionEventType,
  SubscriptionStatus,
} from '../../../../../../libs/database/generated/client';

export interface SubscriptionEventInput {
  subscriptionId: string;
  userId: string;
  type: SubscriptionEventType;
  fromStatus?: SubscriptionStatus | null;
  toStatus?: SubscriptionStatus | null;
  actorId?: string | null;
  metadata?: Record<string, unknown>;
}

/** A subscription with the plan tier that scheduling needs. */
export interface ScheduledSubscription {
  id: string;
  endDate: Date;
  tier: number;
}

/**
 * Persistence for subscriptions, payments and their history. DB access only;
 * every state transition is a status-conditional `updateMany` whose `count`
 * says whether THIS caller won it, so concurrent duplicates (a webhook racing
 * the client's verify call) collapse to one winner without explicit locks.
 */
@Injectable()
export class SubscriptionRepository {
  constructor(private readonly prisma: PrismaService) {}

  async recordEvent(
    tx: Prisma.TransactionClient,
    event: SubscriptionEventInput,
  ): Promise<void> {
    await tx.subscriptionEvent.create({
      data: {
        subscriptionId: event.subscriptionId,
        userId: event.userId,
        type: event.type,
        fromStatus: event.fromStatus ?? null,
        toStatus: event.toStatus ?? null,
        actorId: event.actorId ?? null,
        metadata: (event.metadata ?? undefined) as
          Prisma.InputJsonValue | undefined,
      },
    });
  }

  /** [userId]'s ACTIVE subscriptions that haven't ended — in force now or
   *  queued to start later — with their plan tier. */
  async findActiveNotEnded(
    tx: Prisma.TransactionClient,
    userId: string,
    now: Date,
  ): Promise<ScheduledSubscription[]> {
    const rows = await tx.userSubscription.findMany({
      where: { userId, status: 'ACTIVE', endDate: { gt: now } },
      select: { id: true, endDate: true, plan: { select: { tier: true } } },
    });
    return rows.map((row) => ({
      id: row.id,
      endDate: row.endDate,
      tier: row.plan.tier,
    }));
  }

  /** [findActiveNotEnded] outside a transaction — for read models. */
  findHeld(userId: string, now: Date): Promise<ScheduledSubscription[]> {
    return this.findActiveNotEnded(this.prisma, userId, now);
  }

  findPaymentByOrderId(
    tx: Prisma.TransactionClient,
    orderId: string,
  ): Promise<PaymentTransaction | null> {
    return tx.paymentTransaction.findUnique({
      where: { razorpayOrderId: orderId },
    });
  }

  findPaymentByPaymentId(
    tx: Prisma.TransactionClient,
    paymentId: string,
  ): Promise<PaymentTransaction | null> {
    return tx.paymentTransaction.findUnique({
      where: { razorpayPaymentId: paymentId },
    });
  }

  /** The member's purchase history, newest first, with each payment. */
  listHistory(userId: string, take: number) {
    return this.prisma.userSubscription.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take,
      select: {
        id: true,
        status: true,
        startDate: true,
        endDate: true,
        priceInPaise: true,
        currency: true,
        source: true,
        activatedAt: true,
        cancelledAt: true,
        cancellationReason: true,
        createdAt: true,
        plan: { select: { name: true, displayName: true } },
        duration: { select: { months: true } },
        payments: {
          orderBy: { createdAt: 'desc' },
          select: {
            id: true,
            razorpayOrderId: true,
            razorpayPaymentId: true,
            amountInr: true,
            currency: true,
            status: true,
            paidAt: true,
            refundedAmount: true,
            refundedAt: true,
          },
        },
      },
    });
  }

  /** The member's paid plans queued to start after the current one. */
  findScheduled(userId: string, now: Date) {
    return this.prisma.userSubscription.findMany({
      where: { userId, status: 'ACTIVE', startDate: { gt: now } },
      orderBy: { startDate: 'asc' },
      select: {
        id: true,
        startDate: true,
        endDate: true,
        plan: { select: { name: true, displayName: true } },
      },
    });
  }
}
