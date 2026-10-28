import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  SubscriptionPlanName,
  SubscriptionSource,
} from '../../../../../../libs/database/generated/client';

/** A subscription row in force, with what resolution needs to rank it. */
export interface SubscriptionInForce {
  id: string;
  planId: string;
  planCode: SubscriptionPlanName;
  planTier: number;
  planVersionId: string | null;
  startDate: Date;
  endDate: Date;
  months: number | null;
  autoRenew: boolean;
  cancelledAt: Date | null;
  source: SubscriptionSource;
}

/**
 * Persistence for membership resolution. DB access only — which row wins is
 * MembershipService's decision.
 */
@Injectable()
export class MembershipRepository {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * [userId]'s subscriptions granting access at [now]: ACTIVE, started, not
   * yet ended. The same rule as `activePremiumSubscriptionWhere`, minus the
   * paid-plan filter (resolution ranks plans itself). Served by the
   * (user_id, status, end_date) index. Reads through [db] when given — the
   * caller's transaction — so a check inside a transaction never needs a
   * second pooled connection.
   */
  async findInForce(
    userId: string,
    now: Date,
    db: Prisma.TransactionClient = this.prisma,
  ): Promise<SubscriptionInForce[]> {
    const rows = await db.userSubscription.findMany({
      where: {
        userId,
        status: 'ACTIVE',
        startDate: { lte: now },
        endDate: { gt: now },
      },
      select: {
        id: true,
        planId: true,
        planVersionId: true,
        startDate: true,
        endDate: true,
        autoRenew: true,
        cancelledAt: true,
        source: true,
        plan: { select: { name: true, tier: true } },
        duration: { select: { months: true } },
      },
    });
    return rows.map((row) => ({
      id: row.id,
      planId: row.planId,
      planCode: row.plan.name,
      planTier: row.plan.tier,
      planVersionId: row.planVersionId,
      startDate: row.startDate,
      endDate: row.endDate,
      months: row.duration?.months ?? null,
      autoRenew: row.autoRenew,
      cancelledAt: row.cancelledAt,
      source: row.source,
    }));
  }
}
