import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  SubscriptionPlanName,
} from '../../../../../../libs/database/generated/client';
import { parseEntitlements } from './feature-catalog';
import type {
  CatalogPlan,
  CatalogVersion,
  PlanCatalog,
} from '../domain/membership.types';

/**
 * How old a loaded catalogue may get before it is refreshed. Plans change
 * rarely and only through PlanCatalogAdminService, which refreshes its own
 * process immediately; other API replicas converge within this window.
 */
const CATALOG_TTL_MS = 60_000;

/**
 * Read side of the plan catalogue: plans, their current price list and every
 * entitlement version, loaded in one query and cached per process.
 *
 * Stale-while-revalidate, and warmed at boot: once loaded, a read NEVER
 * waits on the database — an expired copy is served while a refresh runs in
 * the background. That matters because entitlement checks run inside the
 * caller's transaction; a blocking reload there would need a second pooled
 * connection while holding one, and enough concurrent requests doing that at
 * once starve the pool (found by the concurrency integration spec). Only the
 * very first read in a process can block, and boot warm-up takes that hit.
 *
 * Every stored version is parsed against the feature registry on load. A
 * problem degrades only the affected feature (to its safe default) and is
 * logged — it never fails the load.
 */
@Injectable()
export class PlanCatalogService implements OnApplicationBootstrap {
  private readonly logger = new Logger(PlanCatalogService.name);
  private cached: PlanCatalog | null = null;
  private inflight: Promise<PlanCatalog> | null = null;
  /** Versions already reported, so a reload every minute doesn't repeat it —
   *  a version predating a newly added feature stays "problematic" forever. */
  private readonly reportedVersions = new Set<string>();

  constructor(private readonly prisma: PrismaService) {}

  async onApplicationBootstrap(): Promise<void> {
    await this.refresh().catch((error: unknown) =>
      this.logger.warn(
        `Plan catalogue not loaded at boot (will retry on first use): ${(error as Error).message}`,
      ),
    );
  }

  /**
   * The catalogue, from memory whenever possible. [db] is the caller's
   * transaction, if it is in one: on a cold cache (boot warm-up failed) the
   * load then runs on THAT connection, and isn't shared with other callers,
   * so a burst of transactions can't each hold a connection while waiting on
   * one load that needs another.
   */
  async getCatalog(
    now: Date = new Date(),
    db?: Prisma.TransactionClient,
  ): Promise<PlanCatalog> {
    if (!this.cached) return db ? this.load(now, db) : this.refresh();
    if (now.getTime() - this.cached.loadedAt.getTime() >= CATALOG_TTL_MS) {
      void this.refresh().catch((error: unknown) =>
        this.logger.warn(
          `Plan catalogue refresh failed; serving the previous copy: ${(error as Error).message}`,
        ),
      );
    }
    return this.cached;
  }

  /** Load now (concurrent calls share one query) and wait for it. For
   *  warm-up and administrative reads/writes — never call it inside a
   *  transaction on a request path; use [getCatalog] there. */
  refresh(): Promise<PlanCatalog> {
    this.inflight ??= this.load(new Date()).finally(() => {
      this.inflight = null;
    });
    return this.inflight;
  }

  async findPlan(code: SubscriptionPlanName): Promise<CatalogPlan | null> {
    const catalog = await this.getCatalog();
    return catalog.plans.find((plan) => plan.code === code) ?? null;
  }

  /** The version of [plan] in force at [at]: the latest effectiveFrom not
   *  after it. Null if the plan has no version yet in force. */
  versionEffectiveAt(plan: CatalogPlan, at: Date): CatalogVersion | null {
    return (
      plan.versions.find(
        (version) => version.effectiveFrom.getTime() <= at.getTime(),
      ) ?? null
    );
  }

  async findVersion(versionId: string): Promise<CatalogVersion | null> {
    const catalog = await this.getCatalog();
    for (const plan of catalog.plans) {
      const version = plan.versions.find((v) => v.id === versionId);
      if (version) return version;
    }
    return null;
  }

  private async load(
    now: Date,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<PlanCatalog> {
    const rows = await db.subscriptionPlan.findMany({
      include: { durations: true, versions: true },
      orderBy: [{ displayOrder: 'asc' }, { tier: 'asc' }],
    });

    const plans: CatalogPlan[] = rows.map((row) => {
      const versions: CatalogVersion[] = row.versions
        .map((version) => {
          const { map, problems } = parseEntitlements(version.entitlements);
          if (problems.length > 0 && !this.reportedVersions.has(version.id)) {
            this.reportedVersions.add(version.id);
            this.logger.warn(
              `Plan ${row.name} v${version.version} has ${problems.length} entitlement problem(s), safe defaults applied: ${problems.join('; ')}`,
            );
          }
          return {
            id: version.id,
            planId: version.planId,
            version: version.version,
            effectiveFrom: version.effectiveFrom,
            entitlements: map,
            problems,
          };
        })
        .sort(
          (a, b) =>
            b.effectiveFrom.getTime() - a.effectiveFrom.getTime() ||
            b.version - a.version,
        );

      return {
        id: row.id,
        code: row.name,
        name: row.displayName,
        description: row.description,
        tier: row.tier,
        displayOrder: row.displayOrder,
        isActive: row.isActive,
        durations: row.durations
          .map((duration) => ({
            id: duration.id,
            months: duration.months,
            durationDays: duration.durationDays,
            bonusDays: duration.bonusDays,
            priceInPaise: duration.priceInPaise,
            currency: duration.currency,
            isActive: duration.isActive,
            displayOrder: duration.displayOrder,
          }))
          .sort(
            (a, b) => a.displayOrder - b.displayOrder || a.months - b.months,
          ),
        versions,
      };
    });

    const catalog: PlanCatalog = { plans, loadedAt: now };
    this.cached = catalog;
    return catalog;
  }
}
