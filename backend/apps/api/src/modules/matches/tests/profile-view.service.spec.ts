import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ProfileViewService } from '../services/profile-view.service';

function build() {
  const repo = {
    isTargetAvailable: jest.fn().mockResolvedValue(true),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
    hasViewedSince: jest.fn().mockResolvedValue(false),
    create: jest.fn().mockResolvedValue({ id: 'pv-1' }),
    listViewers: jest.fn().mockResolvedValue([[], 0]),
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
  const service = new ProfileViewService(
    prisma as never,
    repo as never,
    notifications as never,
    mapper as never,
    realtime as never,
  );
  return { service, repo, notifications, mapper, realtime };
}

describe('ProfileViewService.record', () => {
  it('rejects viewing your own profile', async () => {
    const { service } = build();
    await expect(service.record('me', 'me')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('404s when the target is unavailable', async () => {
    const { service, repo } = build();
    repo.isTargetAvailable.mockResolvedValue(false);
    await expect(service.record('me', 'target')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('soft-skips a blocked relationship (no row, no notification, no error)', async () => {
    const { service, repo, notifications } = build();
    repo.isBlockedBetween.mockResolvedValue(true);
    await service.record('me', 'target');
    expect(repo.create).not.toHaveBeenCalled();
    expect(notifications.create).not.toHaveBeenCalled();
  });

  it('logs the view + a PROFILE_VIEW notification atomically on a first view', async () => {
    const { service, repo, notifications } = build();
    await service.record('me', 'target');

    expect(repo.create).toHaveBeenCalledTimes(1);
    expect(notifications.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'target',
        type: 'PROFILE_VIEW',
        // `userId` is the alias the client's deep-link parser reads first;
        // `actorId` is the generic pipeline field. Both must ship.
        data: { actorId: 'me', userId: 'me' },
      }),
    );
    expect(notifications.invalidateUnread).toHaveBeenCalledWith('target');
    expect(notifications.dispatchPush).toHaveBeenCalledTimes(1);
  });

  it('still logs a repeat view but does not notify again inside the window', async () => {
    const { service, repo, notifications, realtime } = build();
    repo.hasViewedSince.mockResolvedValue(true);

    await service.record('me', 'target');

    // The event log is complete regardless — only the push is throttled.
    expect(repo.create).toHaveBeenCalledTimes(1);
    expect(notifications.create).not.toHaveBeenCalled();
    expect(notifications.invalidateUnread).not.toHaveBeenCalled();
    expect(notifications.dispatchPush).not.toHaveBeenCalled();
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });

  it('throttles on a 24h window', async () => {
    const { service, repo } = build();
    await service.record('me', 'target');

    const since = repo.hasViewedSince.mock.calls[0][2] as Date;
    const elapsedHours = (Date.now() - since.getTime()) / 3_600_000;
    expect(elapsedHours).toBeCloseTo(24, 1);
  });
});

describe('ProfileViewService.listViewers', () => {
  const pagination = { skip: 0, take: 20 } as never;

  it('returns an empty list without hitting the profile mapper', async () => {
    const { service, mapper } = build();
    await expect(service.listViewers('me', pagination)).resolves.toEqual([]);
    expect(mapper.toDtoList).not.toHaveBeenCalled();
  });

  it('preserves most-recent-first order and attaches each viewedAt', async () => {
    const { service, repo, mapper } = build();
    const newer = new Date('2026-08-10T10:00:00.000Z');
    const older = new Date('2026-08-09T10:00:00.000Z');
    repo.listViewers.mockResolvedValue([
      [
        { viewerId: 'u1', lastViewedAt: newer },
        { viewerId: 'u2', lastViewedAt: older },
      ],
      2,
    ]);
    // Returned deliberately out of order — order must come from the view
    // rows, not from whatever order the profile fetch happened to produce.
    mapper.toDtoList.mockResolvedValue([{ id: 'u2' }, { id: 'u1' }]);

    const result = await service.listViewers('me', pagination);

    expect(result).toEqual([
      { profile: { id: 'u1' }, viewedAt: newer.toISOString() },
      { profile: { id: 'u2' }, viewedAt: older.toISOString() },
    ]);
  });

  it('drops viewers with no finalized profile', async () => {
    const { service, repo, mapper } = build();
    repo.listViewers.mockResolvedValue([
      [
        { viewerId: 'u1', lastViewedAt: new Date('2026-08-10T10:00:00.000Z') },
        { viewerId: 'ghost', lastViewedAt: new Date('2026-08-10T09:00:00.000Z') },
      ],
      2,
    ]);
    mapper.toDtoList.mockResolvedValue([{ id: 'u1' }]);

    const result = await service.listViewers('me', pagination);

    expect(result).toHaveLength(1);
    expect(result[0].profile).toEqual({ id: 'u1' });
  });
});
