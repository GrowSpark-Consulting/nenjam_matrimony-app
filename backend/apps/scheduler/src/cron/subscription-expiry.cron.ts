import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService, expireLapsedSubscriptions } from '@app/database';

/** Rows expired per pass; the loop continues while a pass comes back full. */
const BATCH_SIZE = 500;
/** Upper bound on passes per run, so one run can never spin forever. */
const MAX_PASSES = 20;

/**
 * Marks subscriptions whose end date has passed as EXPIRED, with their
 * lifecycle event. Bookkeeping only: access already stopped at the end date
 * (every membership check requires `endDate > now`), so a late or skipped run
 * never grants anyone anything — it only delays the status catching up. The
 * rule itself is shared with the API (`expireLapsedSubscriptions`).
 */
@Injectable()
export class SubscriptionExpiryCron {
  private readonly logger = new Logger(SubscriptionExpiryCron.name);

  constructor(private readonly prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_HOUR)
  async run(now: Date = new Date()): Promise<number> {
    let total = 0;
    try {
      for (let pass = 0; pass < MAX_PASSES; pass++) {
        const expired = await expireLapsedSubscriptions(
          this.prisma,
          now,
          BATCH_SIZE,
        );
        total += expired;
        if (expired < BATCH_SIZE) break;
      }
      if (total > 0) this.logger.log(`Expired ${total} subscription(s).`);
    } catch (error) {
      // A cron must never take the scheduler down; the next run retries.
      this.logger.error(
        `Subscription expiry run failed after ${total} row(s): ${(error as Error).message}`,
      );
    }
    return total;
  }
}
