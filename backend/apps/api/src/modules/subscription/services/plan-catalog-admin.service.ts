import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  SubscriptionPlanName,
} from '../../../../../../libs/database/generated/client';
import {
  parseEntitlements,
  reductionsBetween,
  validateEntitlementsForPublish,
  type EntitlementMap,
  type FeatureKey,
} from '../../entitlements/catalog/feature-catalog';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { SubscriptionRepository } from '../repositories/subscription.repository';
import { assertAdminPermission } from '../../admin/rbac/assert-admin-permission';

/** Allowance for clock skew when refusing a backdated version. */
const BACKDATE_TOLERANCE_MS = 60_000;

export interface PublishVersionInput {
  planCode: SubscriptionPlanName;
  /** The COMPLETE entitlement map — every known feature, nothing unknown. */
  entitlements: unknown;
  /** When new purchases (and Free members) start getting it. Defaults to
   *  now; never in the past. */
  effectiveFrom?: Date;
  changeNote: string;
  actorId: string;
  /**
   * Also move members who already hold this plan onto the new version.
   * Allowed only for subscribers it can't take anything from: each one is
   * moved only if the new version reduces nothing relative to the version
   * they bought; anyone it would reduce keeps theirs.
   */
  applyToExistingSubscribers?: boolean;
}

export interface PublishVersionResult {
  versionId: string;
  version: number;
  /** What the new version grants less of than the one it supersedes —
   *  reductions apply to new purchases (and Free members) only. */
  reductionsVsCurrent: FeatureKey[];
  appliedToExisting: number;
  skippedExisting: number;
}

export interface SetDurationInput {
  planCode: SubscriptionPlanName;
  months: number;
  priceInPaise?: number | null;
  durationDays?: number;
  bonusDays?: number;
  isActive?: boolean;
  displayOrder?: number;
  actorId: string;
  reason: string;
}

/**
 * Write side of the plan catalogue, for the future admin panel. There is no
 * HTTP surface for any of this yet, deliberately: an unauthenticated or
 * role-less config endpoint would let anyone reprice the app. When the admin
 * API is built it should be a thin, permission-checked controller over these
 * methods (see docs/membership/README.md § Future admin API).
 *
 * Every method requires a reason, checks — inside its transaction — that the
 * actor is an ACTIVE admin whose roles grant the permission (plan.publish for
 * anything members see change — versions, prices, availability; plan.edit for
 * display text; see admin/rbac/assert-admin-permission.ts), validates, and
 * writes its change and an AuditLog row (with the before/after state) in that
 * ONE transaction, then refreshes the catalogue cache.
 *
 * Change policy, enforced here:
 *  - Entitlements are never edited in place — a change is a new version.
 *    Members who bought an earlier version keep it for the rest of their term
 *    (no silent reduction of a purchased benefit); `applyToExistingSubscribers`
 *    can move them forward only where that loses them nothing.
 *  - Prices are a current price list; history is the price snapshotted on
 *    each subscription and payment, which is never rewritten.
 *  - FREE can never be deactivated, never priced, and must keep every
 *    `requiredOnEveryPlan` feature (verified-only browsing among them).
 *  - Deactivating a paid plan only stops new sales; existing subscriptions
 *    run to their end date untouched.
 */
@Injectable()
export class PlanCatalogAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
    private readonly subscriptions: SubscriptionRepository,
  ) {}

  async publishVersion(
    input: PublishVersionInput,
    now: Date = new Date(),
  ): Promise<PublishVersionResult> {
    this.assertText(input.changeNote, 'changeNote');
    const problems = validateEntitlementsForPublish(input.entitlements);
    if (problems.length > 0) {
      throw new BadRequestException({
        message: 'The entitlements are not valid.',
        problems,
      });
    }
    const next = parseEntitlements(input.entitlements).map;
    const effectiveFrom = input.effectiveFrom ?? now;
    if (effectiveFrom.getTime() < now.getTime() - BACKDATE_TOLERANCE_MS) {
      throw new BadRequestException('effectiveFrom cannot be in the past.');
    }
    if (input.applyToExistingSubscribers && effectiveFrom > now) {
      throw new BadRequestException(
        'A future-dated version cannot be applied to existing subscribers.',
      );
    }

    const plan = await this.requirePlan(input.planCode);
    const current = this.catalog.versionEffectiveAt(plan, now);
    const reductionsVsCurrent = current
      ? reductionsBetween(current.entitlements, next)
      : [];

    try {
      const result = await this.prisma.$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.publish');
        const latest = await tx.subscriptionPlanVersion.aggregate({
          where: { planId: plan.id },
          _max: { version: true },
        });
        const version = (latest._max.version ?? 0) + 1;
        const created = await tx.subscriptionPlanVersion.create({
          data: {
            planId: plan.id,
            version,
            entitlements: next as unknown as Prisma.InputJsonValue,
            effectiveFrom,
            changeNote: input.changeNote,
            createdById: input.actorId,
          },
        });

        let appliedToExisting = 0;
        let skippedExisting = 0;
        if (input.applyToExistingSubscribers && plan.code !== 'FREE') {
          ({ appliedToExisting, skippedExisting } =
            await this.applyToSubscribers(
              tx,
              plan.id,
              created.id,
              next,
              input.actorId,
              now,
            ));
        }

        await this.audit(
          tx,
          input.actorId,
          'membership.plan.version.publish',
          'SubscriptionPlan',
          plan.id,
          {
            plan: plan.code,
            version,
            effectiveFrom: effectiveFrom.toISOString(),
            changeNote: input.changeNote,
            previousVersion: current?.version ?? null,
            reductionsVsCurrent,
            appliedToExisting,
            skippedExisting,
          },
        );
        return {
          versionId: created.id,
          version,
          appliedToExisting,
          skippedExisting,
        };
      });
      return { ...result, reductionsVsCurrent };
    } catch (error) {
      // Two admins publishing at once collide on (plan_id, version).
      if ((error as { code?: string })?.code === 'P2002') {
        throw new ConflictException(
          'Another version of this plan was published at the same time. Reload and try again.',
        );
      }
      throw error;
    } finally {
      await this.refreshCatalog();
    }
  }

  async setDuration(input: SetDurationInput): Promise<void> {
    this.assertText(input.reason, 'reason');
    if (input.planCode === 'FREE') {
      throw new BadRequestException('The Free plan has no price or durations.');
    }
    if (
      !Number.isInteger(input.months) ||
      input.months < 1 ||
      input.months > 36
    ) {
      throw new BadRequestException(
        'months must be a whole number from 1 to 36.',
      );
    }
    this.assertOptionalInt(input.durationDays, 'durationDays', 1);
    this.assertOptionalInt(input.bonusDays, 'bonusDays', 0);
    this.assertOptionalInt(input.displayOrder, 'displayOrder', 0);
    if (input.priceInPaise !== undefined && input.priceInPaise !== null) {
      this.assertOptionalInt(input.priceInPaise, 'priceInPaise', 1);
    }

    const plan = await this.requirePlan(input.planCode);
    try {
      await this.prisma.$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.publish');
        const before = await tx.subscriptionPlanDuration.findUnique({
          where: { planId_months: { planId: plan.id, months: input.months } },
        });
        const price =
          input.priceInPaise !== undefined
            ? input.priceInPaise
            : (before?.priceInPaise ?? null);
        const active = input.isActive ?? before?.isActive ?? false;
        if (active && price === null) {
          throw new BadRequestException(
            'A duration must be priced before it can be sold.',
          );
        }
        const durationDays = input.durationDays ?? before?.durationDays;
        if (durationDays === undefined) {
          throw new BadRequestException(
            'durationDays is required for a new duration.',
          );
        }
        const data = {
          durationDays,
          bonusDays: input.bonusDays ?? before?.bonusDays ?? 0,
          priceInPaise: price,
          isActive: active,
          displayOrder:
            input.displayOrder ?? before?.displayOrder ?? input.months,
        };
        const after = await tx.subscriptionPlanDuration.upsert({
          where: { planId_months: { planId: plan.id, months: input.months } },
          create: { planId: plan.id, months: input.months, ...data },
          update: data,
        });
        await this.audit(
          tx,
          input.actorId,
          'membership.plan.duration.set',
          'SubscriptionPlanDuration',
          after.id,
          {
            plan: plan.code,
            months: input.months,
            reason: input.reason,
            before: before ? durationSnapshot(before) : null,
            after: durationSnapshot(after),
          },
        );
      });
    } finally {
      await this.refreshCatalog();
    }
  }

  async setPlanActive(input: {
    planCode: SubscriptionPlanName;
    isActive: boolean;
    actorId: string;
    reason: string;
  }): Promise<void> {
    this.assertText(input.reason, 'reason');
    if (input.planCode === 'FREE' && !input.isActive) {
      throw new BadRequestException('The Free plan can never be deactivated.');
    }
    const plan = await this.requirePlan(input.planCode);
    try {
      await this.prisma.$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.publish');
        await tx.subscriptionPlan.update({
          where: { id: plan.id },
          data: { isActive: input.isActive },
        });
        await this.audit(
          tx,
          input.actorId,
          'membership.plan.status.set',
          'SubscriptionPlan',
          plan.id,
          {
            plan: plan.code,
            before: plan.isActive,
            after: input.isActive,
            reason: input.reason,
          },
        );
      });
    } finally {
      await this.refreshCatalog();
    }
  }

  async updatePlanDisplay(input: {
    planCode: SubscriptionPlanName;
    displayName?: string;
    description?: string | null;
    displayOrder?: number;
    actorId: string;
    reason: string;
  }): Promise<void> {
    this.assertText(input.reason, 'reason');
    if (input.displayName !== undefined)
      this.assertText(input.displayName, 'displayName');
    this.assertOptionalInt(input.displayOrder, 'displayOrder', 0);
    const plan = await this.requirePlan(input.planCode);
    const data = {
      ...(input.displayName !== undefined && {
        displayName: input.displayName.trim(),
      }),
      ...(input.description !== undefined && {
        description: input.description,
      }),
      ...(input.displayOrder !== undefined && {
        displayOrder: input.displayOrder,
      }),
    };
    try {
      await this.prisma.$transaction(async (tx) => {
        await assertAdminPermission(tx, input.actorId, 'plan.edit');
        await tx.subscriptionPlan.update({ where: { id: plan.id }, data });
        await this.audit(
          tx,
          input.actorId,
          'membership.plan.display.set',
          'SubscriptionPlan',
          plan.id,
          {
            plan: plan.code,
            reason: input.reason,
            before: {
              displayName: plan.name,
              description: plan.description,
              displayOrder: plan.displayOrder,
            },
            after: data,
          },
        );
      });
    } finally {
      await this.refreshCatalog();
    }
  }

  /** Re-pin the plan's live subscriptions to [versionId] where the new
   *  version reduces nothing relative to what each one bought. */
  private async applyToSubscribers(
    tx: Prisma.TransactionClient,
    planId: string,
    versionId: string,
    next: EntitlementMap,
    actorId: string,
    now: Date,
  ): Promise<{ appliedToExisting: number; skippedExisting: number }> {
    const plan = (await this.catalog.getCatalog(now)).plans.find(
      (p) => p.id === planId,
    );
    const live = await tx.userSubscription.findMany({
      where: { planId, status: 'ACTIVE', endDate: { gt: now } },
      select: { id: true, userId: true, planVersionId: true, startDate: true },
    });
    let appliedToExisting = 0;
    let skippedExisting = 0;
    for (const subscription of live) {
      const pinned = subscription.planVersionId
        ? plan?.versions.find((v) => v.id === subscription.planVersionId)
        : plan && this.catalog.versionEffectiveAt(plan, subscription.startDate);
      if (!pinned || reductionsBetween(pinned.entitlements, next).length > 0) {
        skippedExisting += 1;
        continue;
      }
      await tx.userSubscription.update({
        where: { id: subscription.id },
        data: { planVersionId: versionId },
      });
      await this.subscriptions.recordEvent(tx, {
        subscriptionId: subscription.id,
        userId: subscription.userId,
        type: 'ENTITLEMENTS_UPGRADED',
        actorId,
        metadata: { fromVersionId: pinned.id, toVersionId: versionId },
      });
      appliedToExisting += 1;
    }
    return { appliedToExisting, skippedExisting };
  }

  /** The plan as stored right now — admin changes must not act on a cached
   *  copy up to a minute old. Loaded before any transaction opens. */
  private async requirePlan(code: SubscriptionPlanName) {
    const { plans } = await this.catalog.refresh();
    const plan = plans.find((p) => p.code === code);
    if (!plan) throw new NotFoundException(`No plan ${code}.`);
    return plan;
  }

  /** After a committed change: make this process serve it immediately (other
   *  replicas pick it up within the catalogue TTL). A failed reload doesn't
   *  undo the committed change, so it is logged by the catalogue, not thrown. */
  private async refreshCatalog(): Promise<void> {
    await this.catalog.refresh().catch(() => undefined);
  }

  private assertText(value: string, field: string): void {
    if (typeof value !== 'string' || value.trim().length < 3) {
      throw new BadRequestException(`${field} is required.`);
    }
  }

  private assertOptionalInt(
    value: number | undefined,
    field: string,
    min: number,
  ): void {
    if (value !== undefined && (!Number.isInteger(value) || value < min)) {
      throw new BadRequestException(
        `${field} must be a whole number >= ${min}.`,
      );
    }
  }

  private async audit(
    tx: Prisma.TransactionClient,
    actorId: string,
    action: string,
    entity: string,
    entityId: string,
    metadata: Record<string, unknown>,
  ): Promise<void> {
    await tx.auditLog.create({
      data: {
        actorId,
        action,
        entity,
        entityId,
        metadata: metadata as Prisma.InputJsonValue,
      },
    });
  }
}

function durationSnapshot(duration: {
  months: number;
  durationDays: number;
  bonusDays: number;
  priceInPaise: number | null;
  currency: string;
  isActive: boolean;
}) {
  return {
    months: duration.months,
    durationDays: duration.durationDays,
    bonusDays: duration.bonusDays,
    priceInPaise: duration.priceInPaise,
    currency: duration.currency,
    isActive: duration.isActive,
  };
}
