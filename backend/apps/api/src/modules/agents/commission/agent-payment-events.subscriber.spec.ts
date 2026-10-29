import { addExclusiveTax, type ReferralEvent } from '@app/common';
import { ReferralEventBus } from '../../subscription/events/referral-event-bus';
import { makeCommissionHarness } from '../testing/agent-commission-harness';
import { FakeAgentClock } from '../testing/fake-agent-infra';
import {
  AgentPaymentEventsSubscriber,
  AgentPaymentEventsUnknownError,
  handlePaymentEvent,
} from './agent-payment-events.subscriber';

const quiet = { log: jest.fn() };

async function creditable() {
  const h = makeCommissionHarness();
  h.seedPolicy();
  await h.seedAgent();
  await h.seedAttribution(1);
  return h;
}

describe('AgentPaymentEventsSubscriber.onModuleInit', () => {
  const clock = new FakeAgentClock(new Date('2026-10-29T10:00:00Z'));
  const events = {
    onPaymentSucceeded: jest.fn(),
    onPaymentRefunded: jest.fn(),
  };

  it('does NOT subscribe without peppers or without a policy (events wait)', async () => {
    for (const [available, policy] of [
      [false, {}],
      [true, null],
    ] as const) {
      const bus = { subscribe: jest.fn() };
      await new AgentPaymentEventsSubscriber(
        bus,
        events,
        { available },
        { findActive: jest.fn().mockResolvedValue(policy) },
        clock,
      ).onModuleInit();
      expect(bus.subscribe).not.toHaveBeenCalled();
    }
  });

  it('subscribes once when ready, on the real bus', async () => {
    const bus = new ReferralEventBus();
    await new AgentPaymentEventsSubscriber(
      bus,
      events,
      { available: true },
      { findActive: jest.fn().mockResolvedValue({ id: 'v1' }) },
      clock,
    ).onModuleInit();
    expect(bus.hasSubscribers).toBe(true);
  });
});

describe('payment events through the real ReferralEventBus', () => {
  it('a success creates one commission; a redelivery is ALREADY_PROCESSED', async () => {
    const h = await creditable();
    const bus = new ReferralEventBus();
    const log = { log: jest.fn<void, [string]>() };
    bus.subscribe((e) => handlePaymentEvent(h.events, e, log));
    await bus.publish(h.paymentSucceeded(1));
    await bus.publish(h.paymentSucceeded(1));
    expect(log.log.mock.calls.map((c) => c[0])).toEqual([
      'payment.succeeded pay-1: CREATED',
      'payment.succeeded pay-1: ALREADY_PROCESSED',
    ]);
  });

  it('a handler failure rejects publish, so the outbox keeps the event for a retry', async () => {
    const bus = new ReferralEventBus();
    const boom = new Error('database down');
    bus.subscribe((e) =>
      handlePaymentEvent(
        {
          onPaymentSucceeded: jest.fn().mockRejectedValue(boom),
          onPaymentRefunded: jest.fn(),
        },
        e,
        quiet,
      ),
    );
    const h = makeCommissionHarness();
    await expect(bus.publish(h.paymentSucceeded(1))).rejects.toBe(boom);
  });

  it('an unknown version or type is refused (redelivered), never dropped', async () => {
    const h = makeCommissionHarness();
    const handlers = {
      onPaymentSucceeded: jest.fn(),
      onPaymentRefunded: jest.fn(),
    };
    await expect(
      handlePaymentEvent(
        handlers,
        { ...h.paymentSucceeded(1), version: 2 } as unknown as ReferralEvent,
        quiet,
      ),
    ).rejects.toBeInstanceOf(AgentPaymentEventsUnknownError);
    await expect(
      handlePaymentEvent(
        handlers,
        {
          ...h.paymentSucceeded(1),
          type: 'payment.disputed',
        } as unknown as ReferralEvent,
        quiet,
      ),
    ).rejects.toBeInstanceOf(AgentPaymentEventsUnknownError);
    expect(handlers.onPaymentSucceeded).not.toHaveBeenCalled();
  });
});

describe('livemode', () => {
  it('a test payment earns nothing; its refund changes nothing', async () => {
    const h = await creditable();
    await expect(
      h.events.onPaymentSucceeded(h.paymentSucceeded(1, { livemode: false })),
    ).resolves.toEqual({ outcome: 'TEST_MODE' });
    await expect(h.commissions.findByPaymentId('pay-1')).resolves.toBeNull();
    await expect(
      h.events.onPaymentRefunded(h.paymentRefunded(1, 1, { livemode: false })),
    ).resolves.toEqual({ outcome: 'TEST_MODE' });
  });

  it('a missing livemode is treated as test (money fails closed)', async () => {
    const h = await creditable();
    const event = { ...h.paymentSucceeded(1) } as Partial<ReferralEvent>;
    delete (event as { livemode?: boolean }).livemode;
    await expect(h.events.onPaymentSucceeded(event as never)).resolves.toEqual({
      outcome: 'TEST_MODE',
    });
  });
});

describe('the commission at both GST rates (payment.gst_rate_bps)', () => {
  it.each([
    [0, 'GST not registered yet: taxable equals what was paid'],
    [1800, 'after registration, 18% on top'],
  ])('rate %i bps (%s): 10%% of the taxable amount', async (rateBps) => {
    const h = await creditable();
    const taxable = 9_500;
    const { taxPaise, totalPaise: amountPaidPaise } = addExclusiveTax(
      taxable,
      rateBps,
    );
    if (rateBps === 0) expect(amountPaidPaise).toBe(taxable);
    const result = await h.events.onPaymentSucceeded(
      h.paymentSucceeded(1, {
        taxRateBps: rateBps,
        taxPaise,
        taxableAmountPaise: taxable,
        amountPaidPaise,
      }),
    );
    expect(result.outcome).toBe('CREATED');
    const created = await h.commissions.findByPaymentId('pay-1');
    expect(created?.amountPaise).toBe(950);
  });
});
