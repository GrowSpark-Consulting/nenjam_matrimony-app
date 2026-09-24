import { NotFoundException } from '@nestjs/common';
import { NotificationsService } from '../services/notifications.service';
import type { Notification } from '../../../../../../libs/database/generated/client';

function notification(over: Partial<Notification> = {}): Notification {
  return {
    id: 'n-1',
    userId: 'me',
    type: 'INTEREST_RECEIVED',
    title: 'New interest received',
    body: 'Someone is interested.',
    data: { actorId: 'actor-1', referenceId: 'int-1' },
    isRead: false,
    readAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    ...over,
  };
}

/** Fake ioredis client whose readiness + command results are configurable. */
function makeRedis(status: 'ready' | 'end' = 'ready') {
  const store = new Map<string, string>();
  const client = {
    status,
    get: jest.fn((k: string) => Promise.resolve(store.get(k) ?? null)),
    set: jest.fn((k: string, v: string) => {
      store.set(k, v);
      return Promise.resolve('OK');
    }),
    del: jest.fn((k: string) => {
      store.delete(k);
      return Promise.resolve(1);
    }),
  };
  return { redis: { getClient: () => client }, client, store };
}

function build(redisStatus: 'ready' | 'end' = 'ready') {
  const repo = {
    create: jest.fn(),
    listPaginated: jest.fn(),
    countUnread: jest.fn().mockResolvedValue(0),
    markOneRead: jest.fn().mockResolvedValue(1),
    markAllRead: jest.fn().mockResolvedValue(3),
    existsForUser: jest.fn().mockResolvedValue(true),
    findActorSnapshots: jest.fn().mockResolvedValue([]),
    findDisplayName: jest.fn().mockResolvedValue('Asha Patel'),
  };
  const { redis, client } = makeRedis(redisStatus);
  const s3 = {
    isConfigured: jest.fn().mockReturnValue(true),
    getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed/photo.jpg'),
  };
  const pushDispatch = {
    dispatchToUser: jest.fn().mockResolvedValue(undefined),
  };
  const service = new NotificationsService(
    repo as never,
    redis as never,
    s3 as never,
    pushDispatch as never,
  );
  return { service, repo, client, s3, pushDispatch };
}

describe('NotificationsService.dispatchPush', () => {
  const newMessage = {
    userId: 'peer',
    type: 'NEW_MESSAGE' as const,
    title: 'New message',
    body: 'You have a new message.',
    data: { actorId: 'me', referenceId: 'r1' },
  };

  it('addresses the stored notification recipient and flattens its data', async () => {
    const { service, pushDispatch } = build();
    await service.dispatchPush(newMessage);

    expect(pushDispatch.dispatchToUser).toHaveBeenCalledWith(
      'peer',
      {
        title: 'New message',
        body: 'You have a new message.',
        data: { type: 'NEW_MESSAGE', actorId: 'me', referenceId: 'r1' },
      },
      { excludeUserId: undefined },
    );
  });

  it('forwards excludeUserId and the push-only content override', async () => {
    const { service, pushDispatch } = build();
    await service.dispatchPush(newMessage, {
      excludeUserId: 'me',
      override: {
        title: 'Asha Patel',
        body: 'hi there',
        data: { type: 'chat', conversationId: 'r1', senderId: 'me' },
      },
    });

    expect(pushDispatch.dispatchToUser).toHaveBeenCalledWith(
      'peer',
      {
        title: 'Asha Patel',
        body: 'hi there',
        data: { type: 'chat', conversationId: 'r1', senderId: 'me' },
      },
      { excludeUserId: 'me' },
    );
  });
});

describe('NotificationsService.getUnreadCount', () => {
  it('returns the cached value without hitting the DB', async () => {
    const { service, repo, client } = build();
    await client.set('notif:unread:me', '7');
    const count = await service.getUnreadCount('me');
    expect(count).toBe(7);
    expect(repo.countUnread).not.toHaveBeenCalled();
  });

  it('on a cache miss, counts from the DB and populates the cache', async () => {
    const { service, repo, client } = build();
    repo.countUnread.mockResolvedValue(4);
    const count = await service.getUnreadCount('me');
    expect(count).toBe(4);
    expect(client.set).toHaveBeenCalledWith(
      'notif:unread:me',
      '4',
      'EX',
      expect.any(Number),
    );
  });

  it('fails open to the DB count when Redis is unavailable', async () => {
    const { service, repo, client } = build('end');
    repo.countUnread.mockResolvedValue(9);
    const count = await service.getUnreadCount('me');
    expect(count).toBe(9);
    expect(client.get).not.toHaveBeenCalled();
  });
});

describe('NotificationsService.markRead', () => {
  it('marks read and invalidates the cache', async () => {
    const { service, repo, client } = build();
    await client.set('notif:unread:me', '3');
    await service.markRead('me', 'n-1');
    expect(repo.markOneRead).toHaveBeenCalledWith('me', 'n-1');
    expect(client.del).toHaveBeenCalledWith('notif:unread:me');
  });

  it('is a no-op (no throw) when the notification is already read', async () => {
    const { service, repo } = build();
    repo.markOneRead.mockResolvedValue(0);
    repo.existsForUser.mockResolvedValue(true);
    await expect(service.markRead('me', 'n-1')).resolves.toBeUndefined();
  });

  it('404s when the notification does not belong to the user', async () => {
    const { service, repo } = build();
    repo.markOneRead.mockResolvedValue(0);
    repo.existsForUser.mockResolvedValue(false);
    await expect(service.markRead('me', 'n-1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('NotificationsService.markAllRead', () => {
  it('marks all read and sets the cached count to zero', async () => {
    const { service, repo, client } = build();
    await service.markAllRead('me');
    expect(repo.markAllRead).toHaveBeenCalledWith('me');
    expect(client.set).toHaveBeenCalledWith(
      'notif:unread:me',
      '0',
      'EX',
      expect.any(Number),
    );
  });
});

describe('NotificationsService.list', () => {
  it('shapes items, resolves actors in one batch, and builds the page envelope', async () => {
    const { service, repo } = build();
    repo.listPaginated.mockResolvedValue([[notification()], 1]);
    repo.findActorSnapshots.mockResolvedValue([
      {
        userId: 'actor-1',
        firstName: 'Actor',
        lastName: 'One',
        user: { photos: [{ s3Key: 'photos/a.jpg' }] },
      },
    ]);

    const page = await service.list('me', {
      skip: 0,
      take: 20,
      pageNumber: 1,
    });

    // The recipient is passed so the actor's photo privacy is evaluated
    // against them, inside the same batch query.
    expect(repo.findActorSnapshots).toHaveBeenCalledWith(['actor-1'], 'me');
    expect(page).toMatchObject({
      page: 1,
      limit: 20,
      total: 1,
      hasMore: false,
    });
    expect(page.items[0]).toMatchObject({
      id: 'n-1',
      type: 'INTEREST_RECEIVED',
      message: 'Someone is interested.',
      isRead: false,
      createdAt: '2026-01-01T00:00:00.000Z',
      referenceId: 'int-1',
      actor: {
        id: 'actor-1',
        name: 'Actor One',
        photoUrl: 'https://signed/photo.jpg',
      },
    });
  });

  it('leaves actor null for a notification with no actorId', async () => {
    const { service, repo } = build();
    repo.listPaginated.mockResolvedValue([
      [notification({ type: 'SYSTEM', data: {} })],
      1,
    ]);

    const page = await service.list('me', {
      skip: 0,
      take: 20,
      pageNumber: 1,
    });

    expect(repo.findActorSnapshots).not.toHaveBeenCalled();
    expect(page.items[0].actor).toBeNull();
  });

  describe('actor photo privacy', () => {
    async function listWithActor(user: Record<string, unknown>) {
      const built = build();
      built.repo.listPaginated.mockResolvedValue([[notification()], 1]);
      built.repo.findActorSnapshots.mockResolvedValue([
        {
          userId: 'actor-1',
          firstName: 'Actor',
          lastName: 'One',
          user: { photos: [{ s3Key: 'photos/a.jpg' }], ...user },
        },
      ]);
      const page = await built.service.list('me', {
        skip: 0,
        take: 20,
        pageNumber: 1,
      });
      return { ...built, actor: page.items[0].actor };
    }

    it('premium actor hiding photos, recipient not connected: no URL is signed', async () => {
      const { actor, s3 } = await listWithActor({
        hidePhotosFromNonConnections: true,
        subscriptions: [{ id: 'sub-1' }],
        receivedInterests: [],
        sentInterests: [],
      });
      expect(actor).toMatchObject({ id: 'actor-1', photoUrl: null });
      expect(s3.getPresignedGetUrl).not.toHaveBeenCalled();
    });

    it('premium actor hiding photos, recipient connected: photo is signed', async () => {
      const { actor, s3 } = await listWithActor({
        hidePhotosFromNonConnections: true,
        subscriptions: [{ id: 'sub-1' }],
        receivedInterests: [],
        sentInterests: [{ id: 'int-9' }],
      });
      expect(actor?.photoUrl).toBe('https://signed/photo.jpg');
      expect(s3.getPresignedGetUrl).toHaveBeenCalledWith('photos/a.jpg');
    });

    it('non-premium actor with the flag on: photo withheld from a stranger (free privacy)', async () => {
      const { actor } = await listWithActor({
        hidePhotosFromNonConnections: true,
        subscriptions: [],
        receivedInterests: [],
        sentInterests: [],
      });
      expect(actor?.photoUrl).toBeNull();
    });

    it('non-premium actor with the flag on: photo visible to a connection', async () => {
      const { actor } = await listWithActor({
        hidePhotosFromNonConnections: true,
        subscriptions: [],
        receivedInterests: [{ id: 'i1' }],
        sentInterests: [],
      });
      expect(actor?.photoUrl).toBe('https://signed/photo.jpg');
    });

    it('flag on but probes missing: fails closed', async () => {
      const { actor, s3 } = await listWithActor({
        hidePhotosFromNonConnections: true,
      });
      expect(actor?.photoUrl).toBeNull();
      expect(s3.getPresignedGetUrl).not.toHaveBeenCalled();
    });
  });
});
