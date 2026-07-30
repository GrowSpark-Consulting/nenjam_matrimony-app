import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ShortlistService } from '../services/shortlist.service';

function build() {
  const repo = {
    isTargetAvailable: jest.fn().mockResolvedValue(true),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
    exists: jest.fn().mockResolvedValue(false),
    create: jest.fn().mockResolvedValue({ id: 'sl-1' }),
    remove: jest.fn().mockResolvedValue(1),
    list: jest.fn(),
    findFeedProfilesByUserIds: jest.fn().mockResolvedValue([]),
  };
  const notifications = {
    create: jest.fn().mockResolvedValue({}),
    invalidateUnread: jest.fn().mockResolvedValue(undefined),
    dispatchPush: jest.fn().mockResolvedValue(undefined),
  };
  const mapper = { toDtoList: jest.fn().mockResolvedValue([]) };
  const realtime = { emitToUser: jest.fn() };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };
  const service = new ShortlistService(
    prisma as never,
    repo as never,
    notifications as never,
    mapper as never,
    realtime as never,
  );
  return { service, repo, notifications, mapper, realtime };
}

describe('ShortlistService.add', () => {
  it('rejects shortlisting yourself', async () => {
    const { service } = build();
    await expect(service.add('me', 'me')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('404s when the target is unavailable', async () => {
    const { service, repo } = build();
    repo.isTargetAvailable.mockResolvedValue(false);
    await expect(service.add('me', 'target')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('soft-skips a blocked relationship (no row, no notification, no error)', async () => {
    const { service, repo, notifications } = build();
    repo.isBlockedBetween.mockResolvedValue(true);
    await service.add('me', 'target');
    expect(repo.create).not.toHaveBeenCalled();
    expect(notifications.create).not.toHaveBeenCalled();
  });

  it('is idempotent: re-adding an existing entry is a no-op', async () => {
    const { service, repo, notifications } = build();
    repo.exists.mockResolvedValue(true);
    await service.add('me', 'target');
    expect(repo.create).not.toHaveBeenCalled();
    expect(notifications.create).not.toHaveBeenCalled();
  });

  it('creates the entry + a SHORTLIST_ADDED notification atomically', async () => {
    const { service, repo, notifications } = build();
    await service.add('me', 'target');
    expect(repo.create).toHaveBeenCalledTimes(1);
    expect(notifications.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: 'target', type: 'SHORTLIST_ADDED' }),
    );
    expect(notifications.invalidateUnread).toHaveBeenCalledWith('target');
  });

  it('treats a unique-constraint race (P2002) as a successful no-op', async () => {
    const { service, repo } = build();
    repo.create.mockRejectedValue({ code: 'P2002' });
    await expect(service.add('me', 'target')).resolves.toBeUndefined();
  });
});

describe('ShortlistService.remove', () => {
  it('delegates to an idempotent repository remove', async () => {
    const { service, repo } = build();
    await service.remove('me', 'target');
    expect(repo.remove).toHaveBeenCalledWith('me', 'target');
  });
});

describe('ShortlistService.list', () => {
  it('maps targets to Discover cards, preserves order, and drops missing profiles', async () => {
    const { service, repo, mapper } = build();
    repo.list.mockResolvedValue([
      [
        { id: 's1', userId: 'me', targetUserId: 't1', createdAt: new Date() },
        { id: 's2', userId: 'me', targetUserId: 't2', createdAt: new Date() },
      ],
      2,
    ]);
    // t2 has no finalized profile.
    mapper.toDtoList.mockResolvedValue([{ id: 't1', name: 'T One' }]);

    const result = await service.list('me', {
      skip: 0,
      take: 20,
      pageNumber: 1,
    } as never);

    expect(repo.findFeedProfilesByUserIds).toHaveBeenCalledWith(['t1', 't2']);
    expect(result).toEqual([{ id: 't1', name: 'T One' }]);
  });
});
