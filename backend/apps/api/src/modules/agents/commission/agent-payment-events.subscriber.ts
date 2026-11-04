/**
 * Subscribes the commission handlers to the payment events
 * (`ReferralEventBus.subscribe`, Shaaz's SubscriptionModule) in
 * `onModuleInit`, which runs before the dispatcher's first delivery at
 * `onApplicationBootstrap`.
 *
 * Delivery is at least once, after commit, through the payment outbox: a
 * handler that throws leaves the event undelivered and it is tried again on
 * the next dispatch run (after the next payment change, at every startup,
 * and from the daily job). Both handlers are idempotent (paymentId /
 * refundId), so a redelivery is harmless.
 *
 * Not an agent route: it does not depend on AGENT_PROGRAM_ENABLED. It
 * subscribes only when the handlers can answer (identifier hashing is
 * configured and a commission policy is in effect); otherwise it logs why
 * and does NOT subscribe, so events wait in the outbox instead of failing
 * and being retried. Checked at startup: once the missing piece is set, the
 * next restart (every Render deploy) subscribes and catches up.
 */
import { Injectable, Logger, type OnModuleInit } from '@nestjs/common';
import type { ReferralEvent } from '@app/common';
import type { IdentifierHashService } from '../../platform/identifier-hash.service';
import type { ReferralEventBus } from '../../subscription/events/referral-event-bus';
import type { CommissionPolicyRepository } from '../ports/agent-commission-ports';
import type { AgentClock } from '../ports/agent-infra-ports';
import type { AgentCommissionEventsService } from './agent-commission-events.service';

export class AgentPaymentEventsUnknownError extends Error {
  constructor(type: string, version: unknown) {
    super(`Unknown payment event ${type} (version ${String(version)}).`);
    this.name = 'AgentPaymentEventsUnknownError';
  }
}

/** Routes one event to its handler. Throws (so it is redelivered) for an
 *  event this code does not understand: a money event is never dropped. */
export async function handlePaymentEvent(
  events: Pick<
    AgentCommissionEventsService,
    'onPaymentSucceeded' | 'onPaymentRefunded'
  >,
  event: ReferralEvent,
  logger: Pick<Logger, 'log'>,
): Promise<void> {
  if (event.version !== 1) {
    throw new AgentPaymentEventsUnknownError(event.type, event.version);
  }
  if (event.type === 'payment.succeeded') {
    const result = await events.onPaymentSucceeded(event);
    logger.log(`payment.succeeded ${event.paymentId}: ${result.outcome}`);
    return;
  }
  if (event.type === 'payment.refunded') {
    const result = await events.onPaymentRefunded(event);
    logger.log(`payment.refunded ${event.refundId}: ${result.outcome}`);
    return;
  }
  throw new AgentPaymentEventsUnknownError(
    (event as { type: string }).type,
    (event as { version: unknown }).version,
  );
}

@Injectable()
export class AgentPaymentEventsSubscriber implements OnModuleInit {
  private readonly logger = new Logger('AgentPaymentEvents');

  constructor(
    private readonly bus: Pick<ReferralEventBus, 'subscribe'>,
    private readonly events: Pick<
      AgentCommissionEventsService,
      'onPaymentSucceeded' | 'onPaymentRefunded'
    >,
    private readonly hashing: Pick<IdentifierHashService, 'available'>,
    private readonly policy: Pick<CommissionPolicyRepository, 'findActive'>,
    private readonly clock: AgentClock,
  ) {}

  async onModuleInit(): Promise<void> {
    const reason = await this.notReadyReason();
    if (reason !== null) {
      this.logger.warn(
        `Commission handlers NOT subscribed (${reason}): payment events wait in the outbox.`,
      );
      return;
    }
    this.bus.subscribe((event) =>
      handlePaymentEvent(this.events, event, this.logger),
    );
    this.logger.log('Commission handlers subscribed to payment events.');
  }

  private async notReadyReason(): Promise<string | null> {
    if (!this.hashing.available) return 'IDENTIFIER_HASH_PEPPERS is not set';
    const active = await this.policy.findActive(this.clock.now());
    return active === null ? 'no commission policy is in effect' : null;
  }
}
