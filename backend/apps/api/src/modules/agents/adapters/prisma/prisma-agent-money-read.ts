/**
 * The Prisma side of the agent's money routes: the display fields of a
 * commission (the referred member's short name, the plan bought) and the
 * agent's push devices (`agent_device_tokens`).
 *
 * Only what an agent may see is selected: the member's first and last name
 * (shortened by `toDisplayName`) and the plan's display name.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentCommissionDisplayPort,
  AgentDevicePlatform,
  AgentDeviceRepository,
  CommissionDisplay,
} from '../../ports/agent-money-read.port';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { toDisplayName } from '../../referral/agent-referral-view';
import { dbFor } from './prisma-agent-tx';

export class PrismaAgentCommissionDisplay implements AgentCommissionDisplayPort {
  constructor(private readonly prisma: PrismaClient) {}

  async describe(
    commissions: ReadonlyArray<{
      id: string;
      paymentId: string;
      attributionId: string;
    }>,
    tx?: AgentTx,
  ): Promise<Map<string, CommissionDisplay>> {
    const result = new Map<string, CommissionDisplay>();
    if (commissions.length === 0) return result;
    const db = dbFor(this.prisma, tx);
    const [payments, attributions] = await Promise.all([
      db.paymentTransaction.findMany({
        where: {
          id: { in: [...new Set(commissions.map((c) => c.paymentId))] },
        },
        select: {
          id: true,
          subscription: { select: { plan: { select: { displayName: true } } } },
        },
      }),
      db.referralAttribution.findMany({
        where: {
          id: { in: [...new Set(commissions.map((c) => c.attributionId))] },
        },
        select: {
          id: true,
          user: {
            select: {
              profile: { select: { firstName: true, lastName: true } },
            },
          },
        },
      }),
    ]);
    const planOf = new Map(
      payments.map((p) => [p.id, p.subscription.plan.displayName]),
    );
    const nameOf = new Map(
      attributions.flatMap((a) =>
        a.user?.profile
          ? [
              [
                a.id,
                toDisplayName(
                  a.user.profile.firstName,
                  a.user.profile.lastName,
                ),
              ] as const,
            ]
          : [],
      ),
    );
    for (const c of commissions) {
      const planName = planOf.get(c.paymentId);
      const referralDisplayName = nameOf.get(c.attributionId);
      if (planName !== undefined && referralDisplayName !== undefined) {
        result.set(c.id, { referralDisplayName, planName });
      }
    }
    return result;
  }
}

export class PrismaAgentDeviceRepository implements AgentDeviceRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async register(
    device: {
      agentId: string;
      fcmToken: string;
      platform: AgentDevicePlatform;
    },
    tx?: AgentTx,
  ): Promise<void> {
    await dbFor(this.prisma, tx).agentDeviceToken.upsert({
      where: { fcmToken: device.fcmToken },
      create: {
        agentId: device.agentId,
        fcmToken: device.fcmToken,
        platform: device.platform,
      },
      update: {
        agentId: device.agentId,
        platform: device.platform,
        isActive: true,
      },
    });
  }
}
