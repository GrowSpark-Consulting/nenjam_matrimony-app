import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  type OnModuleInit,
  Optional,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { ReferralQuoteProvider, ReferralQuoteResult } from '@app/common';
import { PrismaService } from '@app/database';
import { AGENT_REFERRAL_QUOTE } from '../../agents/agent-referral-quote.token';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import {
  GST_RATE_SETTING,
  parseGstRateBps,
  priceCheckout,
  PricingError,
  type CheckoutPricing,
} from '../domain/pricing';
import { PaymentEventDispatcher } from '../events/payment-event-outbox';
import { paymentSourceHashOf } from '../events/payment-events';
import { CheckoutDto, VerifyCheckoutDto } from '../dto/checkout.dto';
import type {
  CheckoutResponseDto,
  VerifyCheckoutResponseDto,
  VerifyOutcome,
} from '../dto/checkout.dto';
import { RazorpayService } from './razorpay.service';
import { SubscriptionLifecycleService } from './subscription-lifecycle.service';
import { SubscriptionRepository } from '../repositories/subscription.repository';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Buying a plan, in two steps the client drives:
 *
 *  1. `start` — validates the plan and duration are on sale, prices the
 *     purchase (list price − referral discount, GST added on top; see
 *     domain/pricing.ts), creates a Razorpay order for that total, and
 *     records a PENDING subscription + PENDING payment carrying the whole
 *     breakdown. The subscription pins the entitlement version and the price
 *     on sale at this moment, so what the member saw is what they get.
 *     PENDING grants nothing.
 *  2. `verify` — checks the Razorpay signature, then asks Razorpay for the
 *     payment itself and activates only if it is CAPTURED for this order at
 *     the checkout amount. The client never supplies a status or an amount.
 *     The webhook (RazorpayWebhookService) activates the same order
 *     independently; whichever arrives first wins, the other is a no-op.
 *
 * Both answer 503 until Razorpay is configured; `start` also while the GST
 * setting is missing (there is no default rate in code).
 *
 * The referral discount comes from the agent program's quote service
 * (AGENT_REFERRAL_QUOTE), injected optionally: without it there is no
 * discount and a typed promo code is refused.
 */
@Injectable()
export class CheckoutService implements OnModuleInit {
  private readonly logger = new Logger(CheckoutService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
    private readonly razorpay: RazorpayService,
    private readonly lifecycle: SubscriptionLifecycleService,
    private readonly repository: SubscriptionRepository,
    private readonly settings: PlatformSettingsService,
    private readonly hasher: IdentifierHashService,
    private readonly dispatcher: PaymentEventDispatcher,
    @Optional()
    @Inject(AGENT_REFERRAL_QUOTE)
    private readonly referralQuote?: ReferralQuoteProvider,
  ) {}

  /** The admin settings API refuses a GST rate checkout couldn't use. */
  onModuleInit(): void {
    this.settings.registerValidator(GST_RATE_SETTING, (value) =>
      parseGstRateBps(value) === null
        ? `${GST_RATE_SETTING} must be an integer from 0 to 10000 (basis points: 1800 = 18%).`
        : null,
    );
  }

  async start(
    userId: string,
    dto: CheckoutDto,
    now: Date = new Date(),
  ): Promise<CheckoutResponseDto> {
    // Fail before touching the catalogue or the provider when unconfigured.
    const keyId = this.razorpay.publicKeyId();

    const plan = await this.catalog.findPlan(dto.planCode);
    if (!plan || !plan.isActive || plan.code === 'FREE') {
      throw new BadRequestException('That plan is not available.');
    }
    const duration = plan.durations.find(
      (d) => d.months === dto.months && d.isActive && d.priceInPaise !== null,
    );
    if (!duration || duration.priceInPaise === null) {
      throw new BadRequestException(
        `${plan.name} is not available for ${dto.months} months.`,
      );
    }
    const version = this.catalog.versionEffectiveAt(plan, now);
    if (!version) {
      throw new BadRequestException('That plan is not available.');
    }

    const promoCode = dto.promoCode?.trim() || null;
    const quote = await this.quoteReferral(
      userId,
      promoCode,
      duration.id,
      duration.priceInPaise,
    );
    const pricing = this.price(
      duration.priceInPaise,
      quote,
      await this.gstRateBps(),
    );
    const livemode = this.razorpay.isLiveMode();

    const subscriptionId = randomUUID();
    const order = await this.razorpay.createOrder({
      amountInPaise: pricing.totalPaise,
      currency: duration.currency,
      receipt: subscriptionId,
      notes: {
        userId,
        subscriptionId,
        plan: plan.code,
        months: String(duration.months),
        listPaise: String(pricing.listAmountPaise),
        discountPaise: String(pricing.discountPaise),
        taxPaise: String(pricing.taxPaise),
      },
    });

    // Provisional window: its LENGTH is the term bought (duration + bonus).
    // Activation re-anchors the start (now, or queued behind a current plan)
    // and keeps this length, so a later price-list edit can't change it.
    const termMs = (duration.durationDays + duration.bonusDays) * DAY_MS;
    await this.prisma.$transaction(async (tx) => {
      await tx.userSubscription.create({
        data: {
          id: subscriptionId,
          userId,
          planId: plan.id,
          planVersionId: version.id,
          durationId: duration.id,
          status: 'PENDING',
          startDate: now,
          endDate: new Date(now.getTime() + termMs),
          priceInPaise: duration.priceInPaise,
          currency: duration.currency,
          source: 'PURCHASE',
        },
      });
      await tx.paymentTransaction.create({
        data: {
          userId,
          subscriptionId,
          razorpayOrderId: order.id,
          amountInr: pricing.totalPaise,
          currency: duration.currency,
          status: 'PENDING',
          paidBy: 'MEMBER',
          livemode,
          listAmountPaise: pricing.listAmountPaise,
          discountPaise: pricing.discountPaise,
          discountSource: pricing.discountSource,
          heldReferralCodeId: pricing.heldReferralCodeId,
          taxableAmountPaise: pricing.taxableAmountPaise,
          taxRateBps: pricing.taxRateBps,
          taxPaise: pricing.taxPaise,
        },
      });
      await this.repository.recordEvent(tx, {
        subscriptionId,
        userId,
        type: 'CHECKOUT_CREATED',
        toStatus: 'PENDING',
        actorId: userId,
        metadata: {
          orderId: order.id,
          plan: plan.code,
          months: duration.months,
          priceInPaise: duration.priceInPaise,
          planVersion: version.version,
          discountPaise: pricing.discountPaise,
          taxRateBps: pricing.taxRateBps,
          taxPaise: pricing.taxPaise,
          totalPaise: pricing.totalPaise,
          livemode,
        },
      });
    });

    return {
      subscriptionId,
      orderId: order.id,
      amountInPaise: pricing.totalPaise,
      currency: duration.currency,
      keyId,
      plan: { code: plan.code, name: plan.name },
      months: duration.months,
      pricing: {
        listAmountPaise: pricing.listAmountPaise,
        discountPaise: pricing.discountPaise,
        discountSource: pricing.discountSource,
        taxableAmountPaise: pricing.taxableAmountPaise,
        taxRateBps: pricing.taxRateBps,
        taxPaise: pricing.taxPaise,
        totalPaise: pricing.totalPaise,
      },
      referral:
        pricing.discountSource === 'NONE'
          ? null
          : { agentDisplayName: quote?.agentDisplayName ?? null },
    };
  }

  /**
   * The agent program's quote, or null without one. A typed code that gives
   * no discount is refused (422) rather than silently charged in full; a
   * failing quote service refuses the checkout (503) rather than guessing.
   */
  private async quoteReferral(
    memberId: string,
    promoCode: string | null,
    planPriceId: string,
    listAmountPaise: number,
  ): Promise<ReferralQuoteResult | null> {
    if (!this.referralQuote) {
      if (promoCode) {
        throw checkoutError(
          HttpStatus.UNPROCESSABLE_ENTITY,
          'PROMO_CODES_UNAVAILABLE',
          'Referral codes can’t be used yet. Remove the code to continue.',
        );
      }
      return null;
    }
    let quote: ReferralQuoteResult;
    try {
      quote = await this.referralQuote.quote({
        memberId,
        promoCode,
        planPriceId,
        listAmountPaise,
      });
    } catch (error) {
      this.logger.error(
        `Referral quote failed for a checkout: ${(error as Error).message}`,
      );
      throw checkoutUnavailable();
    }
    if (promoCode && quote.discountSource === 'NONE') {
      throw checkoutError(
        HttpStatus.UNPROCESSABLE_ENTITY,
        'PROMO_CODE_REJECTED',
        'That code can’t be used for this purchase.',
        { reason: quote.rejectedReason ?? 'NOT_APPLICABLE' },
      );
    }
    return quote;
  }

  /** The GST rate setting; 503 while it is missing or unusable. */
  private async gstRateBps(): Promise<number> {
    const values = await this.settings.getMany([GST_RATE_SETTING]);
    const rate = parseGstRateBps(values[GST_RATE_SETTING]);
    if (rate === null) {
      this.logger.error(
        `${GST_RATE_SETTING} is missing or not an integer 0–10000: checkout refused.`,
      );
      throw checkoutUnavailable();
    }
    return rate;
  }

  private price(
    listAmountPaise: number,
    quote: ReferralQuoteResult | null,
    taxRateBps: number,
  ): CheckoutPricing {
    try {
      return priceCheckout(listAmountPaise, quote, taxRateBps);
    } catch (error) {
      if (
        error instanceof PricingError &&
        error.code === 'BELOW_MINIMUM_CHARGE'
      ) {
        throw new BadRequestException('That plan is not available.');
      }
      // A quote that doesn't add up: never charge on it.
      this.logger.error(`Checkout refused: ${(error as Error).message}`);
      throw checkoutUnavailable();
    }
  }

  async verify(
    userId: string,
    dto: VerifyCheckoutDto,
  ): Promise<VerifyCheckoutResponseDto> {
    if (
      !this.razorpay.verifyPaymentSignature(
        dto.orderId,
        dto.paymentId,
        dto.signature,
      )
    ) {
      throw new BadRequestException('Payment verification failed.');
    }

    // Ownership before anything else — and the same answer for "no such
    // order" and "someone else's order".
    const payment = await this.repository.findPaymentByOrderId(
      this.prisma,
      dto.orderId,
    );
    if (!payment || payment.userId !== userId) {
      throw new NotFoundException('Payment not found.');
    }

    // The signature proves Razorpay saw this payment for this order — not
    // that money was taken. Only Razorpay's own record says that, so it is
    // fetched, and only a CAPTURED payment for this order, at the amount and
    // currency fixed at checkout, activates anything.
    const provider = await this.razorpay.fetchPayment(dto.paymentId);
    let outcome: VerifyOutcome;
    if (!provider) {
      // Razorpay unreachable: don't guess. The webhook will confirm it.
      outcome = 'PENDING_CONFIRMATION';
    } else if (provider.orderId !== dto.orderId) {
      throw new BadRequestException('Payment verification failed.');
    } else if (provider.status === 'captured') {
      outcome = await this.prisma.$transaction((tx) =>
        this.lifecycle.confirmPayment(tx, {
          orderId: dto.orderId,
          paymentId: dto.paymentId,
          amountInPaise: provider.amount,
          currency: provider.currency,
          actorId: userId,
          via: 'CHECKOUT_VERIFY',
          paymentSourceHash: paymentSourceHashOf(this.hasher, provider.vpa),
        }),
      );
      this.dispatcher.dispatchSoon();
    } else if (
      provider.status === 'authorized' ||
      provider.status === 'created'
    ) {
      // Not captured yet: the payment.captured webhook will activate it.
      outcome = 'AWAITING_CAPTURE';
    } else {
      outcome = provider.status === 'refunded' ? 'REFUNDED' : 'NOT_PAID';
    }

    const subscription = await this.prisma.userSubscription.findUnique({
      where: { id: payment.subscriptionId },
      select: { status: true, startDate: true, endDate: true },
    });
    const active = subscription?.status === 'ACTIVE';
    return {
      outcome,
      subscriptionId: payment.subscriptionId,
      status: subscription?.status ?? 'PENDING',
      // Dates only once they are real; a PENDING row's are provisional.
      startDate: active ? subscription.startDate.toISOString() : null,
      endDate: active ? subscription.endDate.toISOString() : null,
    };
  }
}

/** The `{ statusCode, error, code, message }` body the app branches on. */
function checkoutError(
  status: HttpStatus.UNPROCESSABLE_ENTITY | HttpStatus.SERVICE_UNAVAILABLE,
  code: string,
  message: string,
  extra?: Record<string, unknown>,
): HttpException {
  return new HttpException(
    {
      statusCode: status,
      error:
        status === HttpStatus.UNPROCESSABLE_ENTITY
          ? 'Unprocessable Entity'
          : 'Service Unavailable',
      code,
      message,
      ...extra,
    },
    status,
  );
}

function checkoutUnavailable(): HttpException {
  return checkoutError(
    HttpStatus.SERVICE_UNAVAILABLE,
    'CHECKOUT_UNAVAILABLE',
    'Payments are temporarily unavailable. Please try again shortly.',
  );
}
