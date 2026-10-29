import { Injectable } from '@nestjs/common';
import type { ReferralEvent, ReferralEventPublisher } from '@app/common';

export type ReferralEventHandler = (event: ReferralEvent) => Promise<void>;

/**
 * In-process delivery of payment events (libs/common referral-events) to the
 * features that subscribe — the agent program's commission handlers. Render
 * runs no worker, so this is a plain list of handlers; a queue can replace
 * it later behind the same `ReferralEventPublisher` interface.
 *
 * Events reach it only through PaymentEventDispatcher, after the payment's
 * transaction has committed. `publish` resolves once EVERY handler has
 * accepted the event, and rejects if any throws — the dispatcher then keeps
 * the event and delivers it again later, so handlers must be idempotent
 * (keyed on paymentId / refundId).
 */
@Injectable()
export class ReferralEventBus implements ReferralEventPublisher {
  private readonly handlers: ReferralEventHandler[] = [];

  /** Call once, at startup (e.g. in a module's onModuleInit). */
  subscribe(handler: ReferralEventHandler): void {
    this.handlers.push(handler);
  }

  /** With no subscriber, events stay in the outbox until one appears. */
  get hasSubscribers(): boolean {
    return this.handlers.length > 0;
  }

  async publish(event: ReferralEvent): Promise<void> {
    for (const handler of this.handlers) {
      await handler(event);
    }
  }
}
