/**
 * `ReferralCodeAttemptStore` on the `referral_code_attempts` table.
 *
 * - The requester key is OPAQUE (a keyed hash, or a namespaced member id). A
 *   raw IPv4/IPv6 address is refused with a `RangeError` before anything is
 *   stored: an IP is personal data.
 * - `window` counts attempts strictly after `since` for one requester or one
 *   code, and reports the earliest of them.
 * - Reading the count and then recording is not atomic (an accepted limit,
 *   see the port): parallel requests can pass a limit by a few.
 * - Every `record` also purges a small batch of expired attempts (see
 *   `prisma-bounded-purge.ts`): attempts older than `now - graceMs`. The
 *   grace period must be at least the longest window any caller counts over,
 *   or a still-relevant attempt could be purged.
 */
import type { PrismaClient } from '@app/database';
import type {
  ReferralAttemptDimension,
  ReferralCodeAttemptStore,
  ReferralCodeAttemptWindow,
} from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { looksLikeRawIp } from '../../referral/requester-key';
import { dbFor } from './prisma-agent-tx';
import {
  checkPurgeOptions,
  runPurge,
  type BoundedPurgeOptions,
} from './prisma-bounded-purge';

export class PrismaReferralCodeAttemptStore implements ReferralCodeAttemptStore {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly purge: BoundedPurgeOptions,
  ) {
    checkPurgeOptions(purge);
  }

  async window(
    dimension: ReferralAttemptDimension,
    key: string,
    since: Date,
    tx?: AgentTx,
  ): Promise<ReferralCodeAttemptWindow> {
    const result = await dbFor(this.prisma, tx).referralCodeAttempt.aggregate({
      where: {
        ...(dimension === 'REQUESTER'
          ? { requesterKey: key }
          : { codeKey: key }),
        attemptedAt: { gt: since },
      },
      _count: { _all: true },
      _min: { attemptedAt: true },
    });
    return {
      count: result._count._all,
      oldestAt: result._min.attemptedAt,
    };
  }

  async record(
    attempt: { requesterKey: string; codeKey: string | null; at: Date },
    tx?: AgentTx,
  ): Promise<void> {
    if (looksLikeRawIp(attempt.requesterKey)) {
      throw new RangeError(
        'requesterKey must be a hashed key, not a raw IP address.',
      );
    }
    await dbFor(this.prisma, tx).referralCodeAttempt.create({
      data: {
        requesterKey: attempt.requesterKey,
        codeKey: attempt.codeKey,
        attemptedAt: attempt.at,
      },
    });
    await this.purgeExpired();
  }

  private purgeExpired(): Promise<void> {
    return runPurge(this.purge, 'attempts', async (cutoff, batchSize) => {
      const expired = await this.prisma.referralCodeAttempt.findMany({
        where: { attemptedAt: { lt: cutoff } },
        orderBy: { attemptedAt: 'asc' },
        take: batchSize,
        select: { id: true },
      });
      if (expired.length === 0) return;
      await this.prisma.referralCodeAttempt.deleteMany({
        where: {
          id: { in: expired.map((r) => r.id) },
          attemptedAt: { lt: cutoff },
        },
      });
    });
  }
}
