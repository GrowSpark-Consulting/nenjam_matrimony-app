import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '@app/database';
import type {
  PaymentWebhookStatus,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PaymentEventDispatcher } from '../events/payment-event-outbox';
import { paymentSourceHashOf } from '../events/payment-events';
import { SubscriptionLifecycleService } from './subscription-lifecycle.service';

const PROVIDER = 'RAZORPAY';

/** The parts of a Razorpay webhook body this handles. Everything is
 *  optional: the body is signed, but its shape is still Razorpay's. */
interface RazorpayWebhookBody {
  event?: unknown;
  payload?: {
    payment?: {
      entity?: {
        id?: string;
        order_id?: string;
        amount?: number;
        currency?: string;
        error_code?: string;
        error_description?: string;
        /** The payer's UPI id on UPI payments. */
        vpa?: string;
      };
    };
    order?: {
      entity?: { id?: string; amount_paid?: number; currency?: string };
    };
    refund?: { entity?: { id?: string; payment_id?: string; amount?: number } };
  };
}

export interface WebhookResult {
  status: PaymentWebhookStatus | 'DUPLICATE';
  detail?: string;
}

/**
 * Applies Razorpay webhook events. Idempotent by construction: the event id
 * and the signed body's hash are recorded in payment_webhook_events IN THE
 * SAME TRANSACTION that applies the event, so
 *  - a redelivery finds the id taken and does nothing (and still answers
 *    200, so Razorpay stops retrying);
 *  - a delivery that fails mid-way rolls back the id with everything else,
 *    answers 5xx, and Razorpay's retry applies it cleanly.
 * And beneath that, every state change it makes is itself a conditional
 * transition (SubscriptionLifecycleService), so even two DIFFERENT events for
 * one order (payment.captured + order.paid) activate it once.
 *
 * Handled: payment.captured / order.paid (activate, amount-checked),
 * payment.failed (record), refund.processed (refund; a full refund revokes).
 * Anything else is stored as IGNORED.
 */
@Injectable()
export class RazorpayWebhookService {
  private readonly logger = new Logger(RazorpayWebhookService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly lifecycle: SubscriptionLifecycleService,
    private readonly dispatcher: PaymentEventDispatcher,
    private readonly hasher: IdentifierHashService,
  ) {}

  async handle(
    eventIdHeader: string | undefined,
    body: unknown,
    rawBody: Buffer,
  ): Promise<WebhookResult> {
    const payloadSha256 = createHash('sha256').update(rawBody).digest('hex');
    // Two keys, either of which makes a delivery a duplicate (both are
    // unique; `skipDuplicates` honours both): Razorpay's event id, and the
    // hash of the SIGNED body. The header is not covered by the signature, so
    // someone replaying a captured delivery with a fresh event id is still
    // caught by the body hash — Razorpay's own retries resend the same bytes.
    const eventId = eventIdHeader?.trim() || `sha256:${payloadSha256}`;
    const event = (body ?? {}) as RazorpayWebhookBody;
    const eventType = typeof event.event === 'string' ? event.event : 'unknown';
    const payment = event.payload?.payment?.entity;
    const order = event.payload?.order?.entity;
    const refund = event.payload?.refund?.entity;

    const result = await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.paymentWebhookEvent.createMany({
        data: [
          {
            provider: PROVIDER,
            eventId,
            eventType,
            status: 'PROCESSED',
            orderId: payment?.order_id ?? order?.id ?? null,
            paymentId: payment?.id ?? refund?.payment_id ?? null,
            payloadSha256,
          },
        ],
        skipDuplicates: true,
      });
      if (count === 0) return { status: 'DUPLICATE' as const };

      const result = await this.apply(tx, eventType, event);
      if (result.status !== 'PROCESSED' || result.detail) {
        await tx.paymentWebhookEvent.update({
          where: { provider_eventId: { provider: PROVIDER, eventId } },
          data: { status: result.status, detail: result.detail ?? null },
        });
      }
      if (result.status === 'IGNORED') {
        this.logger.log(
          `Razorpay ${eventType} ${eventId} ignored: ${result.detail}`,
        );
      }
      return result;
    });
    // Deliver any payment event the change wrote, now that it has committed.
    if (result.status === 'PROCESSED') this.dispatcher.dispatchSoon();
    return result;
  }

  private async apply(
    tx: Prisma.TransactionClient,
    eventType: string,
    event: RazorpayWebhookBody,
  ): Promise<{ status: PaymentWebhookStatus; detail?: string }> {
    const payment = event.payload?.payment?.entity;
    const order = event.payload?.order?.entity;
    const refund = event.payload?.refund?.entity;

    switch (eventType) {
      case 'payment.captured':
      case 'order.paid': {
        const orderId = payment?.order_id ?? order?.id;
        const amount =
          eventType === 'order.paid'
            ? (order?.amount_paid ?? payment?.amount)
            : payment?.amount;
        const currency = payment?.currency ?? order?.currency;
        if (
          !orderId ||
          !payment?.id ||
          typeof amount !== 'number' ||
          typeof currency !== 'string'
        ) {
          return {
            status: 'IGNORED',
            detail: 'missing order, payment, amount or currency',
          };
        }
        const outcome = await this.lifecycle.confirmPayment(tx, {
          orderId,
          paymentId: payment.id,
          amountInPaise: amount,
          currency,
          actorId: null,
          via: 'WEBHOOK',
          paymentSourceHash: paymentSourceHashOf(this.hasher, payment.vpa),
        });
        return outcome === 'UNKNOWN_ORDER'
          ? { status: 'IGNORED', detail: 'unknown order' }
          : { status: 'PROCESSED', detail: outcome };
      }
      case 'payment.failed': {
        if (!payment?.order_id) {
          return { status: 'IGNORED', detail: 'missing order' };
        }
        const outcome = await this.lifecycle.recordPaymentFailure(tx, {
          orderId: payment.order_id,
          paymentId: payment.id,
          reason:
            payment.error_description ?? payment.error_code ?? 'Payment failed',
        });
        return outcome === 'UNKNOWN_ORDER'
          ? { status: 'IGNORED', detail: 'unknown order' }
          : { status: 'PROCESSED', detail: outcome };
      }
      case 'refund.processed': {
        if (
          !refund?.id ||
          !refund.payment_id ||
          typeof refund.amount !== 'number'
        ) {
          return { status: 'IGNORED', detail: 'missing refund fields' };
        }
        // The refunded payment's order, when the payload carries it: lets a
        // refund that overtakes the capture webhook still find its payment.
        const outcome = await this.lifecycle.recordRefund(tx, {
          paymentId: refund.payment_id,
          orderId: payment?.order_id,
          refundId: refund.id,
          amountInPaise: refund.amount,
        });
        return outcome === 'UNKNOWN_PAYMENT'
          ? { status: 'IGNORED', detail: 'unknown payment' }
          : { status: 'PROCESSED', detail: outcome };
      }
      default:
        return { status: 'IGNORED', detail: 'unhandled event type' };
    }
  }
}
