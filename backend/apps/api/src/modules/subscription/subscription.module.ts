import { Module } from '@nestjs/common';
import { REFERRAL_EVENT_PUBLISHER } from '@app/common';
import { AppConfigModule } from '@app/config';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { PlatformModule } from '../platform/platform.module';
import { PaymentEventDispatcher } from './events/payment-event-outbox';
import { ReferralEventBus } from './events/referral-event-bus';
import { PlansController } from './controllers/plans.controller';
import { CheckoutController } from './controllers/checkout.controller';
import { RazorpayWebhookController } from './controllers/razorpay-webhook.controller';
import { PlansService } from './services/plans.service';
import { CheckoutService } from './services/checkout.service';
import { RazorpayService } from './services/razorpay.service';
import { RazorpayWebhookService } from './services/razorpay-webhook.service';
import { SubscriptionLifecycleService } from './services/subscription-lifecycle.service';
import { PlanCatalogAdminService } from './services/plan-catalog-admin.service';
import { PlanDraftService } from './services/plan-draft.service';
import { RazorpaySignatureGuard } from './guards/razorpay-signature.guard';
import { SubscriptionRepository } from './repositories/subscription.repository';

/**
 * Membership write side: buying (checkout + Razorpay), the subscription
 * lifecycle, and the admin-ready catalogue service. Reads entitlements from
 * EntitlementsModule; nothing imports this module back.
 *
 * Exports the services the admin module wraps (PlanCatalogAdminService,
 * PlanDraftService, SubscriptionLifecycleService) — there is deliberately no
 * admin HTTP surface in this module; /admin/* lives in AdminModule.
 *
 * Payment events: ReferralEventBus (also as REFERRAL_EVENT_PUBLISHER) is where
 * the agent program subscribes; PaymentEventDispatcher delivers the outbox.
 */
@Module({
  imports: [AppConfigModule, EntitlementsModule, PlatformModule],
  controllers: [PlansController, CheckoutController, RazorpayWebhookController],
  providers: [
    PlansService,
    CheckoutService,
    RazorpayService,
    RazorpayWebhookService,
    SubscriptionLifecycleService,
    PlanCatalogAdminService,
    PlanDraftService,
    RazorpaySignatureGuard,
    ReferralEventBus,
    { provide: REFERRAL_EVENT_PUBLISHER, useExisting: ReferralEventBus },
    PaymentEventDispatcher,
    SubscriptionRepository,
  ],
  exports: [
    PlanCatalogAdminService,
    PlanDraftService,
    SubscriptionLifecycleService,
    ReferralEventBus,
    REFERRAL_EVENT_PUBLISHER,
    PaymentEventDispatcher,
  ],
})
export class SubscriptionModule {}
