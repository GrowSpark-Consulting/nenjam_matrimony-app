/**
 * `AgentPaymentSourcePort` over `payment_transactions.payment_source_hash`
 * (added by the Payments migration 20261029130000): has this card / UPI id
 * paid for ANOTHER member? Only successful payments count (`paid_at` set);
 * the payment being judged is left out. Read only; the hash is never logged.
 *
 * There is no index on payment_source_hash: fine at today's volume; an index
 * is a change to Shaaz's table, so it is his to add when it matters.
 */
import type { PrismaClient } from '@app/database';
import type { AgentPaymentSourcePort } from '../../ports/agent-money-ports';

export class PrismaAgentPaymentSource implements AgentPaymentSourcePort {
  constructor(private readonly prisma: PrismaClient) {}

  async wasUsedByAnotherMember(input: {
    paymentSourceHash: string;
    memberId: string;
    excludePaymentId: string;
  }): Promise<boolean> {
    const other = await this.prisma.paymentTransaction.findFirst({
      where: {
        paymentSourceHash: input.paymentSourceHash,
        userId: { not: input.memberId },
        id: { not: input.excludePaymentId },
        paidAt: { not: null },
      },
      select: { id: true },
    });
    return other !== null;
  }
}
