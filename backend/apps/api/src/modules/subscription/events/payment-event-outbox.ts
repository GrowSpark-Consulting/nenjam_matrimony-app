import {
  Injectable,
  Logger,
  type OnApplicationBootstrap,
} from '@nestjs/common';
import type { ReferralEvent } from '@app/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { ReferralEventBus } from './referral-event-bus';

type OutboxWriter = Pick<Prisma.TransactionClient, 'paymentEventOutbox'>;

/** The idempotency key: one row per payment success and per refund. */
export function paymentEventKey(event: ReferralEvent): string {
  return event.type === 'payment.succeeded'
    ? `${event.type}:${event.paymentId}`
    : `${event.type}:${event.refundId}`;
}

/**
 * Records [event] in the outbox inside the caller's transaction, so it exists
 * exactly when the payment change it describes commits. Writing the same
 * event twice (a redelivered webhook) is a no-op.
 */
export async function enqueuePaymentEvent(
  tx: OutboxWriter,
  event: ReferralEvent,
): Promise<void> {
  await tx.paymentEventOutbox.createMany({
    data: [
      {
        type: event.type,
        dedupeKey: paymentEventKey(event),
        payload: event as unknown as Prisma.InputJsonObject,
      },
    ],
    skipDuplicates: true,
  });
}

const BATCH = 50;
const MAX_ERROR_LENGTH = 500;

/**
 * Delivers outbox events to ReferralEventBus subscribers after commit —
 * oldest first, at least once. Runs right after each payment change
 * (`dispatchSoon`), at startup (catching up anything a restart interrupted),
 * and from the daily job. An event a handler rejects stays undelivered with
 * its error and is tried again on the next run; with no subscriber at all
 * (agent program not wired) events simply wait.
 */
@Injectable()
export class PaymentEventDispatcher implements OnApplicationBootstrap {
  private readonly logger = new Logger(PaymentEventDispatcher.name);
  private running: Promise<DispatchResult> | null = null;
  private again = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly bus: ReferralEventBus,
  ) {}

  onApplicationBootstrap(): void {
    this.dispatchSoon();
  }

  /** Fire and forget: never delays or fails the request that caused it. */
  dispatchSoon(): void {
    void this.dispatchPending().catch((error: Error) =>
      this.logger.error(`Payment event delivery failed: ${error.message}`),
    );
  }

  /**
   * Delivers waiting events. One run at a time per process; a call during a
   * run makes that run go round once more instead of starting a second.
   */
  dispatchPending(limit = BATCH): Promise<DispatchResult> {
    if (this.running) {
      this.again = true;
      return this.running;
    }
    this.running = (async () => {
      const total: DispatchResult = { delivered: 0, failed: 0 };
      do {
        this.again = false;
        const result = await this.deliverBatch(limit);
        total.delivered += result.delivered;
        total.failed += result.failed;
      } while (this.again);
      return total;
    })().finally(() => {
      this.running = null;
    });
    return this.running;
  }

  private async deliverBatch(limit: number): Promise<DispatchResult> {
    const result: DispatchResult = { delivered: 0, failed: 0 };
    if (!this.bus.hasSubscribers) return result;
    const pending = await this.prisma.paymentEventOutbox.findMany({
      where: { deliveredAt: null },
      orderBy: { createdAt: 'asc' },
      take: limit,
    });
    for (const row of pending) {
      try {
        await this.bus.publish(row.payload as unknown as ReferralEvent);
        await this.prisma.paymentEventOutbox.update({
          where: { id: row.id },
          data: { deliveredAt: new Date(), attempts: { increment: 1 } },
        });
        result.delivered += 1;
      } catch (error) {
        const message = (error as Error).message ?? String(error);
        await this.prisma.paymentEventOutbox.update({
          where: { id: row.id },
          data: {
            attempts: { increment: 1 },
            lastError: message.slice(0, MAX_ERROR_LENGTH),
          },
        });
        this.logger.error(
          `Payment event ${row.dedupeKey} was not accepted (attempt ${row.attempts + 1}): ${message}`,
        );
        result.failed += 1;
      }
    }
    return result;
  }
}

export interface DispatchResult {
  delivered: number;
  failed: number;
}
