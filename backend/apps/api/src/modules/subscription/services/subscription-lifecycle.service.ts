import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService, expireLapsedSubscriptions } from '@app/database';
import type {
  Prisma,
  SubscriptionPlanName,
} from '../../../../../../libs/database/generated/client';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { SubscriptionRepository } from '../repositories/subscription.repository';
import { assertAdminPermission } from '../domain/admin-permission';
import { windowFor, type PlanWindow } from '../domain/schedule';

const DAY_MS = 24 * 60 * 60 * 1000;

export type ActivationOutcome =
  | 'ACTIVATED'
  /** This payment was already applied (duplicate webhook / verify race). */
  | 'ALREADY_APPLIED'
  /** The provider reported a different amount — never activated. */
  | 'AMOUNT_MISMATCH'
  /** The payment was refunded (the refund overtook the capture) — never
   *  activated. */
  | 'REFUNDED'
  /** No payment row for this order: not one of ours. */
  | 'UNKNOWN_ORDER'
  /** Paid, but the subscription had left PENDING (e.g. revoked) — needs a
   *  human; logged as an error. */
  | 'PAID_NOT_ACTIVATED';

export interface PaymentConfirmation {
  orderId: string;
  paymentId: string;
  /** What the provider says was captured, in paise — from the webhook body
   *  or, on the verify path, from Razorpay's own payment record (never from
   *  the client). Checked against the amount fixed at checkout. */
  amountInPaise: number;
  currency: string;
  /** The member (verify) or null (webhook). */
  actorId: string | null;
  via: 'CHECKOUT_VERIFY' | 'WEBHOOK';
}

export interface AdminActor {
  /** The administrator's user id — recorded on every event and audit row. */
  actorId: string;
  /** Why; mandatory for every lifecycle exception. */
  reason: string;
}

/**
 * The subscription state machine — the only code that changes a
 * subscription's status.
 *
 *   PENDING ──paid──▶ ACTIVE ──end date──▶ EXPIRED
 *      │                 │
 *      │                 ├─refund / admin revoke──▶ CANCELLED
 *      │                 └─member cancels──▶ ACTIVE until end date (no renewal)
 *      ├─payment failed──▶ stays PENDING (Razorpay allows a retry on the
 *      │                   same order); a later success still activates it
 *      └─fully refunded before its capture was seen──▶ CANCELLED (never
 *                          activates, whatever arrives later)
 *
 * Scheduling on activation: an UPGRADE (a higher tier than anything the
 * member has) starts now, overlapping the lower plan, which resumes if it
 * outlives the upgrade. A RENEWAL or DOWNGRADE is queued to start when the
 * member's last same-or-higher plan ends. Nothing already bought is shortened
 * and no proration is computed.
 *
 * Every transition writes a SubscriptionEvent in the same transaction, and
 * admin exceptions also an AuditLog row.
 */
@Injectable()
export class SubscriptionLifecycleService {
  private readonly logger = new Logger(SubscriptionLifecycleService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly repository: SubscriptionRepository,
    private readonly catalog: PlanCatalogService,
  ) {}

  /** When a new plan of [tier] lasting [termMs] would run for [userId] —
   *  the shared rule in domain/schedule.ts. */
  async scheduleWindow(
    tx: Prisma.TransactionClient,
    userId: string,
    tier: number,
    termMs: number,
    now: Date,
  ): Promise<PlanWindow> {
    const held = await this.repository.findActiveNotEnded(tx, userId, now);
    return windowFor(held, tier, termMs, now);
  }

  /**
   * Apply a confirmed payment: mark it paid and activate its subscription.
   * Idempotent and race-safe — the client's verify call and any number of
   * webhook deliveries for the same order activate it exactly once.
   */
  async confirmPayment(
    tx: Prisma.TransactionClient,
    input: PaymentConfirmation,
    now: Date = new Date(),
  ): Promise<ActivationOutcome> {
    const payment = await this.repository.findPaymentByOrderId(
      tx,
      input.orderId,
    );
    if (!payment) return 'UNKNOWN_ORDER';
    // A refund that overtook the capture already closed this purchase.
    if (payment.status === 'REFUNDED') return 'REFUNDED';

    if (
      input.amountInPaise !== payment.amountInr ||
      input.currency !== payment.currency
    ) {
      await tx.paymentTransaction.updateMany({
        where: { id: payment.id, status: 'PENDING' },
        data: { status: 'FAILED', failureReason: 'AMOUNT_MISMATCH' },
      });
      this.logger.error(
        `Payment for order ${input.orderId} reported ${input.amountInPaise} ${input.currency ?? ''}, expected ${payment.amountInr} ${payment.currency} — NOT activated.`,
      );
      return 'AMOUNT_MISMATCH';
    }

    // The latch: only one caller can move this payment to SUCCESS. A payment
    // that failed and was retried on the same order may still succeed — but
    // never one flagged for an amount mismatch.
    const { count } = await tx.paymentTransaction.updateMany({
      where: {
        id: payment.id,
        OR: [
          { status: 'PENDING' },
          { status: 'FAILED', failureReason: { not: 'AMOUNT_MISMATCH' } },
        ],
      },
      data: {
        status: 'SUCCESS',
        razorpayPaymentId: input.paymentId,
        paidAt: now,
        failureReason: null,
      },
    });
    if (count === 0) return 'ALREADY_APPLIED';

    const subscription = await tx.userSubscription.findUnique({
      where: { id: payment.subscriptionId },
      include: { plan: { select: { tier: true, name: true } } },
    });
    if (!subscription || subscription.status !== 'PENDING') {
      this.logger.error(
        `Order ${input.orderId} was paid but subscription ${payment.subscriptionId} is ${subscription?.status ?? 'missing'} — needs manual review.`,
      );
      return 'PAID_NOT_ACTIVATED';
    }

    // The term was fixed at checkout (provisional start → end), so a price
    // list edited after checkout can't change what this payment bought.
    const termMs =
      subscription.endDate.getTime() - subscription.startDate.getTime();
    const window = await this.scheduleWindow(
      tx,
      subscription.userId,
      subscription.plan.tier,
      termMs,
      now,
    );
    await tx.userSubscription.update({
      where: { id: subscription.id },
      data: {
        status: 'ACTIVE',
        startDate: window.startDate,
        endDate: window.endDate,
        activatedAt: now,
      },
    });
    await this.repository.recordEvent(tx, {
      subscriptionId: subscription.id,
      userId: subscription.userId,
      type: 'ACTIVATED',
      fromStatus: 'PENDING',
      toStatus: 'ACTIVE',
      actorId: input.actorId,
      metadata: {
        orderId: input.orderId,
        paymentId: input.paymentId,
        via: input.via,
        plan: subscription.plan.name,
        startDate: window.startDate.toISOString(),
        endDate: window.endDate.toISOString(),
        scheduled: window.scheduled,
      },
    });
    return 'ACTIVATED';
  }

  /** A failed payment attempt. Grants nothing and changes no access; the
   *  subscription stays PENDING so a retry on the same order can succeed. */
  async recordPaymentFailure(
    tx: Prisma.TransactionClient,
    input: { orderId: string; paymentId?: string; reason: string },
  ): Promise<'RECORDED' | 'UNKNOWN_ORDER' | 'NOT_PENDING'> {
    const payment = await this.repository.findPaymentByOrderId(
      tx,
      input.orderId,
    );
    if (!payment) return 'UNKNOWN_ORDER';
    const { count } = await tx.paymentTransaction.updateMany({
      where: { id: payment.id, status: 'PENDING' },
      data: { status: 'FAILED', failureReason: input.reason.slice(0, 500) },
    });
    if (count === 0) return 'NOT_PENDING';
    await this.repository.recordEvent(tx, {
      subscriptionId: payment.subscriptionId,
      userId: payment.userId,
      type: 'PAYMENT_FAILED',
      fromStatus: 'PENDING',
      toStatus: 'PENDING',
      metadata: {
        orderId: input.orderId,
        paymentId: input.paymentId ?? null,
        reason: input.reason.slice(0, 500),
      },
    });
    return 'RECORDED';
  }

  /**
   * A processed refund. Partial refunds accumulate and change no access; the
   * refund that makes the total reach the amount paid marks the payment
   * REFUNDED and ends the subscription immediately (CANCELLED).
   *
   * Webhooks are not delivered in order, so a refund can arrive before the
   * capture it refunds. It is still applied: the payment is found by its
   * order, and a fully refunded purchase is closed before it was ever
   * activated — the late capture then finds it REFUNDED and does nothing.
   */
  async recordRefund(
    tx: Prisma.TransactionClient,
    input: {
      paymentId: string;
      orderId?: string;
      refundId: string;
      amountInPaise: number;
    },
    now: Date = new Date(),
  ): Promise<'FULL' | 'PARTIAL' | 'UNKNOWN_PAYMENT'> {
    const payment =
      (await this.repository.findPaymentByPaymentId(tx, input.paymentId)) ??
      (input.orderId
        ? await this.repository.findPaymentByOrderId(tx, input.orderId)
        : null);
    if (!payment) return 'UNKNOWN_PAYMENT';
    const beforeCapture = payment.status !== 'SUCCESS';

    const updated = await tx.paymentTransaction.update({
      where: { id: payment.id },
      data: {
        refundedAmount: { increment: input.amountInPaise },
        // Record which payment was refunded if the capture hasn't yet.
        ...(payment.razorpayPaymentId === null && {
          razorpayPaymentId: input.paymentId,
        }),
      },
      select: { refundedAmount: true, amountInr: true },
    });
    const full = updated.refundedAmount >= updated.amountInr;
    const metadata = {
      paymentId: input.paymentId,
      refundId: input.refundId,
      amountInPaise: input.amountInPaise,
      refundedTotal: updated.refundedAmount,
      beforeCapture,
    };
    if (!full) {
      await this.repository.recordEvent(tx, {
        subscriptionId: payment.subscriptionId,
        userId: payment.userId,
        type: 'PARTIALLY_REFUNDED',
        metadata,
      });
      return 'PARTIAL';
    }

    await tx.paymentTransaction.updateMany({
      where: { id: payment.id, status: { not: 'REFUNDED' } },
      data: { status: 'REFUNDED', refundedAt: now },
    });
    const before = await tx.userSubscription.findUnique({
      where: { id: payment.subscriptionId },
      select: { status: true },
    });
    // ACTIVE (access ends now) or still PENDING (refunded before capture —
    // it must never activate later).
    const { count } = await tx.userSubscription.updateMany({
      where: {
        id: payment.subscriptionId,
        status: { in: ['ACTIVE', 'PENDING'] },
      },
      data: {
        status: 'CANCELLED',
        cancelledAt: now,
        cancellationReason: 'REFUNDED',
        autoRenew: false,
      },
    });
    await this.repository.recordEvent(tx, {
      subscriptionId: payment.subscriptionId,
      userId: payment.userId,
      type: 'REFUNDED',
      fromStatus: count === 1 ? (before?.status ?? null) : null,
      toStatus: count === 1 ? 'CANCELLED' : null,
      metadata,
    });
    return 'FULL';
  }

  /**
   * The member stops their plan from renewing. Access is NOT cut: every paid
   * plan keeps running to its end date (one-time purchases are never
   * refunded by cancelling). Idempotent.
   */
  async cancelAtPeriodEnd(
    userId: string,
    now: Date = new Date(),
  ): Promise<{ cancelled: number; accessUntil: Date }> {
    return this.prisma.$transaction(async (tx) => {
      const rows = await tx.userSubscription.findMany({
        where: { userId, status: 'ACTIVE', endDate: { gt: now } },
        select: { id: true, endDate: true, cancelledAt: true },
      });
      if (rows.length === 0) {
        throw new NotFoundException('You have no active paid plan to cancel.');
      }
      let cancelled = 0;
      for (const row of rows.filter((r) => r.cancelledAt === null)) {
        const { count } = await tx.userSubscription.updateMany({
          where: { id: row.id, cancelledAt: null },
          data: {
            autoRenew: false,
            cancelledAt: now,
            cancellationReason: 'MEMBER_REQUEST',
          },
        });
        if (count === 0) continue;
        cancelled += 1;
        await this.repository.recordEvent(tx, {
          subscriptionId: row.id,
          userId,
          type: 'CANCELLED_AT_PERIOD_END',
          fromStatus: 'ACTIVE',
          toStatus: 'ACTIVE',
          actorId: userId,
          metadata: { accessUntil: row.endDate.toISOString() },
        });
      }
      const accessUntil = rows.reduce(
        (latest, r) => (r.endDate > latest ? r.endDate : latest),
        rows[0].endDate,
      );
      return { cancelled, accessUntil };
    });
  }

  /** Marks lapsed ACTIVE subscriptions EXPIRED (bookkeeping only — access
   *  already stopped at endDate). Shared with the scheduler's cron. */
  expireLapsed(now: Date = new Date(), batchSize = 500): Promise<number> {
    return expireLapsedSubscriptions(this.prisma, now, batchSize);
  }

  // ── Administrative lifecycle exceptions (no HTTP surface yet) ────────────
  // For the future admin panel: each requires an actor who is an ACTIVE admin
  // holding the permission (checked here, inside the transaction — a missing
  // controller guard can't skip it), a reason, and writes a SubscriptionEvent
  // and an AuditLog row in that same transaction.

  /** Give a member a plan without payment (compensation, testing, support). */
  async grant(
    input: AdminActor & {
      userId: string;
      planCode: SubscriptionPlanName;
      days: number;
    },
    now: Date = new Date(),
  ): Promise<{ subscriptionId: string; startDate: Date; endDate: Date }> {
    this.assertReason(input.reason);
    if (!Number.isInteger(input.days) || input.days < 1 || input.days > 3660) {
      throw new BadRequestException(
        'days must be a whole number from 1 to 3660.',
      );
    }
    const plan = await this.catalog.findPlan(input.planCode);
    if (!plan || plan.code === 'FREE') {
      throw new BadRequestException('Only a paid plan can be granted.');
    }
    const version = this.catalog.versionEffectiveAt(plan, now);
    if (!version) {
      throw new BadRequestException(
        `${plan.name} has no entitlement version in force.`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, {
        module: 'subscriptions',
        action: 'write',
      });
      const member = await tx.user.findUnique({
        where: { id: input.userId },
        select: { deletedAt: true },
      });
      if (!member || member.deletedAt !== null) {
        throw new NotFoundException('No member with that id.');
      }
      const window = await this.scheduleWindow(
        tx,
        input.userId,
        plan.tier,
        input.days * DAY_MS,
        now,
      );
      const created = await tx.userSubscription.create({
        data: {
          userId: input.userId,
          planId: plan.id,
          planVersionId: version.id,
          status: 'ACTIVE',
          startDate: window.startDate,
          endDate: window.endDate,
          activatedAt: now,
          priceInPaise: 0,
          currency: 'INR',
          source: 'ADMIN_GRANT',
        },
      });
      const metadata = {
        plan: plan.code,
        days: input.days,
        reason: input.reason,
      };
      await this.repository.recordEvent(tx, {
        subscriptionId: created.id,
        userId: input.userId,
        type: 'GRANTED',
        toStatus: 'ACTIVE',
        actorId: input.actorId,
        metadata,
      });
      await this.audit(
        tx,
        input.actorId,
        'membership.subscription.grant',
        created.id,
        {
          userId: input.userId,
          ...metadata,
        },
      );
      return {
        subscriptionId: created.id,
        startDate: window.startDate,
        endDate: window.endDate,
      };
    });
  }

  /**
   * Push an ACTIVE subscription's end date out by [days]. Plans of the same
   * or a lower tier queued to start when it ended move back by the same
   * [days], so the extension doesn't silently overlap — and use up — a
   * renewal the member already paid for.
   */
  async extend(
    input: AdminActor & { subscriptionId: string; days: number },
  ): Promise<{ endDate: Date; shiftedQueued: number }> {
    this.assertReason(input.reason);
    if (!Number.isInteger(input.days) || input.days < 1 || input.days > 3660) {
      throw new BadRequestException(
        'days must be a whole number from 1 to 3660.',
      );
    }
    return this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, {
        module: 'subscriptions',
        action: 'write',
      });
      const subscription = await tx.userSubscription.findUnique({
        where: { id: input.subscriptionId },
        include: { plan: { select: { tier: true } } },
      });
      if (!subscription || subscription.status !== 'ACTIVE') {
        throw new NotFoundException('No active subscription with that id.');
      }
      const shiftMs = input.days * DAY_MS;
      const endDate = new Date(subscription.endDate.getTime() + shiftMs);
      await tx.userSubscription.update({
        where: { id: subscription.id },
        data: { endDate },
      });

      const queued = await tx.userSubscription.findMany({
        where: {
          userId: subscription.userId,
          status: 'ACTIVE',
          id: { not: subscription.id },
          startDate: { gte: subscription.endDate },
          plan: { tier: { lte: subscription.plan.tier } },
        },
        select: { id: true, startDate: true, endDate: true },
      });
      for (const next of queued) {
        await tx.userSubscription.update({
          where: { id: next.id },
          data: {
            startDate: new Date(next.startDate.getTime() + shiftMs),
            endDate: new Date(next.endDate.getTime() + shiftMs),
          },
        });
        await this.repository.recordEvent(tx, {
          subscriptionId: next.id,
          userId: subscription.userId,
          type: 'EXTENDED',
          actorId: input.actorId,
          metadata: {
            shiftedBehind: subscription.id,
            days: input.days,
            reason: input.reason,
          },
        });
      }

      const metadata = {
        days: input.days,
        previousEndDate: subscription.endDate.toISOString(),
        endDate: endDate.toISOString(),
        shiftedQueued: queued.map((q) => q.id),
        reason: input.reason,
      };
      await this.repository.recordEvent(tx, {
        subscriptionId: subscription.id,
        userId: subscription.userId,
        type: 'EXTENDED',
        actorId: input.actorId,
        metadata,
      });
      await this.audit(
        tx,
        input.actorId,
        'membership.subscription.extend',
        subscription.id,
        metadata,
      );
      return { endDate, shiftedQueued: queued.length };
    });
  }

  /** End an ACTIVE subscription now. Does not refund — a refund goes through
   *  the payment provider and arrives as its webhook. */
  async revoke(
    input: AdminActor & { subscriptionId: string },
    now: Date = new Date(),
  ): Promise<void> {
    this.assertReason(input.reason);
    await this.prisma.$transaction(async (tx) => {
      await assertAdminPermission(tx, input.actorId, {
        module: 'subscriptions',
        action: 'cancel',
      });
      const subscription = await tx.userSubscription.findUnique({
        where: { id: input.subscriptionId },
        select: { id: true, userId: true },
      });
      if (!subscription) {
        throw new NotFoundException('No subscription with that id.');
      }
      const { count } = await tx.userSubscription.updateMany({
        where: { id: subscription.id, status: 'ACTIVE' },
        data: {
          status: 'CANCELLED',
          cancelledAt: now,
          cancellationReason: 'REVOKED',
          autoRenew: false,
        },
      });
      if (count === 0) {
        throw new BadRequestException(
          'Only an active subscription can be revoked.',
        );
      }
      const metadata = { reason: input.reason };
      await this.repository.recordEvent(tx, {
        subscriptionId: subscription.id,
        userId: subscription.userId,
        type: 'REVOKED',
        fromStatus: 'ACTIVE',
        toStatus: 'CANCELLED',
        actorId: input.actorId,
        metadata,
      });
      await this.audit(
        tx,
        input.actorId,
        'membership.subscription.revoke',
        subscription.id,
        metadata,
      );
    });
  }

  private assertReason(reason: string): void {
    if (typeof reason !== 'string' || reason.trim().length < 3) {
      throw new BadRequestException('A reason is required for this action.');
    }
  }

  private async audit(
    tx: Prisma.TransactionClient,
    actorId: string,
    action: string,
    entityId: string,
    metadata: Record<string, unknown>,
  ): Promise<void> {
    await tx.auditLog.create({
      data: {
        actorId,
        action,
        entity: 'UserSubscription',
        entityId,
        metadata: metadata as Prisma.InputJsonValue,
      },
    });
  }
}
