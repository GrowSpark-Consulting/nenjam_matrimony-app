import type { PrismaClient } from '../../generated/client';

/**
 * Flips ACTIVE subscriptions whose end date has passed to EXPIRED, each with
 * its EXPIRED lifecycle event.
 *
 * Bookkeeping only: access already stopped at `endDate`, because every
 * membership query requires `endDate > now` regardless of status. So a missed
 * or late sweep never grants anyone anything — it only delays the status (and
 * the history row) catching up.
 *
 * Shared by the API (SubscriptionLifecycleService) and the separately
 * deployed scheduler (SubscriptionExpiryCron), so the rule can't diverge.
 * One small transaction per row, with a status-conditional update, so a row
 * refunded or revoked in the meantime is skipped rather than overwritten.
 * Returns how many rows it expired; call again while it returns `batchSize`.
 */
export async function expireLapsedSubscriptions(
  prisma: PrismaClient,
  now: Date,
  batchSize = 500,
): Promise<number> {
  const due = await prisma.userSubscription.findMany({
    where: { status: 'ACTIVE', endDate: { lte: now } },
    select: { id: true, userId: true },
    orderBy: { endDate: 'asc' },
    take: batchSize,
  });

  let expired = 0;
  for (const row of due) {
    await prisma.$transaction(async (tx) => {
      const { count } = await tx.userSubscription.updateMany({
        where: { id: row.id, status: 'ACTIVE', endDate: { lte: now } },
        data: { status: 'EXPIRED' },
      });
      if (count === 0) return;
      await tx.subscriptionEvent.create({
        data: {
          subscriptionId: row.id,
          userId: row.userId,
          type: 'EXPIRED',
          fromStatus: 'ACTIVE',
          toStatus: 'EXPIRED',
        },
      });
      expired += 1;
    });
  }
  return expired;
}
