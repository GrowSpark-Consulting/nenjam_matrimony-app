import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { MembershipEnforcementMode } from '@app/config';
import { PlanCatalogService } from '../catalog/plan-catalog.service';
import type { PlanCatalog } from '../domain/membership.types';
import { MembershipService } from '../services/membership.service';
import type { SubscriptionInForce } from '../repositories/membership.repository';
import type {
  ConsumeCommand,
  ConsumeOutcome,
} from '../repositories/usage.repository';

export type PaidOrFree = 'FREE' | 'GOLD' | 'PLATINUM';

const CATALOG_MIGRATION = join(
  __dirname,
  '../../../../../../libs/database/prisma/migrations/20261027120100_membership_catalog/migration.sql',
);

/**
 * The entitlement JSON each plan ships with, parsed out of the catalogue
 * migration itself — so these tests check the data that actually deploys,
 * not a copy of it that could drift.
 */
export function shippedEntitlements(): Record<
  PaidOrFree,
  Record<string, unknown>
> {
  const sql = readFileSync(CATALOG_MIGRATION, 'utf8');
  const read = (plan: PaidOrFree) => {
    const match = sql.match(
      new RegExp(`\\('${plan}', '(\\{[\\s\\S]*?\\})'\\)`),
    );
    if (!match)
      throw new Error(`No ${plan} entitlements in the catalogue migration`);
    return JSON.parse(match[1]) as Record<string, unknown>;
  };
  return { FREE: read('FREE'), GOLD: read('GOLD'), PLATINUM: read('PLATINUM') };
}

const TIERS: Record<PaidOrFree, number> = { FREE: 0, GOLD: 1, PLATINUM: 2 };
export const V1_EFFECTIVE = new Date('2026-01-01T00:00:00.000Z');

export interface ExtraVersion {
  plan: PaidOrFree;
  id: string;
  version: number;
  effectiveFrom: Date;
  entitlements: Record<string, unknown>;
}

/** subscription_plans rows (with durations + versions) as Prisma returns
 *  them, built from the shipped catalogue. */
export function catalogRows(
  options: { purchasable?: boolean; extraVersions?: ExtraVersion[] } = {},
) {
  const shipped = shippedEntitlements();
  return (['FREE', 'GOLD', 'PLATINUM'] as const).map((code) => ({
    id: `plan-${code}`,
    name: code,
    displayName: code[0] + code.slice(1).toLowerCase(),
    description: null,
    tier: TIERS[code],
    displayOrder: TIERS[code],
    isActive: true,
    durations:
      code === 'FREE'
        ? []
        : [3, 6].map((months) => ({
            id: `dur-${code}-${months}`,
            months,
            durationDays: months * 30,
            bonusDays: 0,
            priceInPaise: options.purchasable ? months * 100_000 : null,
            currency: 'INR',
            isActive: Boolean(options.purchasable),
            displayOrder: months,
          })),
    versions: [
      {
        id: `ver-${code}-1`,
        planId: `plan-${code}`,
        version: 1,
        entitlements: shipped[code],
        effectiveFrom: V1_EFFECTIVE,
      },
      ...(options.extraVersions ?? [])
        .filter((v) => v.plan === code)
        .map((v) => ({
          id: v.id,
          planId: `plan-${code}`,
          version: v.version,
          entitlements: v.entitlements,
          effectiveFrom: v.effectiveFrom,
        })),
    ],
  }));
}

/**
 * The real catalogue service — real caching, parsing and version selection —
 * except that it always reads through its own fake Prisma: unit specs hand
 * the engine bare stand-in transactions with no tables on them. Reading a
 * cold catalogue through a REAL transaction is covered against Postgres by
 * membership-usage.integration.spec.ts.
 */
class FixtureCatalogService extends PlanCatalogService {
  getCatalog(now?: Date): Promise<PlanCatalog> {
    return super.getCatalog(now);
  }
}

/** A REAL PlanCatalogService over a fake Prisma that returns [rows]. */
export function catalogService(rows: unknown[]): PlanCatalogService {
  return new FixtureCatalogService({
    subscriptionPlan: { findMany: jest.fn().mockResolvedValue(rows) },
  } as never);
}

/** Counters in memory, honouring the same ceiling rule as the SQL. */
export class InMemoryUsage {
  readonly counters = new Map<string, number>();
  readonly items = new Set<string>();
  readonly lockCap = jest.fn().mockResolvedValue(undefined);

  consume = jest.fn(
    (_tx: unknown, command: ConsumeCommand): Promise<ConsumeOutcome> => {
      const key = `${command.userId}|${command.feature}|${command.periodKey}`;
      if (command.itemKey !== undefined) {
        const itemKey = `${key}|${command.itemKey}`;
        if (this.items.has(itemKey)) {
          return Promise.resolve({ allowed: true, charged: false });
        }
        this.items.add(itemKey);
      }
      const used = this.counters.get(key) ?? 0;
      if (command.ceiling !== null && used + command.amount > command.ceiling) {
        return Promise.resolve({ allowed: false, charged: false });
      }
      this.counters.set(key, used + command.amount);
      return Promise.resolve({ allowed: true, charged: true });
    },
  );

  usedIn = jest.fn(
    (_tx: unknown, userId: string, feature: string, periodKey: string) =>
      Promise.resolve(
        this.counters.get(`${userId}|${feature}|${periodKey}`) ?? 0,
      ),
  );

  read = jest.fn(
    (userId: string, keys: Array<{ feature: string; periodKey: string }>) =>
      Promise.resolve(
        keys
          .map(({ feature, periodKey }) => ({
            feature,
            periodKey,
            used: this.counters.get(`${userId}|${feature}|${periodKey}`),
          }))
          .filter(
            (r): r is { feature: string; periodKey: string; used: number } =>
              r.used !== undefined,
          ),
      ),
  );
}

/** A subscription in force, for the fake MembershipRepository. */
export function inForce(
  plan: Exclude<PaidOrFree, 'FREE'>,
  over: Partial<SubscriptionInForce> = {},
): SubscriptionInForce {
  return {
    id: `sub-${plan}`,
    planId: `plan-${plan}`,
    planCode: plan,
    planTier: TIERS[plan],
    planVersionId: `ver-${plan}-1`,
    startDate: new Date('2026-10-01T00:00:00.000Z'),
    endDate: new Date('2026-12-31T00:00:00.000Z'),
    months: 3,
    autoRenew: false,
    cancelledAt: null,
    source: 'PURCHASE',
    ...over,
  };
}

/**
 * A REAL MembershipService over the shipped catalogue, in-memory usage and
 * a fixed map of who holds which subscription. Members not in [members] are
 * Free.
 */
export function membershipWithPlans(
  mode: MembershipEnforcementMode,
  members: Record<string, SubscriptionInForce[]> = {},
  options: { purchasable?: boolean; rows?: unknown[] } = {},
) {
  const usage = new InMemoryUsage();
  const catalog = catalogService(
    options.rows ?? catalogRows({ purchasable: options.purchasable ?? true }),
  );
  const membershipRepository = {
    findInForce: jest.fn((userId: string) =>
      Promise.resolve(members[userId] ?? []),
    ),
  };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({ tx: true })),
  };
  const service = new MembershipService(
    prisma as never,
    catalog,
    membershipRepository as never,
    usage as never,
    { membership: { enforcementMode: mode } } as never,
  );
  return { service, usage, catalog, membershipRepository, prisma };
}
