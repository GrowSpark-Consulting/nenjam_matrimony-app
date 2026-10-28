import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { AppConfigService, type MembershipEnforcementMode } from '@app/config';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  SubscriptionPlanName,
} from '../../../../../../libs/database/generated/client';
import {
  definitionOf,
  effectiveLimit,
  FEATURE_KEYS,
  FEATURES,
  LEGACY_CAP_LIMITS,
  type BooleanFeatureKey,
  type CapFeatureKey,
  type EffectiveLimit,
  type EntitlementValue,
  type FeatureKey,
  type LevelFeatureKey,
  type LimitValue,
  type QuotaFeatureKey,
  type QuotaPeriod,
} from '../catalog/feature-catalog';
import { PlanCatalogService } from '../catalog/plan-catalog.service';
import {
  capReached,
  featureUnavailable,
  quotaReached,
  type DenialContext,
} from '../domain/membership-denial';
import type {
  CatalogPlan,
  CatalogVersion,
  ResolvedMembership,
} from '../domain/membership.types';
import { usagePeriodFor } from '../domain/usage-period';
import {
  MembershipRepository,
  type SubscriptionInForce,
} from '../repositories/membership.repository';
import { UsageRepository } from '../repositories/usage.repository';

export interface ConsumeOptions {
  userId: string;
  /** The caller's transaction, so the charge commits or rolls back with the
   *  action it pays for. Without one the charge runs in its own. */
  tx?: Prisma.TransactionClient;
  amount?: number;
  /** For per-item features: the item (e.g. the profile id) being charged. */
  itemKey?: string;
  /** Reuse a resolution already made in this request. */
  membership?: ResolvedMembership;
  now?: Date;
}

export interface CapOptions {
  userId: string;
  /** How many the member holds now, read through the client it is given. */
  count: (db: Prisma.TransactionClient) => Promise<number>;
  /** The caller's transaction. In `enforce` mode the check takes a lock and
   *  counts inside it, so concurrent requests can't both pass the cap. */
  tx?: Prisma.TransactionClient;
  membership?: ResolvedMembership;
  /** The hard cap that applied before membership existed. Kept in `off` and
   *  `shadow` mode so those modes behave exactly as before. */
  legacyLimit?: { limit: number; message: string };
  now?: Date;
}

export interface QuotaUsage {
  feature: QuotaFeatureKey;
  period: QuotaPeriod;
  used: number;
  /** null = unlimited. */
  limit: number | null;
  remaining: number | null;
  fairUse: boolean;
  resetsAt: Date | null;
}

export interface MembershipSummary {
  membership: ResolvedMembership;
  usage: QuotaUsage[];
  /** For every cap feature, the cap actually applied right now (null =
   *  none) — see [MembershipService.effectiveCap]. */
  effectiveCaps: Record<CapFeatureKey, number | null>;
}

/** Where shadow mode records a feature's usage: a separate counter that
 *  enforcement never reads (see shadowConsume). */
export function shadowFeatureKey(feature: QuotaFeatureKey): string {
  return `shadow:${feature}`;
}

function unavailable(userId: string, now: Date): ResolvedMembership {
  return {
    userId,
    source: 'UNAVAILABLE',
    plan: null,
    planVersion: null,
    subscription: null,
    entitlements: null,
    resolvedAt: now,
  };
}

/**
 * The central entitlement engine: the one place the backend decides whether a
 * member may do something their plan governs. Controllers and services ask it
 * — never the plan name, never the client.
 *
 * Resolution: a member's plan is the highest-tier subscription in force
 * (ACTIVE, started, not ended); with none they are Free. A subscription's
 * entitlements are those of the plan version it was sold under, so later
 * catalogue changes don't silently alter what someone paid for.
 *
 * Everything that can deny goes through [mode] (MEMBERSHIP_ENFORCEMENT_MODE):
 *  - `off`     — no membership work at all; pre-membership behaviour.
 *  - `shadow`  — usage is recorded and would-be denials are LOGGED, off the
 *                request path, and nothing is denied.
 *  - `enforce` — denials are 403s with a structured body.
 *
 * It fails OPEN: if the catalogue can't be read the member is treated exactly
 * as before membership existed, never locked out.
 */
@Injectable()
export class MembershipService {
  private readonly logger = new Logger(MembershipService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: PlanCatalogService,
    private readonly membershipRepository: MembershipRepository,
    private readonly usageRepository: UsageRepository,
    private readonly config: AppConfigService,
  ) {}

  get mode(): MembershipEnforcementMode {
    return this.config.membership?.enforcementMode ?? 'shadow';
  }

  // ── Resolution ──────────────────────────────────────────────────────────

  /**
   * [userId]'s membership at [now]. Pass the caller's transaction as [db]
   * when resolving inside one: then this needs no connection beyond the one
   * the transaction already holds (the catalogue is served from memory).
   */
  async resolve(
    userId: string,
    now: Date = new Date(),
    db?: Prisma.TransactionClient,
  ): Promise<ResolvedMembership> {
    try {
      // Sequential on purpose when [db] is a transaction: one connection
      // can't run two queries at once.
      const catalog = await this.catalog.getCatalog(now, db);
      const inForce = await this.membershipRepository.findInForce(
        userId,
        now,
        db,
      );

      // Highest plan wins; among equals, the one running longest. An upgrade
      // overlaps the plan it upgrades, and the lower plan simply resumes if
      // it outlives the higher one — nothing already bought is lost.
      const ranked = [...inForce].sort(
        (a, b) =>
          b.planTier - a.planTier || b.endDate.getTime() - a.endDate.getTime(),
      );

      // A subscription with no pinned version predates this catalogue (e.g.
      // an old SILVER/GOLD row). What it was sold as is not recorded, and the
      // old GOLD was marketed with unlimited interests and contacts — so it is
      // NEVER reinterpreted under today's terms, which could quietly take
      // something away. While it is in force the member has no limits at all.
      const legacy = ranked.find((s) => s.planVersionId === null);
      if (legacy) {
        this.logger.warn(
          `Subscription ${legacy.id} (${legacy.planCode}) predates plan versions — no limits applied while it is in force.`,
        );
        return {
          userId,
          source: 'LEGACY',
          plan: {
            id: legacy.planId,
            code: legacy.planCode,
            name:
              catalog.plans.find((p) => p.id === legacy.planId)?.name ??
              legacy.planCode,
            tier: legacy.planTier,
          },
          planVersion: null,
          subscription: this.subscriptionView(legacy),
          entitlements: null,
          resolvedAt: now,
        };
      }

      let uninterpretablePaidRow = false;
      for (const subscription of ranked) {
        const plan = catalog.plans.find((p) => p.id === subscription.planId);
        const version = plan ? this.versionOf(plan, subscription) : null;
        if (!plan || !version) {
          uninterpretablePaidRow = true;
          this.logger.warn(
            `Subscription ${subscription.id} (${subscription.planCode}) has no entitlement version to resolve.`,
          );
          continue;
        }
        return this.fromSubscription(userId, now, plan, version, subscription);
      }
      // Someone holds a subscription we can't interpret. Falling back to Free
      // would take away what they paid for; fail open instead.
      if (uninterpretablePaidRow) return unavailable(userId, now);

      const free = catalog.plans.find((plan) => plan.code === 'FREE');
      const freeVersion = free
        ? this.catalog.versionEffectiveAt(free, now)
        : null;
      if (!free || !freeVersion) {
        this.logger.error(
          'The FREE plan or its current version is missing — membership checks are failing open.',
        );
        return unavailable(userId, now);
      }
      return {
        userId,
        source: 'FREE',
        plan: {
          id: free.id,
          code: free.code,
          name: free.name,
          tier: free.tier,
        },
        planVersion: { id: freeVersion.id, version: freeVersion.version },
        subscription: null,
        entitlements: freeVersion.entitlements,
        resolvedAt: now,
      };
    } catch (error) {
      this.logger.error(
        `Membership resolution failed for user ${userId}; failing open: ${(error as Error).message}`,
      );
      return unavailable(userId, now);
    }
  }

  /** The version a subscription is pinned to (legacy, unpinned rows are
   *  handled before this is reached). */
  private versionOf(
    plan: CatalogPlan,
    subscription: SubscriptionInForce,
  ): CatalogVersion | null {
    return (
      plan.versions.find((v) => v.id === subscription.planVersionId) ?? null
    );
  }

  private subscriptionView(
    subscription: SubscriptionInForce,
  ): NonNullable<ResolvedMembership['subscription']> {
    return {
      id: subscription.id,
      planCode: subscription.planCode,
      status: 'ACTIVE',
      startDate: subscription.startDate,
      endDate: subscription.endDate,
      months: subscription.months,
      autoRenew: subscription.autoRenew,
      cancelledAt: subscription.cancelledAt,
      source: subscription.source,
    };
  }

  private fromSubscription(
    userId: string,
    now: Date,
    plan: CatalogPlan,
    version: CatalogVersion,
    subscription: SubscriptionInForce,
  ): ResolvedMembership {
    return {
      userId,
      source: 'SUBSCRIPTION',
      plan: { id: plan.id, code: plan.code, name: plan.name, tier: plan.tier },
      planVersion: { id: version.id, version: version.version },
      subscription: this.subscriptionView(subscription),
      entitlements: version.entitlements,
      resolvedAt: now,
    };
  }

  // ── Pure reads (no mode applied) ────────────────────────────────────────

  /** Whether the plan grants a boolean feature. True when the catalogue is
   *  unavailable (fail open). */
  isEnabled(
    membership: ResolvedMembership,
    feature: BooleanFeatureKey,
  ): boolean {
    return membership.entitlements
      ? membership.entitlements[feature] === true
      : true;
  }

  /** A level feature's value; null when the catalogue is unavailable. */
  levelOf(
    membership: ResolvedMembership,
    feature: LevelFeatureKey,
  ): string | null {
    return membership.entitlements ? membership.entitlements[feature] : null;
  }

  /** A cap/quota's limit for this member right now; unlimited when the
   *  catalogue is unavailable. */
  limitOf(
    membership: ResolvedMembership,
    feature: CapFeatureKey | QuotaFeatureKey,
  ): EffectiveLimit {
    if (!membership.entitlements) return { limit: null, fairUse: false };
    return effectiveLimit(membership.entitlements[feature], {
      subscriptionMonths: membership.subscription?.months,
    });
  }

  /**
   * The cap the backend actually applies right now — what [enforceCap] will
   * hold the member to: the plan's limit under `enforce`, otherwise the
   * pre-membership cap if there was one (null = none). Mode-aware, unlike
   * [limitOf], which always reports the plan's own number.
   */
  effectiveCap(
    membership: ResolvedMembership,
    feature: CapFeatureKey,
  ): number | null {
    if (this.mode === 'enforce' && membership.entitlements) {
      return this.limitOf(membership, feature).limit;
    }
    return LEGACY_CAP_LIMITS[feature] ?? null;
  }

  // ── Checks (mode applied) ───────────────────────────────────────────────

  /** Gate a boolean feature: allowed if granted; otherwise logged (shadow) or
   *  denied with a 403 (enforce). */
  async requireFeature(
    membership: ResolvedMembership,
    feature: BooleanFeatureKey,
  ): Promise<void> {
    if (this.mode === 'off' || this.isEnabled(membership, feature)) return;
    if (this.mode === 'shadow') {
      this.logShadow(membership, feature, 'feature not included');
      return;
    }
    throw featureUnavailable(await this.denialContext(membership, feature));
  }

  /**
   * Charge [amount] of a metered feature. In `enforce` mode this is atomic
   * with the caller's transaction and refuses (403) a charge that would pass
   * the limit — concurrent requests cannot overshoot it. In `shadow` mode it
   * records the use off the request path and never throws.
   */
  async consume(
    feature: QuotaFeatureKey,
    options: ConsumeOptions,
  ): Promise<void> {
    if (this.mode === 'off') return;
    if (this.mode === 'shadow') {
      void this.shadowConsume(feature, options).catch((error: unknown) =>
        this.logger.warn(
          `[membership:shadow] usage not recorded for ${feature}: ${(error as Error).message}`,
        ),
      );
      return;
    }

    const now = options.now ?? new Date();
    const membership =
      options.membership ??
      (await this.resolve(options.userId, now, options.tx));
    if (!membership.entitlements) return; // fail open — nothing to meter against

    const charge = async (tx: Prisma.TransactionClient): Promise<void> => {
      const quota = this.quotaContext(membership, feature, now);
      const outcome = await this.usageRepository.consume(tx, {
        userId: options.userId,
        feature,
        periodKey: quota.periodKey,
        periodEndsAt: quota.resetsAt,
        amount: options.amount ?? 1,
        ceiling: quota.limit.limit,
        itemKey: options.itemKey,
      });
      if (outcome.allowed) return;
      const used = await this.usageRepository.usedIn(
        tx,
        options.userId,
        feature,
        quota.periodKey,
      );
      throw quotaReached({
        ...(await this.denialContext(membership, feature)),
        period: quota.period,
        limit: quota.limit.limit ?? 0,
        used,
        resetsAt: quota.resetsAt,
        fairUse: quota.limit.fairUse,
      });
    };

    if (options.tx) return charge(options.tx);
    return this.prisma.$transaction(charge);
  }

  /** Shadow metering: its own transaction, never the caller's, so it can't
   *  slow or fail the action. Over-limit uses are still counted (to measure
   *  real demand) and logged. */
  private async shadowConsume(
    feature: QuotaFeatureKey,
    options: ConsumeOptions,
  ): Promise<void> {
    const now = options.now ?? new Date();
    const membership =
      options.membership ?? (await this.resolve(options.userId, now));
    if (!membership.entitlements) return;
    const quota = this.quotaContext(membership, feature, now);
    const command = {
      userId: options.userId,
      // Shadow usage lives in its own namespace and is NEVER read back as an
      // allowance. It is recorded off the request path, before the action
      // commits, so it can include actions that later failed — fine for
      // measuring demand, wrong for charging members. It also means switching
      // to `enforce` starts everyone on a fresh allowance rather than
      // charging them for use that was never limited.
      feature: shadowFeatureKey(feature),
      periodKey: quota.periodKey,
      periodEndsAt: quota.resetsAt,
      amount: options.amount ?? 1,
      itemKey: options.itemKey,
    };
    await this.prisma.$transaction(async (tx) => {
      const outcome = await this.usageRepository.consume(tx, {
        ...command,
        ceiling: quota.limit.limit,
      });
      if (outcome.allowed) return;
      await this.usageRepository.consume(tx, {
        ...command,
        itemKey: undefined,
        ceiling: null,
      });
      this.logShadow(
        membership,
        feature,
        `limit ${quota.limit.limit} ${quota.period.toLowerCase()} reached`,
      );
    });
  }

  /**
   * Check that adding one more stays within a cap ("may hold at most N").
   *
   * - `off`: only [CapOptions.legacyLimit] applies, exactly as before
   *   membership; with no legacy limit nothing is even counted.
   * - `shadow`: the same, plus a would-be plan denial is logged off the
   *   request path.
   * - `enforce`: the plan's limit applies (the legacy one is ignored). Given
   *   a transaction, it first takes a per-member, per-feature lock and counts
   *   inside it, so two concurrent adds can't both see room for one.
   */
  async enforceCap(feature: CapFeatureKey, options: CapOptions): Promise<void> {
    const db = options.tx ?? this.prisma;
    if (this.mode !== 'enforce') {
      let held: number | undefined;
      if (options.legacyLimit) {
        held = await options.count(db);
        if (held >= options.legacyLimit.limit) {
          throw new BadRequestException(options.legacyLimit.message);
        }
      }
      if (this.mode === 'shadow') {
        void this.shadowCap(feature, options, held).catch(() => undefined);
      }
      return;
    }

    const membership =
      options.membership ??
      (await this.resolve(
        options.userId,
        options.now ?? new Date(),
        options.tx,
      ));
    // No plan terms (LEGACY / UNAVAILABLE): fail open to exactly the
    // pre-membership behaviour — which includes the legacy cap, not "no cap".
    if (!membership.entitlements) {
      if (options.legacyLimit) {
        const held = await options.count(db);
        if (held >= options.legacyLimit.limit) {
          throw new BadRequestException(options.legacyLimit.message);
        }
      }
      return;
    }
    const { limit } = this.limitOf(membership, feature);
    if (limit === null) return;
    if (options.tx) {
      await this.usageRepository.lockCap(options.tx, options.userId, feature);
    }
    const held = await options.count(db);
    if (held < limit) return;
    throw capReached({
      ...(await this.denialContext(membership, feature)),
      limit,
      used: held,
    });
  }

  /** Shadow mode's cap check: off the request path, counting through the
   *  root client (the caller's transaction may be gone by then). */
  private async shadowCap(
    feature: CapFeatureKey,
    options: CapOptions,
    alreadyCounted: number | undefined,
  ): Promise<void> {
    const membership =
      options.membership ?? (await this.resolve(options.userId, options.now));
    const { limit } = this.limitOf(membership, feature);
    if (limit === null) return;
    const held = alreadyCounted ?? (await options.count(this.prisma));
    if (held >= limit) {
      this.logShadow(membership, feature, `cap ${limit} reached`);
    }
  }

  // ── Read model for GET /membership/me ───────────────────────────────────

  async summarize(
    userId: string,
    now: Date = new Date(),
  ): Promise<MembershipSummary> {
    const membership = await this.resolve(userId, now);
    if (!membership.entitlements) {
      return {
        membership,
        usage: [],
        effectiveCaps: this.effectiveCapsOf(membership),
      };
    }

    const quotaFeatures = FEATURE_KEYS.filter(
      (key): key is QuotaFeatureKey => FEATURES[key].kind === 'quota',
    );
    const contexts = quotaFeatures.map((feature) => ({
      feature,
      ...this.quotaContext(membership, feature, now),
    }));
    const readings = await this.usageRepository.read(
      userId,
      contexts.map(({ feature, periodKey }) => ({ feature, periodKey })),
    );
    const usedBy = new Map(
      readings.map((r) => [`${r.feature}|${r.periodKey}`, r.used]),
    );

    return {
      membership,
      usage: contexts.map((context) => {
        const used = usedBy.get(`${context.feature}|${context.periodKey}`) ?? 0;
        const { limit, fairUse } = context.limit;
        return {
          feature: context.feature,
          period: context.period,
          used,
          limit,
          remaining: limit === null ? null : Math.max(0, limit - used),
          fairUse,
          resetsAt: context.resetsAt,
        };
      }),
      effectiveCaps: this.effectiveCapsOf(membership),
    };
  }

  private effectiveCapsOf(
    membership: ResolvedMembership,
  ): Record<CapFeatureKey, number | null> {
    const caps = {} as Record<CapFeatureKey, number | null>;
    for (const key of FEATURE_KEYS) {
      if (FEATURES[key].kind === 'cap') {
        caps[key as CapFeatureKey] = this.effectiveCap(
          membership,
          key as CapFeatureKey,
        );
      }
    }
    return caps;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  private quotaContext(
    membership: ResolvedMembership,
    feature: QuotaFeatureKey,
    now: Date,
  ) {
    const def = definitionOf(feature);
    const period: QuotaPeriod = def.kind === 'quota' ? def.period : 'MONTH';
    const usagePeriod = usagePeriodFor(
      period,
      now,
      membership.subscription
        ? {
            id: membership.subscription.id,
            endDate: membership.subscription.endDate,
          }
        : null,
    );
    return {
      period,
      periodKey: usagePeriod.key,
      resetsAt: usagePeriod.endsAt,
      limit: this.limitOf(membership, feature),
    };
  }

  private async denialContext(
    membership: ResolvedMembership,
    feature: FeatureKey,
  ): Promise<DenialContext> {
    return {
      feature,
      planCode: membership.plan?.code ?? null,
      planName: membership.plan?.name ?? null,
      upgradeTo: await this.upgradeFor(membership, feature),
    };
  }

  /**
   * The cheapest higher plan that is on sale now and grants more of
   * [feature] than the member has. Null when nothing purchasable would help
   * — a denial never points at a plan that can't be bought.
   */
  private async upgradeFor(
    membership: ResolvedMembership,
    feature: FeatureKey,
  ): Promise<{ code: SubscriptionPlanName; name: string } | null> {
    if (!membership.entitlements) return null;
    const current = membership.entitlements[feature];
    const now = membership.resolvedAt;
    const { plans } = await this.catalog.getCatalog(now);
    const candidates = plans
      .filter(
        (plan) =>
          plan.isActive &&
          plan.tier > (membership.plan?.tier ?? 0) &&
          plan.durations.some((d) => d.isActive && d.priceInPaise !== null),
      )
      .sort((a, b) => a.tier - b.tier);
    for (const plan of candidates) {
      const version = this.catalog.versionEffectiveAt(plan, now);
      if (
        version &&
        isMoreGenerous(feature, version.entitlements[feature], current)
      ) {
        return { code: plan.code, name: plan.name };
      }
    }
    return null;
  }

  private logShadow(
    membership: ResolvedMembership,
    feature: FeatureKey,
    detail: string,
  ): void {
    this.logger.log(
      `[membership:shadow] would deny ${feature} for user ${membership.userId} on ${membership.plan?.code ?? 'UNKNOWN'} (${detail})`,
    );
  }
}

function isMoreGenerous(
  feature: FeatureKey,
  candidate: EntitlementValue,
  current: EntitlementValue,
): boolean {
  const def = definitionOf(feature);
  switch (def.kind) {
    case 'boolean':
      return candidate === true && current !== true;
    case 'level':
      return (
        def.levels.indexOf(candidate as string) >
        def.levels.indexOf(current as string)
      );
    case 'cap':
    case 'quota': {
      const next = (candidate as LimitValue).limit;
      const now = (current as LimitValue).limit;
      if (now === null) return false;
      return next === null || next > now;
    }
  }
}
