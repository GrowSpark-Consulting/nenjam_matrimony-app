import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '@app/database';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { CheckoutDto, VerifyCheckoutDto } from '../dto/checkout.dto';
import type {
  CheckoutResponseDto,
  VerifyCheckoutResponseDto,
  VerifyOutcome,
} from '../dto/checkout.dto';
import { RazorpayService } from './razorpay.service';
import { SubscriptionLifecycleService } from './subscription-lifecycle.service';
import { SubscriptionRepository } from '../repositories/subscription.repository';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Buying a plan, in two steps the client drives:
 *
 *  1. `start` — validates the plan and duration are on sale, creates a
 *     Razorpay order for the CURRENT price, and records a PENDING
 *     subscription + PENDING payment. The subscription pins the entitlement
 *     version and the price on sale at this moment, so what the member saw is
 *     what they get. PENDING grants nothing.
 *  2. `verify` — checks the Razorpay signature, then asks Razorpay for the
 *     payment itself and activates only if it is CAPTURED for this order at
 *     the checkout amount. The client never supplies a status or an amount.
 *     The webhook (RazorpayWebhookService) activates the same order
 *     independently; whichever arrives first wins, the other is a no-op.
 *
 * Both answer 503 until Razorpay is configured.
 */
@Injectable()
export class CheckoutService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
    private readonly razorpay: RazorpayService,
    private readonly lifecycle: SubscriptionLifecycleService,
    private readonly repository: SubscriptionRepository,
  ) {}

  async start(
    userId: string,
    dto: CheckoutDto,
    now: Date = new Date(),
  ): Promise<CheckoutResponseDto> {
    // Fail before touching the catalogue or the provider when unconfigured.
    const keyId = this.razorpay.publicKeyId();

    const plan = await this.catalog.findPlan(dto.planCode);
    if (!plan || !plan.isActive || plan.code === 'FREE') {
      throw new BadRequestException('That plan is not available.');
    }
    const duration = plan.durations.find(
      (d) => d.months === dto.months && d.isActive && d.priceInPaise !== null,
    );
    if (!duration || duration.priceInPaise === null) {
      throw new BadRequestException(
        `${plan.name} is not available for ${dto.months} months.`,
      );
    }
    const version = this.catalog.versionEffectiveAt(plan, now);
    if (!version) {
      throw new BadRequestException('That plan is not available.');
    }

    const subscriptionId = randomUUID();
    const order = await this.razorpay.createOrder({
      amountInPaise: duration.priceInPaise,
      currency: duration.currency,
      receipt: subscriptionId,
      notes: {
        userId,
        subscriptionId,
        plan: plan.code,
        months: String(duration.months),
      },
    });

    // Provisional window: its LENGTH is the term bought (duration + bonus).
    // Activation re-anchors the start (now, or queued behind a current plan)
    // and keeps this length, so a later price-list edit can't change it.
    const termMs = (duration.durationDays + duration.bonusDays) * DAY_MS;
    await this.prisma.$transaction(async (tx) => {
      await tx.userSubscription.create({
        data: {
          id: subscriptionId,
          userId,
          planId: plan.id,
          planVersionId: version.id,
          durationId: duration.id,
          status: 'PENDING',
          startDate: now,
          endDate: new Date(now.getTime() + termMs),
          priceInPaise: duration.priceInPaise,
          currency: duration.currency,
          source: 'PURCHASE',
        },
      });
      await tx.paymentTransaction.create({
        data: {
          userId,
          subscriptionId,
          razorpayOrderId: order.id,
          amountInr: duration.priceInPaise!,
          currency: duration.currency,
          status: 'PENDING',
        },
      });
      await this.repository.recordEvent(tx, {
        subscriptionId,
        userId,
        type: 'CHECKOUT_CREATED',
        toStatus: 'PENDING',
        actorId: userId,
        metadata: {
          orderId: order.id,
          plan: plan.code,
          months: duration.months,
          priceInPaise: duration.priceInPaise,
          planVersion: version.version,
        },
      });
    });

    return {
      subscriptionId,
      orderId: order.id,
      amountInPaise: duration.priceInPaise,
      currency: duration.currency,
      keyId,
      plan: { code: plan.code, name: plan.name },
      months: duration.months,
    };
  }

  async verify(
    userId: string,
    dto: VerifyCheckoutDto,
  ): Promise<VerifyCheckoutResponseDto> {
    if (
      !this.razorpay.verifyPaymentSignature(
        dto.orderId,
        dto.paymentId,
        dto.signature,
      )
    ) {
      throw new BadRequestException('Payment verification failed.');
    }

    // Ownership before anything else — and the same answer for "no such
    // order" and "someone else's order".
    const payment = await this.repository.findPaymentByOrderId(
      this.prisma,
      dto.orderId,
    );
    if (!payment || payment.userId !== userId) {
      throw new NotFoundException('Payment not found.');
    }

    // The signature proves Razorpay saw this payment for this order — not
    // that money was taken. Only Razorpay's own record says that, so it is
    // fetched, and only a CAPTURED payment for this order, at the amount and
    // currency fixed at checkout, activates anything.
    const provider = await this.razorpay.fetchPayment(dto.paymentId);
    let outcome: VerifyOutcome;
    if (!provider) {
      // Razorpay unreachable: don't guess. The webhook will confirm it.
      outcome = 'PENDING_CONFIRMATION';
    } else if (provider.orderId !== dto.orderId) {
      throw new BadRequestException('Payment verification failed.');
    } else if (provider.status === 'captured') {
      outcome = await this.prisma.$transaction((tx) =>
        this.lifecycle.confirmPayment(tx, {
          orderId: dto.orderId,
          paymentId: dto.paymentId,
          amountInPaise: provider.amount,
          currency: provider.currency,
          actorId: userId,
          via: 'CHECKOUT_VERIFY',
        }),
      );
    } else if (
      provider.status === 'authorized' ||
      provider.status === 'created'
    ) {
      // Not captured yet: the payment.captured webhook will activate it.
      outcome = 'AWAITING_CAPTURE';
    } else {
      outcome = provider.status === 'refunded' ? 'REFUNDED' : 'NOT_PAID';
    }

    const subscription = await this.prisma.userSubscription.findUnique({
      where: { id: payment.subscriptionId },
      select: { status: true, startDate: true, endDate: true },
    });
    const active = subscription?.status === 'ACTIVE';
    return {
      outcome,
      subscriptionId: payment.subscriptionId,
      status: subscription?.status ?? 'PENDING',
      // Dates only once they are real; a PENDING row's are provisional.
      startDate: active ? subscription.startDate.toISOString() : null,
      endDate: active ? subscription.endDate.toISOString() : null,
    };
  }
}
