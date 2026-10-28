import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';

export interface ConsumeCommand {
  userId: string;
  feature: string;
  periodKey: string;
  periodEndsAt: Date | null;
  amount: number;
  /** The most the counter may reach; null records without a ceiling. */
  ceiling: number | null;
  /** For per-item features: charging the same item twice costs once. */
  itemKey?: string;
}

export interface ConsumeOutcome {
  /** False only when the ceiling refused the charge. */
  allowed: boolean;
  /** False when [itemKey] was already charged this period (free repeat). */
  charged: boolean;
}

export interface UsageReading {
  feature: string;
  periodKey: string;
  used: number;
}

/**
 * Usage counters. Every write is concurrency-safe by construction, with no
 * application-level locking:
 *
 *  1. The counter row is created with `INSERT … ON CONFLICT DO NOTHING`
 *     (createMany + skipDuplicates), so racing first uses can't collide.
 *  2. The charge is ONE conditional `UPDATE … SET used = used + n WHERE
 *     used <= ceiling - n`. Postgres row-locks the counter and re-checks the
 *     WHERE against the latest committed value before applying it, so N
 *     simultaneous requests against a limit of L admit exactly L — never
 *     L + 1. An integration spec proves this against a real database.
 *
 * Must run inside a transaction (the caller's, so the charge commits or rolls
 * back with the action it pays for — a failed interest send never costs an
 * interest).
 */
@Injectable()
export class UsageRepository {
  constructor(private readonly prisma: PrismaService) {}

  async consume(
    tx: Prisma.TransactionClient,
    command: ConsumeCommand,
  ): Promise<ConsumeOutcome> {
    const { userId, feature, periodKey, amount, ceiling } = command;

    if (command.itemKey !== undefined) {
      const { count } = await tx.membershipUsageItem.createMany({
        data: [{ userId, feature, periodKey, itemKey: command.itemKey }],
        skipDuplicates: true,
      });
      // Already charged for this item this period — allowed, at no cost.
      if (count === 0) return { allowed: true, charged: false };
    }

    if (ceiling !== null && amount > ceiling) {
      return { allowed: false, charged: false };
    }

    await tx.membershipUsageCounter.createMany({
      data: [
        {
          userId,
          feature,
          periodKey,
          used: 0,
          periodEndsAt: command.periodEndsAt,
        },
      ],
      skipDuplicates: true,
    });

    const { count } = await tx.membershipUsageCounter.updateMany({
      where: {
        userId,
        feature,
        periodKey,
        ...(ceiling !== null ? { used: { lte: ceiling - amount } } : {}),
      },
      data: { used: { increment: amount } },
    });
    return { allowed: count === 1, charged: count === 1 };
  }

  /** Current usage for each (feature, period) asked about; absent = 0. */
  async read(
    userId: string,
    keys: Array<{ feature: string; periodKey: string }>,
  ): Promise<UsageReading[]> {
    if (keys.length === 0) return [];
    return this.prisma.membershipUsageCounter.findMany({
      where: {
        userId,
        OR: keys.map(({ feature, periodKey }) => ({ feature, periodKey })),
      },
      select: { feature: true, periodKey: true, used: true },
    });
  }

  /** One counter's value, for the denial message. */
  async usedIn(
    tx: Prisma.TransactionClient,
    userId: string,
    feature: string,
    periodKey: string,
  ): Promise<number> {
    const row = await tx.membershipUsageCounter.findUnique({
      where: { userId_feature_periodKey: { userId, feature, periodKey } },
      select: { used: true },
    });
    return row?.used ?? 0;
  }

  /**
   * Serialises cap checks for one member and feature until [tx] ends: two
   * concurrent uploads can't both count 4 photos and both insert a 5th. A
   * transaction-scoped advisory lock, so it never blocks unrelated writes to
   * the member's rows and is released automatically on commit or rollback.
   */
  async lockCap(
    tx: Prisma.TransactionClient,
    userId: string,
    feature: string,
  ): Promise<void> {
    const key = `membership-cap:${userId}:${feature}`;
    await tx.$queryRaw`SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtextextended(${key}, 0))) AS locked`;
  }
}
