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
/** Rounds one `drain` may run while full batches keep succeeding. */
const MAX_DRAIN_ROUNDS = 20;

/**
 * Deliveries an event gets before it is set aside: it then stays in the
 * outbox (never deleted) but is no longer retried, so it cannot hold up the
 * events behind it. A person looks at it (`deadLettered` in the daily job's
 * report, and an error in the log when it happens).
 */
export const MAX_DELIVERY_ATTEMPTS = 10;

/**
 * Delivers outbox events to ReferralEventBus subscribers after commit —
 * oldest first, at least once. Runs right after each payment change
 * (`dispatchSoon`), at startup (catching up anything a restart interrupted),
 * and from the daily job. An event a handler rejects stays undelivered with
 * its error and is tried again on the next run, up to MAX_DELIVERY_ATTEMPTS;
 * with no subscriber at all (agent program not wired) events simply wait.
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

  /**
   * Everything waiting, for the daily job: full batches until one comes back
   * short or with a failure (a failing event is retried on the next run, not
   * again and again in this one). Reports how many are set aside.
   */
  async drain(limit = BATCH): Promise<DrainResult> {
    const total: DispatchResult = { delivered: 0, failed: 0 };
    for (let round = 0; round < MAX_DRAIN_ROUNDS; round++) {
      const result = await this.dispatchPending(limit);
      total.delivered += result.delivered;
      total.failed += result.failed;
      if (result.failed > 0 || result.delivered < limit) break;
    }
    const [waiting, deadLettered] = await Promise.all([
      this.prisma.paymentEventOutbox.count({
        where: {
          deliveredAt: null,
          attempts: { lt: MAX_DELIVERY_ATTEMPTS },
        },
      }),
      this.prisma.paymentEventOutbox.count({
        where: {
          deliveredAt: null,
          attempts: { gte: MAX_DELIVERY_ATTEMPTS },
        },
      }),
    ]);
    return {
      ...total,
      waiting,
      deadLettered,
      subscribers: this.bus.hasSubscribers,
    };
  }

  private async deliverBatch(limit: number): Promise<DispatchResult> {
    const result: DispatchResult = { delivered: 0, failed: 0 };
    if (!this.bus.hasSubscribers) return result;
    const pending = await this.prisma.paymentEventOutbox.findMany({
      where: {
        deliveredAt: null,
        attempts: { lt: MAX_DELIVERY_ATTEMPTS },
      },
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
        const attempt = row.attempts + 1;
        this.logger.error(
          attempt >= MAX_DELIVERY_ATTEMPTS
            ? `Payment event ${row.dedupeKey} SET ASIDE after ${attempt} failed deliveries: ${message} — needs a person.`
            : `Payment event ${row.dedupeKey} was not accepted (attempt ${attempt}): ${message}`,
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

export interface DrainResult extends DispatchResult {
  /** Still to deliver (will be retried). */
  waiting: number;
  /** Set aside after MAX_DELIVERY_ATTEMPTS failures. */
  deadLettered: number;
  /** False while nothing subscribes (events wait). */
  subscribers: boolean;
}
