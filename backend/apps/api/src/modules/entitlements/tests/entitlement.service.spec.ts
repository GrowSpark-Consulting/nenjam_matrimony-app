import type { PrismaService } from '@app/database';
import { activePremiumSubscriptionWhere } from '@app/database';
import { EntitlementRepository } from '../repositories/entitlement.repository';
import { EntitlementService } from '../services/entitlement.service';

const NOW = new Date('2026-09-22T00:00:00.000Z');

function build(found: { id: string } | null) {
  const findFirst = jest.fn().mockResolvedValue(found);
  const repository = new EntitlementRepository({
    userSubscription: { findFirst },
  } as unknown as PrismaService);
  return { service: new EntitlementService(repository), findFirst };
}

describe('EntitlementService.hasActivePremiumSubscription', () => {
  it('is true when the member has a subscription matching the shared premium rule', async () => {
    const { service } = build({ id: 'sub-1' });
    await expect(service.hasActivePremiumSubscription('u1', NOW)).resolves.toBe(
      true,
    );
  });

  it('is false when no subscription matches (none, expired, cancelled, pending, FREE)', async () => {
    const { service } = build(null);
    await expect(service.hasActivePremiumSubscription('u1', NOW)).resolves.toBe(
      false,
    );
  });

  it("queries only the member's own rows, with the shared rule, selecting just the id", async () => {
    const { service, findFirst } = build(null);
    await service.hasActivePremiumSubscription('u1', NOW);
    expect(findFirst).toHaveBeenCalledTimes(1);
    expect(findFirst).toHaveBeenCalledWith({
      where: { userId: 'u1', ...activePremiumSubscriptionWhere(NOW) },
      select: { id: true },
    });
  });
});
