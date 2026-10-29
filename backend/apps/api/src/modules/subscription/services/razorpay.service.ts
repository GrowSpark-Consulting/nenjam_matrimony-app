import {
  BadGatewayException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { AppConfigService } from '@app/config';

const ORDERS_URL = 'https://api.razorpay.com/v1/orders';
const PAYMENTS_URL = 'https://api.razorpay.com/v1/payments';
const ORDER_TIMEOUT_MS = 10_000;

export interface CreateOrderInput {
  amountInPaise: number;
  currency: string;
  /** Our reference, max 40 chars — the subscription id. */
  receipt: string;
  notes: Record<string, string>;
}

export interface RazorpayOrder {
  id: string;
  amount: number;
  currency: string;
}

/** Razorpay's own record of a payment — the authority on whether money was
 *  actually taken. Only `captured` means it was. */
export interface RazorpayPayment {
  id: string;
  orderId: string | null;
  amount: number;
  currency: string;
  status: 'created' | 'authorized' | 'captured' | 'refunded' | 'failed';
  /** The payer's UPI id, for UPI payments; null otherwise. */
  vpa: string | null;
}

/** Constant-time comparison of two hex HMAC digests. */
function digestsMatch(expectedHex: string, receivedHex: string): boolean {
  const expected = Buffer.from(expectedHex, 'hex');
  const received = Buffer.from(receivedHex, 'hex');
  return (
    expected.length === received.length && timingSafeEqual(expected, received)
  );
}

/**
 * The Razorpay boundary: order creation, payment lookup and the two
 * signature checks. Holds no business logic — CheckoutService and
 * RazorpayWebhookService decide what a verified payment means.
 *
 * Inert without configuration: every method that needs a credential answers
 * 503 (mirroring face verification), so the app boots and CI runs with no
 * Razorpay secrets at all.
 *
 * Verified by unit tests (signatures against independently computed HMACs;
 * order creation against a mocked HTTP layer). NOT yet exercised against the
 * live Razorpay API — run the sandbox checklist in docs/membership/README.md
 * before enabling it in production.
 */
@Injectable()
export class RazorpayService {
  private readonly logger = new Logger(RazorpayService.name);

  constructor(private readonly config: AppConfigService) {}

  /** Checkout needs the key pair; the webhook needs its own secret. */
  isCheckoutConfigured(): boolean {
    const { keyId, keySecret } = this.config.razorpay ?? {};
    return Boolean(keyId && keySecret);
  }

  isWebhookConfigured(): boolean {
    return Boolean(this.config.razorpay?.webhookSecret);
  }

  /** The public key id the client's Razorpay Checkout opens with. */
  publicKeyId(): string {
    return this.requireKeys().keyId;
  }

  /** False with TEST keys (`rzp_test_`): no money moves. Only an
   *  `rzp_live_` key is live; anything else is treated as test. */
  isLiveMode(): boolean {
    return this.requireKeys().keyId.startsWith('rzp_live_');
  }

  async createOrder(input: CreateOrderInput): Promise<RazorpayOrder> {
    const { keyId, keySecret } = this.requireKeys();
    const response = await fetch(ORDERS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
      },
      body: JSON.stringify({
        amount: input.amountInPaise,
        currency: input.currency,
        receipt: input.receipt,
        notes: input.notes,
      }),
      signal: AbortSignal.timeout(ORDER_TIMEOUT_MS),
    }).catch((error: unknown) => {
      this.logger.error(
        `Razorpay order request failed: ${(error as Error).message}`,
      );
      throw new BadGatewayException(
        'The payment service is not reachable. Please try again.',
      );
    });

    if (!response.ok) {
      // Never log the body wholesale — log status and Razorpay's error code.
      const detail = (await response.json().catch(() => ({}))) as {
        error?: { code?: string };
      };
      this.logger.error(
        `Razorpay order creation failed: HTTP ${response.status} ${detail.error?.code ?? ''}`,
      );
      throw new BadGatewayException(
        'The payment could not be started. Please try again.',
      );
    }
    const order = (await response.json()) as Partial<RazorpayOrder>;
    if (
      typeof order.id !== 'string' ||
      order.amount !== input.amountInPaise ||
      order.currency !== input.currency
    ) {
      this.logger.error(
        'Razorpay returned an order that does not match the request.',
      );
      throw new BadGatewayException(
        'The payment could not be started. Please try again.',
      );
    }
    return { id: order.id, amount: order.amount, currency: order.currency };
  }

  /**
   * Razorpay's record of [paymentId] (GET /v1/payments/:id), or null when it
   * can't be read right now (Razorpay unreachable or erroring) — the caller
   * then leaves the purchase pending for the webhook rather than guessing.
   */
  async fetchPayment(paymentId: string): Promise<RazorpayPayment | null> {
    const { keyId, keySecret } = this.requireKeys();
    try {
      const response = await fetch(
        `${PAYMENTS_URL}/${encodeURIComponent(paymentId)}`,
        {
          headers: {
            Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
          },
          signal: AbortSignal.timeout(ORDER_TIMEOUT_MS),
        },
      );
      if (!response.ok) {
        this.logger.error(
          `Razorpay payment lookup failed: HTTP ${response.status}`,
        );
        return null;
      }
      const payment = (await response.json()) as {
        id?: unknown;
        order_id?: unknown;
        amount?: unknown;
        currency?: unknown;
        status?: unknown;
        vpa?: unknown;
      };
      if (
        typeof payment.id !== 'string' ||
        typeof payment.amount !== 'number' ||
        typeof payment.currency !== 'string' ||
        typeof payment.status !== 'string'
      ) {
        this.logger.error('Razorpay returned a malformed payment record.');
        return null;
      }
      return {
        id: payment.id,
        orderId: typeof payment.order_id === 'string' ? payment.order_id : null,
        amount: payment.amount,
        currency: payment.currency,
        status: payment.status as RazorpayPayment['status'],
        vpa: typeof payment.vpa === 'string' ? payment.vpa : null,
      };
    } catch (error) {
      this.logger.error(
        `Razorpay payment lookup failed: ${(error as Error).message}`,
      );
      return null;
    }
  }

  /**
   * The checkout handler's signature: HMAC-SHA256 of "order_id|payment_id"
   * keyed with the key secret. Proves Razorpay authorised this payment for
   * THIS order (whose amount we fixed when creating it).
   */
  verifyPaymentSignature(
    orderId: string,
    paymentId: string,
    signature: string,
  ): boolean {
    const { keySecret } = this.requireKeys();
    const expected = createHmac('sha256', keySecret)
      .update(`${orderId}|${paymentId}`)
      .digest('hex');
    return digestsMatch(expected, signature);
  }

  /** A webhook delivery's X-Razorpay-Signature: HMAC-SHA256 of the RAW
   *  request body keyed with the webhook secret. */
  verifyWebhookSignature(rawBody: Buffer, signature: string): boolean {
    const secret = this.config.razorpay?.webhookSecret;
    if (!secret) {
      throw new ServiceUnavailableException(
        'Payment webhooks are not configured.',
      );
    }
    const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
    return digestsMatch(expected, signature);
  }

  private requireKeys(): { keyId: string; keySecret: string } {
    const { keyId, keySecret } = this.config.razorpay ?? {};
    if (!keyId || !keySecret) {
      throw new ServiceUnavailableException('Payments are not available yet.');
    }
    return { keyId, keySecret };
  }
}
