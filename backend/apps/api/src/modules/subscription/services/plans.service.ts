import { Injectable } from '@nestjs/common';
import {
  FEATURE_KEYS,
  FEATURES,
  type FeatureDefinition,
} from '../../entitlements/catalog/feature-catalog';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { MembershipService } from '../../entitlements/services/membership.service';
import type {
  FeatureDescriptorDto,
  MyMembershipResponseDto,
  PlanCatalogResponseDto,
  PlanDto,
  PurchaseOptionDto,
  SubscriptionHistoryItemDto,
} from '../dto/plan.response.dto';
import { SubscriptionRepository } from '../repositories/subscription.repository';
import { windowFor } from '../domain/schedule';
import { RazorpayService } from './razorpay.service';

const HISTORY_LIMIT = 50;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Read models for the member-facing membership API. Display only — every
 * decision about what a member may do is MembershipService's, server-side.
 */
@Injectable()
export class PlansService {
  constructor(
    private readonly catalog: PlanCatalogService,
    private readonly membership: MembershipService,
    private readonly repository: SubscriptionRepository,
    private readonly razorpay: RazorpayService,
  ) {}

  async listPlans(now: Date = new Date()): Promise<PlanCatalogResponseDto> {
    const { plans } = await this.catalog.getCatalog(now);
    const visible: PlanDto[] = [];
    for (const plan of plans) {
      if (!plan.isActive) continue;
      const version = this.catalog.versionEffectiveAt(plan, now);
      if (!version) continue;
      visible.push({
        code: plan.code,
        name: plan.name,
        description: plan.description,
        tier: plan.tier,
        isFree: plan.code === 'FREE',
        durations: plan.durations
          .filter((d) => d.isActive && d.priceInPaise !== null)
          .map((d) => ({
            months: d.months,
            durationDays: d.durationDays,
            bonusDays: d.bonusDays,
            priceInPaise: d.priceInPaise!,
            currency: d.currency,
          })),
        entitlements: version.entitlements,
        version: version.version,
      });
    }
    return {
      plans: visible,
      features: FEATURE_KEYS.map(describeFeature),
      checkoutAvailable: this.razorpay.isCheckoutConfigured(),
    };
  }

  async myMembership(
    userId: string,
    now: Date = new Date(),
  ): Promise<MyMembershipResponseDto> {
    const [{ membership, usage, effectiveCaps }, scheduled, held, catalog] =
      await Promise.all([
        this.membership.summarize(userId, now),
        this.repository.findScheduled(userId, now),
        this.repository.findHeld(userId, now),
        this.catalog.getCatalog(now),
      ]);
    const subscription = membership.subscription;

    const purchaseOptions: PurchaseOptionDto[] = [];
    for (const plan of catalog.plans) {
      if (!plan.isActive || plan.code === 'FREE') continue;
      for (const duration of plan.durations) {
        if (!duration.isActive || duration.priceInPaise === null) continue;
        const window = windowFor(
          held,
          plan.tier,
          (duration.durationDays + duration.bonusDays) * DAY_MS,
          now,
        );
        purchaseOptions.push({
          planCode: plan.code,
          planName: plan.name,
          months: duration.months,
          priceInPaise: duration.priceInPaise,
          currency: duration.currency,
          kind: window.kind,
          startsAt: window.startDate.toISOString(),
          endsAt: window.endDate.toISOString(),
        });
      }
    }

    return {
      plan: membership.plan
        ? {
            code: membership.plan.code,
            name: membership.plan.name,
            tier: membership.plan.tier,
          }
        : null,
      source: membership.source,
      planVersion: membership.planVersion?.version ?? null,
      subscription: subscription
        ? {
            id: subscription.id,
            planCode: subscription.planCode,
            status: subscription.status,
            startDate: subscription.startDate.toISOString(),
            endDate: subscription.endDate.toISOString(),
            months: subscription.months,
            autoRenew: subscription.autoRenew,
            cancelledAt: subscription.cancelledAt?.toISOString() ?? null,
            source: subscription.source,
          }
        : null,
      scheduled: scheduled.map((row) => ({
        id: row.id,
        planCode: row.plan.name,
        planName: row.plan.displayName,
        startDate: row.startDate.toISOString(),
        endDate: row.endDate.toISOString(),
      })),
      entitlements: membership.entitlements,
      usage: usage.map((entry) => ({
        ...entry,
        resetsAt: entry.resetsAt?.toISOString() ?? null,
      })),
      purchaseOptions,
      effectiveCaps,
      checkoutAvailable: this.razorpay.isCheckoutConfigured(),
      limitsEnforced: this.membership.mode === 'enforce',
    };
  }

  async history(userId: string): Promise<SubscriptionHistoryItemDto[]> {
    const rows = await this.repository.listHistory(userId, HISTORY_LIMIT);
    return rows.map((row) => ({
      id: row.id,
      plan: { code: row.plan.name, name: row.plan.displayName },
      months: row.duration?.months ?? null,
      status: row.status,
      source: row.source,
      startDate: row.startDate.toISOString(),
      endDate: row.endDate.toISOString(),
      priceInPaise: row.priceInPaise,
      currency: row.currency,
      activatedAt: row.activatedAt?.toISOString() ?? null,
      cancelledAt: row.cancelledAt?.toISOString() ?? null,
      cancellationReason: row.cancellationReason,
      createdAt: row.createdAt.toISOString(),
      payments: row.payments.map((payment) => ({
        id: payment.id,
        orderId: payment.razorpayOrderId,
        paymentId: payment.razorpayPaymentId,
        amountInPaise: payment.amountInr,
        currency: payment.currency,
        status: payment.status,
        paidAt: payment.paidAt?.toISOString() ?? null,
        refundedAmount: payment.refundedAmount,
        refundedAt: payment.refundedAt?.toISOString() ?? null,
      })),
    }));
  }
}

function describeFeature(
  key: (typeof FEATURE_KEYS)[number],
): FeatureDescriptorDto {
  const def: FeatureDefinition = FEATURES[key];
  return {
    key,
    kind: def.kind,
    section: def.section,
    label: def.label,
    ...(def.kind === 'quota' && { period: def.period }),
    ...(def.kind === 'level' && { levels: def.levels }),
    ...(def.requiredOnEveryPlan && { requiredOnEveryPlan: true }),
  };
}
