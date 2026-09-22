import { Injectable } from '@nestjs/common';
import { PrismaService, activePremiumSubscriptionWhere } from '@app/database';

/**
 * Persistence for entitlement checks. DB access only — what counts as
 * "active premium" is defined once in `activePremiumSubscriptionWhere`.
 */
@Injectable()
export class EntitlementRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Whether [userId] has at least one subscription that grants premium at
   *  [now]. A `findFirst` on an indexed `user_id`, selecting only the id. */
  async hasActivePremiumSubscription(
    userId: string,
    now: Date,
  ): Promise<boolean> {
    const row = await this.prisma.userSubscription.findFirst({
      where: { userId, ...activePremiumSubscriptionWhere(now) },
      select: { id: true },
    });
    return row !== null;
  }
}
