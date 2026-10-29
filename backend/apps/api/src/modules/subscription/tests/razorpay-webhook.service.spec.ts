import { Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { RazorpayWebhookService } from '../services/razorpay-webhook.service';

// Dispatch + idempotency of the webhook handler. The state changes it
// triggers are SubscriptionLifecycleService's, covered against a real
// database in membership-lifecycle.integration.spec.ts.

function build() {
  // Mirrors the table's two unique keys: event id, and signed-body hash.
  const acceptedIds = new Set<string>();
  const acceptedHashes = new Set<string>();
  const tx = {
    paymentWebhookEvent: {
      createMany: jest.fn(
        ({
          data,
        }: {
          data: Array<{ eventId: string; payloadSha256: string }>;
        }) => {
          const { eventId, payloadSha256 } = data[0];
          if (acceptedIds.has(eventId) || acceptedHashes.has(payloadSha256)) {
            return Promise.resolve({ count: 0 });
          }
          acceptedIds.add(eventId);
          acceptedHashes.add(payloadSha256);
          return Promise.resolve({ count: 1 });
        },
      ),
      update: jest.fn().mockResolvedValue({}),
    },
  };
  const lifecycle = {
    confirmPayment: jest.fn().mockResolvedValue('ACTIVATED'),
    recordPaymentFailure: jest.fn().mockResolvedValue('RECORDED'),
    recordRefund: jest.fn().mockResolvedValue('FULL'),
  };
  const prisma = {
    $transaction: jest.fn((cb: (t: unknown) => unknown) => cb(tx)),
  };
  const dispatcher = { dispatchSoon: jest.fn() };
  const hasher = {
    available: true,
    hashIdentifier: jest.fn(
      (kind: string, value: string) => `v1:${kind}:${value}`,
    ),
  };
  const service = new RazorpayWebhookService(
    prisma as never,
    lifecycle as never,
    dispatcher as never,
    hasher as never,
  );
  return { service, tx, lifecycle, dispatcher };
}

const captured = {
  event: 'payment.captured',
  payload: {
    payment: {
      entity: {
        id: 'pay_1',
        order_id: 'order_1',
        amount: 499_900,
        currency: 'INR',
      },
    },
  },
};
const raw = (body: unknown) => Buffer.from(JSON.stringify(body));

describe('RazorpayWebhookService', () => {
  beforeEach(() =>
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined),
  );
  afterEach(() => jest.restoreAllMocks());

  it('activates on payment.captured, passing the amount Razorpay reports for checking', async () => {
    const { service, lifecycle } = build();
    await expect(
      service.handle('evt_1', captured, raw(captured)),
    ).resolves.toEqual({
      status: 'PROCESSED',
      detail: 'ACTIVATED',
    });
    expect(lifecycle.confirmPayment).toHaveBeenCalledWith(expect.anything(), {
      orderId: 'order_1',
      paymentId: 'pay_1',
      amountInPaise: 499_900,
      currency: 'INR',
      actorId: null,
      via: 'WEBHOOK',
      paymentSourceHash: null,
    });
  });

  it('hashes the payer’s UPI id and delivers the payment event after commit', async () => {
    const { service, lifecycle, dispatcher } = build();
    const upi = {
      ...captured,
      payload: {
        payment: {
          entity: { ...captured.payload.payment.entity, vpa: 'Priya@OkICICI' },
        },
      },
    };
    await service.handle('evt_upi', upi, raw(upi));
    expect(lifecycle.confirmPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        paymentSourceHash: 'v1:UPI:Priya@OkICICI',
      }),
    );
    expect(dispatcher.dispatchSoon).toHaveBeenCalledTimes(1);
  });

  it('applies a redelivered event exactly once, delivering events once', async () => {
    const { service, lifecycle, dispatcher } = build();
    await service.handle('evt_1', captured, raw(captured));
    await expect(
      service.handle('evt_1', captured, raw(captured)),
    ).resolves.toEqual({
      status: 'DUPLICATE',
    });
    expect(lifecycle.confirmPayment).toHaveBeenCalledTimes(1);
    expect(dispatcher.dispatchSoon).toHaveBeenCalledTimes(1);
  });

  it('falls back to the payload hash as the id when the event-id header is missing', async () => {
    const { service, tx } = build();
    await service.handle(undefined, captured, raw(captured));
    const sha = createHash('sha256').update(raw(captured)).digest('hex');
    expect(tx.paymentWebhookEvent.createMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: [
          expect.objectContaining({
            eventId: `sha256:${sha}`,
            payloadSha256: sha,
          }),
        ],
      }),
    );
  });

  it('uses order.paid’s amount_paid', async () => {
    const { service, lifecycle } = build();
    const body = {
      event: 'order.paid',
      payload: {
        order: {
          entity: { id: 'order_1', amount_paid: 499_900, currency: 'INR' },
        },
        payment: { entity: { id: 'pay_1', order_id: 'order_1', amount: 1 } },
      },
    };
    await service.handle('evt_2', body, raw(body));
    expect(lifecycle.confirmPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ amountInPaise: 499_900 }),
    );
  });

  it('records a failed payment without activating anything', async () => {
    const { service, lifecycle } = build();
    const body = {
      event: 'payment.failed',
      payload: {
        payment: {
          entity: {
            id: 'pay_1',
            order_id: 'order_1',
            error_description: 'Card declined',
          },
        },
      },
    };
    await service.handle('evt_3', body, raw(body));
    expect(lifecycle.recordPaymentFailure).toHaveBeenCalledWith(
      expect.anything(),
      {
        orderId: 'order_1',
        paymentId: 'pay_1',
        reason: 'Card declined',
      },
    );
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it('applies a processed refund, passing the order so it can overtake the capture', async () => {
    const { service, lifecycle } = build();
    const body = {
      event: 'refund.processed',
      payload: {
        refund: {
          entity: { id: 'rfnd_1', payment_id: 'pay_1', amount: 499_900 },
        },
        payment: { entity: { id: 'pay_1', order_id: 'order_1' } },
      },
    };
    await service.handle('evt_4', body, raw(body));
    expect(lifecycle.recordRefund).toHaveBeenCalledWith(expect.anything(), {
      paymentId: 'pay_1',
      orderId: 'order_1',
      refundId: 'rfnd_1',
      amountInPaise: 499_900,
    });
  });

  it('treats a replayed signed body as a duplicate even under a fresh event id', async () => {
    // The event-id header isn't signed; the body is. A captured refund
    // delivery replayed with a new header must not refund twice.
    const { service, lifecycle } = build();
    const body = {
      event: 'refund.processed',
      payload: {
        refund: { entity: { id: 'rfnd_1', payment_id: 'pay_1', amount: 100 } },
      },
    };
    await service.handle('evt_original', body, raw(body));
    expect(await service.handle('evt_forged', body, raw(body))).toEqual({
      status: 'DUPLICATE',
    });
    expect(lifecycle.recordRefund).toHaveBeenCalledTimes(1);
  });

  it('ignores a capture without a currency rather than assuming one', async () => {
    const { service, lifecycle } = build();
    const body = {
      event: 'payment.captured',
      payload: {
        payment: { entity: { id: 'pay_1', order_id: 'order_1', amount: 1 } },
      },
    };
    expect((await service.handle('evt_nc', body, raw(body))).status).toBe(
      'IGNORED',
    );
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it('stores unhandled, malformed and foreign events as IGNORED', async () => {
    const { service, tx, lifecycle } = build();
    const other = { event: 'subscription.charged' };
    expect(await service.handle('evt_5', other, raw(other))).toEqual({
      status: 'IGNORED',
      detail: 'unhandled event type',
    });
    const noAmount = {
      event: 'payment.captured',
      payload: { payment: { entity: { id: 'p', order_id: 'o' } } },
    };
    expect(
      (await service.handle('evt_6', noAmount, raw(noAmount))).status,
    ).toBe('IGNORED');

    lifecycle.confirmPayment.mockResolvedValueOnce('UNKNOWN_ORDER');
    expect(await service.handle('evt_7', captured, raw(captured))).toEqual({
      status: 'IGNORED',
      detail: 'unknown order',
    });
    expect(tx.paymentWebhookEvent.update).toHaveBeenCalledTimes(3);
  });

  it('lets a failure roll back with the transaction so the retry is not a duplicate', async () => {
    const { service, lifecycle } = build();
    // In production the event row is inserted inside this transaction; a
    // throw rolls it back. Here: the throw propagates (-> 5xx -> retry).
    lifecycle.confirmPayment.mockRejectedValueOnce(new Error('db blip'));
    await expect(
      service.handle('evt_8', captured, raw(captured)),
    ).rejects.toThrow('db blip');
  });
});
