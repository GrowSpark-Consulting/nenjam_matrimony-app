import { ForbiddenException } from '@nestjs/common';
import type { MembershipEnforcementMode } from '@app/config';
import { ShortlistService } from '../services/shortlist.service';
import {
  inForce,
  membershipWithPlans,
} from '../../entitlements/tests/catalog-fixtures';

// The shortlist cap (shortlist.profiles: Free 10, Gold/Platinum unlimited).

function build(mode: MembershipEnforcementMode, held: number, members = {}) {
  const repo = {
    isTargetAvailable: jest.fn().mockResolvedValue(true),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
    exists: jest.fn().mockResolvedValue(false),
    create: jest.fn().mockResolvedValue({ id: 'sl-1' }),
    countForUser: jest.fn().mockResolvedValue(held),
  };
  const membership = membershipWithPlans(mode, members);
  const service = new ShortlistService(
    {
      $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({ tx: 1 })),
    } as never,
    repo as never,
    {
      create: jest.fn().mockResolvedValue({}),
      invalidateUnread: jest.fn().mockResolvedValue(undefined),
      dispatchPush: jest.fn().mockResolvedValue(undefined),
    } as never,
    { toDtoList: jest.fn() } as never,
    { emitToUser: jest.fn() } as never,
    membership.service,
  );
  return { service, repo, usage: membership.usage };
}

describe('ShortlistService.add — membership cap', () => {
  it('allows a Free member up to 10, counting under a lock inside the transaction', async () => {
    const { service, repo, usage } = build('enforce', 9);
    await service.add('free', 'target');
    expect(repo.create).toHaveBeenCalled();
    expect(usage.lockCap).toHaveBeenCalledWith(
      { tx: 1 },
      'free',
      'shortlist.profiles',
    );
    expect(repo.countForUser).toHaveBeenCalledWith({ tx: 1 }, 'free');
  });

  it('refuses the 11th for a Free member', async () => {
    const { service, repo } = build('enforce', 10);
    const error = await service.add('free', 'target').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ForbiddenException);
    expect((error as ForbiddenException).getResponse()).toMatchObject({
      feature: 'shortlist.profiles',
      limit: 10,
    });
    expect(repo.create).not.toHaveBeenCalled();
  });

  it('never caps a Gold member', async () => {
    const { service, repo } = build('enforce', 500, {
      gold: [inForce('GOLD')],
    });
    await service.add('gold', 'target');
    expect(repo.create).toHaveBeenCalled();
  });

  it('re-adding an existing entry is still a free no-op', async () => {
    const { service, repo } = build('enforce', 10);
    repo.exists.mockResolvedValueOnce(true);
    await expect(service.add('free', 'target')).resolves.toBeUndefined();
  });

  it('never caps, nor even counts, under off', async () => {
    const { service, repo } = build('off', 50);
    await service.add('free', 'target');
    expect(repo.create).toHaveBeenCalled();
    expect(repo.countForUser).not.toHaveBeenCalled();
  });
});
