import {
  BadRequestException,
  HttpException,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHmac } from 'node:crypto';
import type { ReferralQuoteProvider, ReferralQuoteResult } from '@app/common';
import { CheckoutService } from '../services/checkout.service';
import { RazorpayService } from '../services/razorpay.service';
import {
  catalogRows,
  catalogService,
} from '../../entitlements/tests/catalog-fixtures';

const NOW = new Date('2026-10-27T06:00:00.000Z');
const KEYS = { keyId: 'rzp_test_key', keySecret: 'key-secret' };

function build(
  options: {
    configured?: boolean;
    purchasable?: boolean;
    keyId?: string;
    /** The stored `payment.gst_rate_bps`; `undefined` leaves the key out. */
    gstRateBps?: unknown;
    quote?: ReferralQuoteProvider;
  } = {},
) {
  const razorpay = new RazorpayService({
    razorpay:
      options.configured === false
        ? {}
        : { ...KEYS, keyId: options.keyId ?? KEYS.keyId },
  } as never);
  const createOrder = jest
    .spyOn(razorpay, 'createOrder')
    .mockImplementation((input) =>
      Promise.resolve({
        id: 'order_1',
        amount: input.amountInPaise,
        currency: input.currency,
      }),
    );
  const tx = {
    userSubscription: {
      create: jest.fn().mockResolvedValue({}),
      findUnique: jest.fn().mockResolvedValue({
        id: 'sub-1',
        status: 'ACTIVE',
        startDate: NOW,
        endDate: NOW,
      }),
    },
    paymentTransaction: { create: jest.fn().mockResolvedValue({}) },
  };
  const repository = {
    recordEvent: jest.fn().mockResolvedValue(undefined),
    findPaymentByOrderId: jest
      .fn()
      .mockResolvedValue({ userId: 'u1', subscriptionId: 'sub-1' }),
  };
  const lifecycle = {
    confirmPayment: jest.fn().mockResolvedValue('ACTIVATED'),
  };
  // Razorpay's own record of the payment: captured, for order_1, at the
  // checkout amount — unless a test says otherwise.
  const fetchPayment = jest.spyOn(razorpay, 'fetchPayment').mockResolvedValue({
    id: 'pay_1',
    orderId: 'order_1',
    amount: 300_000,
    currency: 'INR',
    status: 'captured',
    vpa: null,
  });
  const settings = {
    getMany: jest
      .fn()
      .mockResolvedValue(
        'gstRateBps' in options && options.gstRateBps === undefined
          ? {}
          : { 'payment.gst_rate_bps': options.gstRateBps ?? 0 },
      ),
    registerValidator: jest.fn(),
  };
  const hasher = {
    available: true,
    hashIdentifier: jest.fn(
      (kind: string, value: string) => `v1:${kind}:${value}`,
    ),
  };
  const dispatcher = { dispatchSoon: jest.fn() };
  const service = new CheckoutService(
    {
      $transaction: jest.fn((cb: (t: unknown) => unknown) => cb(tx)),
      userSubscription: tx.userSubscription,
    } as never,
    catalogService(catalogRows({ purchasable: options.purchasable ?? true })),
    razorpay,
    lifecycle as never,
    repository as never,
    settings as never,
    hasher as never,
    dispatcher as never,
    options.quote,
  );
  return {
    service,
    createOrder,
    fetchPayment,
    tx,
    repository,
    lifecycle,
    settings,
    dispatcher,
  };
}

async function refusal(promise: Promise<unknown>) {
  try {
    await promise;
  } catch (error) {
    return error as HttpException;
  }
  throw new Error('expected checkout to refuse');
}

function quoting(result: Partial<ReferralQuoteResult>) {
  const quote = jest.fn().mockResolvedValue({
    discountPaise: 0,
    discountSource: 'NONE',
    taxableAfterDiscountPaise: 300_000,
    ...result,
  });
  return { quote, provider: { quote } as ReferralQuoteProvider };
}

describe('CheckoutService.start', () => {
  it('answers 503 until payments are configured, before touching anything', async () => {
    const { service, createOrder } = build({ configured: false });
    await expect(
      service.start('u1', { planCode: 'GOLD', months: 3 }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('refuses a duration that is not on sale (the shipped catalogue is unpriced)', async () => {
    const { service, createOrder } = build({ purchasable: false });
    await expect(
      service.start('u1', { planCode: 'GOLD', months: 3 }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('orders at the current price and records a PENDING subscription pinned to today’s version', async () => {
    const { service, createOrder, tx, repository } = build();
    const result = await service.start(
      'u1',
      { planCode: 'GOLD', months: 3 },
      NOW,
    );

    expect(createOrder).toHaveBeenCalledWith(
      expect.objectContaining({ amountInPaise: 300_000, currency: 'INR' }),
    );
    const [[{ data: subscription }]] = tx.userSubscription.create.mock
      .calls as [[{ data: { startDate: Date; endDate: Date } }]];
    expect(subscription).toMatchObject({
      userId: 'u1',
      planId: 'plan-GOLD',
      planVersionId: 'ver-GOLD-1',
      status: 'PENDING',
      priceInPaise: 300_000,
      source: 'PURCHASE',
    });
    // The term (90 days) is fixed now, as the provisional window's length.
    expect(
      subscription.endDate.getTime() - subscription.startDate.getTime(),
    ).toBe(90 * 24 * 3600 * 1000);
    const [[payment]] = tx.paymentTransaction.create.mock.calls as [
      [{ data: Record<string, unknown> }],
    ];
    expect(payment.data).toMatchObject({
      razorpayOrderId: 'order_1',
      amountInr: 300_000,
      status: 'PENDING',
      paidBy: 'MEMBER',
      // Test keys: no money moves, and the payment says so.
      livemode: false,
      listAmountPaise: 300_000,
      discountPaise: 0,
      discountSource: 'NONE',
      heldReferralCodeId: null,
      taxableAmountPaise: 300_000,
      taxRateBps: 0,
      taxPaise: 0,
    });
    expect(repository.recordEvent).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({
        type: 'CHECKOUT_CREATED',
        toStatus: 'PENDING',
      }),
    );
    expect(result).toMatchObject({
      orderId: 'order_1',
      keyId: 'rzp_test_key',
      months: 3,
      amountInPaise: 300_000,
      pricing: { totalPaise: 300_000, taxPaise: 0 },
      referral: null,
    });
  });

  it('adds GST on top of the price when the rate is set', async () => {
    const { service, createOrder, tx } = build({ gstRateBps: 1800 });
    const result = await service.start(
      'u1',
      { planCode: 'GOLD', months: 3 },
      NOW,
    );
    expect(createOrder).toHaveBeenCalledWith(
      expect.objectContaining({ amountInPaise: 354_000 }),
    );
    const [[payment]] = tx.paymentTransaction.create.mock.calls as [
      [{ data: Record<string, unknown> }],
    ];
    expect(payment.data).toMatchObject({
      amountInr: 354_000,
      taxableAmountPaise: 300_000,
      taxRateBps: 1800,
      taxPaise: 54_000,
    });
    expect(result.pricing).toEqual({
      listAmountPaise: 300_000,
      discountPaise: 0,
      discountSource: 'NONE',
      taxableAmountPaise: 300_000,
      taxRateBps: 1800,
      taxPaise: 54_000,
      totalPaise: 354_000,
    });
  });

  it.each([
    ['missing', undefined],
    ['not a whole number of basis points', 18.5],
    ['above 100%', 10_001],
  ])(
    'refuses to charge (503) while the GST setting is %s',
    async (_label, rate) => {
      const { service, createOrder } = build({ gstRateBps: rate });
      const error = await refusal(
        service.start('u1', { planCode: 'GOLD', months: 3 }, NOW),
      );
      expect(error.getStatus()).toBe(503);
      expect(error.getResponse()).toMatchObject({
        code: 'CHECKOUT_UNAVAILABLE',
      });
      expect(createOrder).not.toHaveBeenCalled();
    },
  );

  it('marks a payment made with live keys as live', async () => {
    const { service, tx } = build({ keyId: 'rzp_live_abc' });
    await service.start('u1', { planCode: 'GOLD', months: 3 }, NOW);
    const [[payment]] = tx.paymentTransaction.create.mock.calls as [
      [{ data: Record<string, unknown> }],
    ];
    expect(payment.data.livemode).toBe(true);
  });

  it('refuses a typed code while the agent program is not wired (422)', async () => {
    const { service, createOrder } = build();
    const error = await refusal(
      service.start(
        'u1',
        { planCode: 'GOLD', months: 3, promoCode: 'NM7K2P9X' },
        NOW,
      ),
    );
    expect(error.getStatus()).toBe(422);
    expect(error.getResponse()).toMatchObject({
      code: 'PROMO_CODES_UNAVAILABLE',
    });
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('applies the quoted referral discount, then GST, and holds the code', async () => {
    const { quote, provider } = quoting({
      discountPaise: 15_000,
      discountSource: 'REFERRAL_FIRST_PLAN',
      taxableAfterDiscountPaise: 285_000,
      heldReferralCodeId: 'code-1',
      agentDisplayName: 'Ravi K.',
    });
    const { service, createOrder, tx } = build({
      quote: provider,
      gstRateBps: 1800,
    });
    const result = await service.start(
      'u1',
      { planCode: 'GOLD', months: 3, promoCode: ' NM7K2P9X ' },
      NOW,
    );
    expect(quote).toHaveBeenCalledWith({
      memberId: 'u1',
      promoCode: 'NM7K2P9X',
      planPriceId: expect.any(String) as string,
      listAmountPaise: 300_000,
    });
    // 285000 + 18% (51300) = 336300
    expect(createOrder).toHaveBeenCalledWith(
      expect.objectContaining({ amountInPaise: 336_300 }),
    );
    const [[payment]] = tx.paymentTransaction.create.mock.calls as [
      [{ data: Record<string, unknown> }],
    ];
    expect(payment.data).toMatchObject({
      amountInr: 336_300,
      listAmountPaise: 300_000,
      discountPaise: 15_000,
      discountSource: 'REFERRAL_FIRST_PLAN',
      heldReferralCodeId: 'code-1',
      taxableAmountPaise: 285_000,
      taxPaise: 51_300,
    });
    expect(result.referral).toEqual({ agentDisplayName: 'Ravi K.' });
  });

  it('asks for a discount without a typed code too (signup attribution)', async () => {
    const { quote, provider } = quoting({});
    const { service } = build({ quote: provider });
    await service.start('u1', { planCode: 'GOLD', months: 3 }, NOW);
    expect(quote).toHaveBeenCalledWith(
      expect.objectContaining({ promoCode: null }),
    );
  });

  it('refuses a typed code that gives no discount, saying why (422)', async () => {
    const { provider } = quoting({ rejectedReason: 'NOT_FIRST_PLAN' });
    const { service, createOrder } = build({ quote: provider });
    const error = await refusal(
      service.start(
        'u1',
        { planCode: 'GOLD', months: 3, promoCode: 'NM7K2P9X' },
        NOW,
      ),
    );
    expect(error.getStatus()).toBe(422);
    expect(error.getResponse()).toMatchObject({
      code: 'PROMO_CODE_REJECTED',
      reason: 'NOT_FIRST_PLAN',
    });
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('never charges on a quote that does not add up (503)', async () => {
    const { provider } = quoting({
      discountPaise: 15_000,
      discountSource: 'REFERRAL_FIRST_PLAN',
      taxableAfterDiscountPaise: 290_000,
    });
    const { service, createOrder } = build({ quote: provider });
    const error = await refusal(
      service.start('u1', { planCode: 'GOLD', months: 3 }, NOW),
    );
    expect(error.getStatus()).toBe(503);
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('refuses (503) rather than guessing when the quote service fails', async () => {
    const quote = jest.fn().mockRejectedValue(new Error('db down'));
    const { service, createOrder } = build({ quote: { quote } });
    const error = await refusal(
      service.start('u1', { planCode: 'GOLD', months: 3 }, NOW),
    );
    expect(error.getResponse()).toMatchObject({ code: 'CHECKOUT_UNAVAILABLE' });
    expect(createOrder).not.toHaveBeenCalled();
  });

  it('registers the GST validator for the admin settings API', () => {
    const { service, settings } = build();
    service.onModuleInit();
    const [[key, validate]] = settings.registerValidator.mock.calls as [
      [string, (v: unknown) => string | null],
    ];
    expect(key).toBe('payment.gst_rate_bps');
    expect(validate(1800)).toBeNull();
    expect(validate(-1)).toMatch(/0 to 10000/);
  });
});

describe('CheckoutService.verify', () => {
  const sign = (order: string, payment: string) =>
    createHmac('sha256', 'key-secret')
      .update(`${order}|${payment}`)
      .digest('hex');

  it('refuses a payment whose signature does not verify, activating nothing', async () => {
    const { service, lifecycle } = build();
    await expect(
      service.verify('u1', {
        orderId: 'order_1',
        paymentId: 'pay_1',
        signature: sign('order_1', 'pay_X'),
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it("refuses to confirm someone else's order", async () => {
    const { service, repository, lifecycle } = build();
    repository.findPaymentByOrderId.mockResolvedValueOnce({
      userId: 'someone-else',
      subscriptionId: 's',
    });
    await expect(
      service.verify('u1', {
        orderId: 'order_1',
        paymentId: 'pay_1',
        signature: sign('order_1', 'pay_1'),
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  const verify = (service: CheckoutService) =>
    service.verify('u1', {
      orderId: 'order_1',
      paymentId: 'pay_1',
      signature: sign('order_1', 'pay_1'),
    });

  it("activates with the amount and currency from RAZORPAY's record, never the client's", async () => {
    const { service, lifecycle, fetchPayment } = build();
    const result = await verify(service);
    expect(fetchPayment).toHaveBeenCalledWith('pay_1');
    expect(lifecycle.confirmPayment).toHaveBeenCalledWith(expect.anything(), {
      orderId: 'order_1',
      paymentId: 'pay_1',
      amountInPaise: 300_000,
      currency: 'INR',
      actorId: 'u1',
      via: 'CHECKOUT_VERIFY',
      paymentSourceHash: null,
    });
    expect(result).toMatchObject({ outcome: 'ACTIVATED', status: 'ACTIVE' });
  });

  it('hashes the payer’s UPI id, and delivers the payment event after commit', async () => {
    const { service, lifecycle, fetchPayment, dispatcher } = build();
    fetchPayment.mockResolvedValueOnce({
      id: 'pay_1',
      orderId: 'order_1',
      amount: 300_000,
      currency: 'INR',
      status: 'captured',
      vpa: 'priya@okicici',
    });
    await verify(service);
    expect(lifecycle.confirmPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ paymentSourceHash: 'v1:UPI:priya@okicici' }),
    );
    expect(dispatcher.dispatchSoon).toHaveBeenCalledTimes(1);
  });

  it('grants nothing for a payment that is only authorized, not captured', async () => {
    const { service, lifecycle, fetchPayment, tx } = build();
    fetchPayment.mockResolvedValueOnce({
      id: 'pay_1',
      orderId: 'order_1',
      amount: 300_000,
      currency: 'INR',
      status: 'authorized',
      vpa: null,
    });
    tx.userSubscription.findUnique.mockResolvedValueOnce({
      status: 'PENDING',
      startDate: NOW,
      endDate: NOW,
    });
    expect(await verify(service)).toEqual({
      outcome: 'AWAITING_CAPTURE',
      subscriptionId: 'sub-1',
      status: 'PENDING',
      startDate: null,
      endDate: null,
    });
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it('leaves the purchase pending, not guessed, when Razorpay is unreachable', async () => {
    const { service, lifecycle, fetchPayment } = build();
    fetchPayment.mockResolvedValueOnce(null);
    expect((await verify(service)).outcome).toBe('PENDING_CONFIRMATION');
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it('refuses a validly signed payment that Razorpay says belongs to another order', async () => {
    const { service, lifecycle, fetchPayment } = build();
    fetchPayment.mockResolvedValueOnce({
      id: 'pay_1',
      orderId: 'order_OTHER',
      amount: 300_000,
      currency: 'INR',
      status: 'captured',
      vpa: null,
    });
    await expect(verify(service)).rejects.toBeInstanceOf(BadRequestException);
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });

  it.each([
    ['failed', 'NOT_PAID'],
    ['refunded', 'REFUNDED'],
  ] as const)('grants nothing for a %s payment', async (status, outcome) => {
    const { service, lifecycle, fetchPayment } = build();
    fetchPayment.mockResolvedValueOnce({
      id: 'pay_1',
      orderId: 'order_1',
      amount: 300_000,
      currency: 'INR',
      status,
      vpa: null,
    });
    expect((await verify(service)).outcome).toBe(outcome);
    expect(lifecycle.confirmPayment).not.toHaveBeenCalled();
  });
});
