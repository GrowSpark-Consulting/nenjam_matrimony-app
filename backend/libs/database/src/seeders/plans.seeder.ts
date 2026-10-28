import { PrismaClient } from '../../generated/client';

/**
 * Reports the membership plan catalogue. Deliberately writes NOTHING.
 *
 * The catalogue (Free / Gold / Platinum, their entitlement versions and
 * durations) is created by the migration 20261027120100_membership_catalog —
 * so it exists wherever `prisma migrate deploy` has run — and is changed only
 * through PlanCatalogAdminService, which versions and audits every change.
 * This seeder used to upsert SILVER (₹499/30d) and GOLD (₹999/90d) with its
 * own limits; re-running that would re-activate the retired SILVER plan and
 * overwrite an administrator's pricing on every `pnpm db:seed`.
 */
export async function seedPlans(prisma: PrismaClient): Promise<void> {
  console.log('\n📦  Membership plans (managed by migration — not seeded)…');

  const plans = await prisma.subscriptionPlan.findMany({
    orderBy: [{ displayOrder: 'asc' }, { tier: 'asc' }],
    include: {
      versions: { orderBy: { version: 'desc' }, take: 1 },
      durations: { orderBy: { months: 'asc' } },
    },
  });

  if (!plans.some((plan) => plan.name === 'FREE')) {
    console.warn(
      '  ⚠️  No FREE plan found — run `pnpm prisma:migrate:deploy`. Until then membership checks fail open.',
    );
  }
  for (const plan of plans) {
    const latest = plan.versions[0]?.version ?? 'none';
    const durations =
      plan.durations
        .map(
          (d) =>
            `${d.months}m ${d.priceInPaise === null ? 'unpriced' : `₹${(d.priceInPaise / 100).toFixed(2)}`}${d.isActive ? '' : ' (inactive)'}`,
        )
        .join(', ') || '—';
    console.log(
      `  ${plan.isActive ? '✅' : '⏸️ '}  ${plan.name} — v${latest} — ${durations}`,
    );
  }
}
