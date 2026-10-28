import {
  BadGatewayException,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHmac } from 'node:crypto';
import { RazorpayService } from '../services/razorpay.service';

const KEYS = {
  keyId: 'rzp_test_key',
  keySecret: 'key-secret',
  webhookSecret: 'webhook-secret',
};

function service(razorpay: Partial<typeof KEYS> = KEYS): RazorpayService {
  return new RazorpayService({ razorpay } as never);
}

const hmac = (secret: string, data: string | Buffer) =>
  createHmac('sha256', secret).update(data).digest('hex');

describe('RazorpayService — signatures', () => {
  it('accepts the checkout signature Razorpay computes over "order_id|payment_id"', () => {
    const signature = hmac('key-secret', 'order_1|pay_1');
    expect(
      service().verifyPaymentSignature('order_1', 'pay_1', signature),
    ).toBe(true);
  });

  it('rejects a signature for a different payment, a wrong secret, or garbage', () => {
    const rz = service();
    expect(
      rz.verifyPaymentSignature(
        'order_1',
        'pay_2',
        hmac('key-secret', 'order_1|pay_1'),
      ),
    ).toBe(false);
    expect(
      rz.verifyPaymentSignature(
        'order_1',
        'pay_1',
        hmac('other', 'order_1|pay_1'),
      ),
    ).toBe(false);
    expect(rz.verifyPaymentSignature('order_1', 'pay_1', 'zz')).toBe(false);
    expect(rz.verifyPaymentSignature('order_1', 'pay_1', '')).toBe(false);
  });

  it('verifies a webhook over the exact raw bytes, and nothing else', () => {
    const raw = Buffer.from('{"event":"payment.captured","x":1}');
    const rz = service();
    expect(rz.verifyWebhookSignature(raw, hmac('webhook-secret', raw))).toBe(
      true,
    );
    // Same JSON, re-serialised with different whitespace: not the signed bytes.
    const reserialised = Buffer.from('{"event": "payment.captured", "x": 1}');
    expect(
      rz.verifyWebhookSignature(reserialised, hmac('webhook-secret', raw)),
    ).toBe(false);
  });

  it('is inert without configuration — 503, never a silent pass', () => {
    const rz = service({});
    expect(rz.isCheckoutConfigured()).toBe(false);
    expect(rz.isWebhookConfigured()).toBe(false);
    expect(() => rz.verifyPaymentSignature('o', 'p', 'aa')).toThrow(
      ServiceUnavailableException,
    );
    expect(() => rz.verifyWebhookSignature(Buffer.from('x'), 'aa')).toThrow(
      ServiceUnavailableException,
    );
    expect(() => rz.publicKeyId()).toThrow(ServiceUnavailableException);
  });
});

describe('RazorpayService.createOrder', () => {
  const realFetch = global.fetch;
  afterEach(() => {
    global.fetch = realFetch;
    jest.restoreAllMocks();
  });

  function mockFetch(status: number, body: unknown) {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(body),
    });
    global.fetch = fetchMock as never;
    return fetchMock;
  }

  const input = {
    amountInPaise: 499_900,
    currency: 'INR',
    receipt: 'sub-1',
    notes: { userId: 'u1' },
  };

  it('creates an order with basic auth and the exact amount', async () => {
    const fetchMock = mockFetch(200, {
      id: 'order_1',
      amount: 499_900,
      currency: 'INR',
    });
    await expect(service().createOrder(input)).resolves.toEqual({
      id: 'order_1',
      amount: 499_900,
      currency: 'INR',
    });
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://api.razorpay.com/v1/orders');
    expect((init.headers as Record<string, string>).Authorization).toBe(
      `Basic ${Buffer.from('rzp_test_key:key-secret').toString('base64')}`,
    );
    expect(JSON.parse(init.body as string)).toEqual({
      amount: 499_900,
      currency: 'INR',
      receipt: 'sub-1',
      notes: { userId: 'u1' },
    });
  });

  it('refuses an order whose amount does not match what was asked for', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    mockFetch(200, { id: 'order_1', amount: 100, currency: 'INR' });
    await expect(service().createOrder(input)).rejects.toBeInstanceOf(
      BadGatewayException,
    );
  });

  it('turns a provider error into a 502 without leaking its body', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    mockFetch(401, {
      error: { code: 'BAD_REQUEST_ERROR', description: 'secret stuff' },
    });
    const error = await service()
      .createOrder(input)
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(BadGatewayException);
    expect(
      JSON.stringify((error as BadGatewayException).getResponse()),
    ).not.toContain('secret');
  });
});

describe('RazorpayService.fetchPayment', () => {
  const realFetch = global.fetch;
  afterEach(() => {
    global.fetch = realFetch;
    jest.restoreAllMocks();
  });

  function mockFetch(impl: () => Promise<unknown>) {
    const fetchMock = jest.fn(impl);
    global.fetch = fetchMock as never;
    return fetchMock;
  }

  it("returns Razorpay's own record: status, order, amount, currency", async () => {
    const fetchMock = mockFetch(() =>
      Promise.resolve({
        ok: true,
        status: 200,
        json: () =>
          Promise.resolve({
            id: 'pay_1',
            order_id: 'order_1',
            amount: 499_900,
            currency: 'INR',
            status: 'captured',
            email: 'payer@example.in',
          }),
      }),
    );
    await expect(service().fetchPayment('pay_1')).resolves.toEqual({
      id: 'pay_1',
      orderId: 'order_1',
      amount: 499_900,
      currency: 'INR',
      status: 'captured',
    });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ];
    expect(url).toBe('https://api.razorpay.com/v1/payments/pay_1');
    expect((init.headers as Record<string, string>).Authorization).toMatch(
      /^Basic /,
    );
  });

  it('never lets a payment id escape the payments path', async () => {
    const fetchMock = mockFetch(() =>
      Promise.resolve({
        ok: false,
        status: 404,
        json: () => Promise.resolve({}),
      }),
    );
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    await service().fetchPayment('../orders?x=1');
    const [[url]] = fetchMock.mock.calls as unknown as [[string]];
    expect(url).toBe(
      'https://api.razorpay.com/v1/payments/..%2Forders%3Fx%3D1',
    );
  });

  it.each([
    [
      'an HTTP error',
      () =>
        Promise.resolve({
          ok: false,
          status: 500,
          json: () => Promise.resolve({}),
        }),
    ],
    ['a network failure', () => Promise.reject(new Error('ECONNRESET'))],
    [
      'a malformed record',
      () =>
        Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve({ id: 'pay_1' }),
        }),
    ],
  ])('returns null (never a guess) on %s', async (_label, impl) => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    mockFetch(impl);
    await expect(service().fetchPayment('pay_1')).resolves.toBeNull();
  });

  it('is 503 without keys', async () => {
    await expect(service({}).fetchPayment('pay_1')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
