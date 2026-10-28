import { ConflictException, ForbiddenException } from '@nestjs/common';
import { InterestsService } from '../services/interests.service';
import type { MembershipEnforcementMode } from '@app/config';
import {
  inForce,
  membershipWithPlans,
} from '../../entitlements/tests/catalog-fixtures';

// The monthly interest allowance (interests.send: Free 5 / Gold 100 /
// Platinum 300) at the real send path, with a real MembershipService over
// the shipped catalogue. The rest of the send path is mocked as in
// interests.service.spec.ts.

function build(mode: MembershipEnforcementMode, members = {}) {
  const repo = {
    findReceiverState: jest
      .fn()
      .mockResolvedValue({ id: 'r', deletedAt: null, status: 'ACTIVE' }),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
    isProfileComplete: jest.fn().mockResolvedValue(true),
    findReverseActive: jest.fn().mockResolvedValue(null),
    findByPair: jest.fn().mockResolvedValue(null),
    create: jest.fn((_tx: unknown, senderId: string, receiverId: string) =>
      Promise.resolve({
        id: `int-${receiverId}`,
        senderId,
        receiverId,
        status: 'PENDING',
        createdAt: new Date(),
      }),
    ),
    resetToPending: jest.fn(),
  };
  const notifications = {
    create: jest.fn().mockResolvedValue({}),
    invalidateUnread: jest.fn().mockResolvedValue(undefined),
    dispatchPush: jest.fn().mockResolvedValue(undefined),
  };
  const membership = membershipWithPlans(mode, members);
  const service = new InterestsService(
    {
      $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
    } as never,
    repo as never,
    notifications as never,
    { toDtoList: jest.fn() } as never,
    { emitToUser: jest.fn() } as never,
    { sendMatchFound: jest.fn() } as never,
    membership.service,
  );
  return { service, repo, notifications, usage: membership.usage };
}

describe('InterestsService.send — membership allowance', () => {
  it('lets a Free member send 5 interests a month, then refuses the 6th with nothing written', async () => {
    const { service, repo, notifications } = build('enforce');
    for (let i = 1; i <= 5; i++) await service.send('free', `r${i}`);

    const error = await service.send('free', 'r6').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ForbiddenException);
    expect((error as ForbiddenException).getResponse()).toMatchObject({
      code: 'MEMBERSHIP_LIMIT_REACHED',
      feature: 'interests.send',
      limit: 5,
    });
    expect(repo.create).toHaveBeenCalledTimes(5);
    expect(notifications.create).toHaveBeenCalledTimes(5);
  });

  it('lets a Gold member go past the Free allowance', async () => {
    const { service, repo } = build('enforce', { gold: [inForce('GOLD')] });
    for (let i = 1; i <= 6; i++) await service.send('gold', `r${i}`);
    expect(repo.create).toHaveBeenCalledTimes(6);
  });

  it('does not charge a send that is refused as a duplicate', async () => {
    const { service, repo, usage } = build('enforce');
    repo.findByPair.mockResolvedValueOnce({ id: 'x', status: 'PENDING' });
    await expect(service.send('free', 'r1')).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(usage.consume).not.toHaveBeenCalled();
  });

  it('never blocks a send under shadow or off — today’s behaviour', async () => {
    for (const mode of ['shadow', 'off'] as const) {
      const { service, repo } = build(mode);
      for (let i = 1; i <= 7; i++) await service.send('free', `r${i}`);
      expect(repo.create).toHaveBeenCalledTimes(7);
    }
  });
});
