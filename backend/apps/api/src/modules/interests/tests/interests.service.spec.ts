import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { InterestsService } from '../services/interests.service';
import type { ExpressInterest } from '../../../../../../libs/database/generated/client';

function interest(over: Partial<ExpressInterest> = {}): ExpressInterest {
  return {
    id: 'int-1',
    senderId: 'sender-1',
    receiverId: 'receiver-1',
    status: 'PENDING',
    royalNote: null,
    respondedAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    ...over,
  };
}

function build() {
  const repo = {
    findReceiverState: jest.fn().mockResolvedValue({
      id: 'receiver-1',
      deletedAt: null,
      status: 'ACTIVE',
    }),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
    isProfileComplete: jest.fn().mockResolvedValue(true),
    findReverseActive: jest.fn().mockResolvedValue(null),
    findByPair: jest.fn().mockResolvedValue(null),
    create: jest.fn().mockResolvedValue(interest()),
    resetToPending: jest.fn().mockResolvedValue(interest()),
    respondIfPending: jest.fn().mockResolvedValue(1),
    deletePendingSent: jest.fn().mockResolvedValue(1),
    findById: jest.fn(),
    listReceived: jest.fn(),
    listSent: jest.fn(),
    findFeedProfilesByUserIds: jest.fn().mockResolvedValue([]),
  };
  const notifications = {
    create: jest.fn().mockResolvedValue({}),
    invalidateUnread: jest.fn().mockResolvedValue(undefined),
    dispatchPush: jest.fn().mockResolvedValue(undefined),
  };
  const mapper = { toDtoList: jest.fn().mockResolvedValue([]) };
  const realtime = { emitToUser: jest.fn() };
  // Transparent transaction: run the callback with a passthrough tx client.
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };

  const service = new InterestsService(
    prisma as never,
    repo as never,
    notifications as never,
    mapper as never,
    realtime as never,
  );
  return { service, repo, notifications, mapper, realtime };
}

describe('InterestsService.send', () => {
  it('rejects sending to yourself', async () => {
    const { service } = build();
    await expect(service.send('me', 'me')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('404s when the receiver does not exist', async () => {
    const { service, repo } = build();
    repo.findReceiverState.mockResolvedValue(null);
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('404s when the receiver is soft-deleted', async () => {
    const { service, repo } = build();
    repo.findReceiverState.mockResolvedValue({
      id: 'receiver-1',
      deletedAt: new Date(),
      status: 'ACTIVE',
    });
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('forbids sending to a suspended/banned member', async () => {
    const { service, repo } = build();
    repo.findReceiverState.mockResolvedValue({
      id: 'receiver-1',
      deletedAt: null,
      status: 'BANNED',
    });
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('forbids sending across a block (either direction)', async () => {
    const { service, repo } = build();
    repo.isBlockedBetween.mockResolvedValue(true);
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('forbids sending when the sender profile is incomplete', async () => {
    const { service, repo } = build();
    repo.isProfileComplete.mockResolvedValue(false);
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('409s when the receiver already sent an active interest (reverse)', async () => {
    const { service, repo } = build();
    repo.findReverseActive.mockResolvedValue(
      interest({ senderId: 'receiver-1' }),
    );
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('creates a PENDING interest + INTEREST_RECEIVED notification atomically', async () => {
    const { service, repo, notifications, realtime } = build();
    const result = await service.send('sender-1', 'receiver-1');

    expect(repo.create).toHaveBeenCalledTimes(1);
    expect(notifications.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'receiver-1',
        type: 'INTEREST_RECEIVED',
        data: { actorId: 'sender-1', referenceId: 'int-1' },
      }),
    );
    expect(notifications.invalidateUnread).toHaveBeenCalledWith('receiver-1');
    // Real-time signal delivered to the receiver after commit.
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'receiver-1',
      'interest.created',
      expect.objectContaining({ id: 'int-1' }),
    );
    expect(result).toEqual({
      id: 'int-1',
      sentAt: '2026-01-01T00:00:00.000Z',
      status: 'pending',
    });
  });

  it('re-sends a previously DECLINED interest by resetting it to PENDING', async () => {
    const { service, repo } = build();
    repo.findByPair.mockResolvedValue(interest({ status: 'DECLINED' }));
    await service.send('sender-1', 'receiver-1');
    expect(repo.resetToPending).toHaveBeenCalledTimes(1);
    expect(repo.create).not.toHaveBeenCalled();
  });

  it('409s on a duplicate PENDING interest', async () => {
    const { service, repo } = build();
    repo.findByPair.mockResolvedValue(interest({ status: 'PENDING' }));
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('maps a unique-constraint race (P2002) to a 409', async () => {
    const { service, repo } = build();
    repo.create.mockRejectedValue({ code: 'P2002' });
    await expect(service.send('sender-1', 'receiver-1')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });
});

describe('InterestsService.respond', () => {
  it('404s for an unknown interest', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(null);
    await expect(
      service.respond('receiver-1', 'int-1', true),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('forbids responding to an interest not sent to you', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest({ receiverId: 'someone-else' }));
    await expect(
      service.respond('receiver-1', 'int-1', true),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('accepts a pending interest + notifies the sender', async () => {
    const { service, repo, notifications } = build();
    repo.findById.mockResolvedValue(interest());
    const result = await service.respond('receiver-1', 'int-1', true);

    expect(repo.respondIfPending).toHaveBeenCalledWith(
      expect.anything(),
      'int-1',
      'ACCEPTED',
    );
    expect(notifications.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        type: 'INTEREST_ACCEPTED',
        userId: 'sender-1',
      }),
    );
    expect(result.status).toBe('accepted');
  });

  it('is idempotent: re-accepting an already-accepted interest is a no-op', async () => {
    const { service, repo, notifications } = build();
    repo.findById.mockResolvedValue(interest({ status: 'ACCEPTED' }));
    const result = await service.respond('receiver-1', 'int-1', true);
    expect(result.status).toBe('accepted');
    expect(repo.respondIfPending).not.toHaveBeenCalled();
    expect(notifications.create).not.toHaveBeenCalled();
  });

  it('409s when responding to a non-pending interest with a different action', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest({ status: 'ACCEPTED' }));
    await expect(
      service.respond('receiver-1', 'int-1', false),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('409s when it loses the respond race (0 rows updated)', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest());
    repo.respondIfPending.mockResolvedValue(0);
    await expect(
      service.respond('receiver-1', 'int-1', true),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});

describe('InterestsService.withdraw', () => {
  it('404s for an unknown interest', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(null);
    await expect(service.withdraw('sender-1', 'int-1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('forbids withdrawing an interest you did not send', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest({ senderId: 'someone-else' }));
    await expect(service.withdraw('sender-1', 'int-1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('409s when the interest is no longer pending', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest({ status: 'ACCEPTED' }));
    await expect(service.withdraw('sender-1', 'int-1')).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it('deletes a pending sent interest', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest());
    await service.withdraw('sender-1', 'int-1');
    expect(repo.deletePendingSent).toHaveBeenCalledWith('sender-1', 'int-1');
  });

  it('404s when it loses the withdraw race (0 rows deleted)', async () => {
    const { service, repo } = build();
    repo.findById.mockResolvedValue(interest());
    repo.deletePendingSent.mockResolvedValue(0);
    await expect(service.withdraw('sender-1', 'int-1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});

describe('InterestsService lists', () => {
  it('received: joins each row to the SENDER profile, lowercases status, skips missing profiles', async () => {
    const { service, repo, mapper } = build();
    repo.listReceived.mockResolvedValue([
      [
        interest({ id: 'a', senderId: 's1', status: 'PENDING' }),
        interest({ id: 'b', senderId: 's2', status: 'ACCEPTED' }),
      ],
      2,
    ]);
    // s2 has no finalized profile -> that row is dropped.
    mapper.toDtoList.mockResolvedValue([{ id: 's1', name: 'S One' }]);

    const items = await service.listReceived('me', {
      skip: 0,
      take: 20,
      pageNumber: 1,
    });

    expect(repo.findFeedProfilesByUserIds).toHaveBeenCalledWith(['s1', 's2']);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({
      id: 'a',
      status: 'pending',
      profile: { id: 's1' },
    });
  });

  it('sent: joins each row to the RECEIVER profile', async () => {
    const { service, repo, mapper } = build();
    repo.listSent.mockResolvedValue([
      [interest({ id: 'a', receiverId: 'r1' })],
      1,
    ]);
    mapper.toDtoList.mockResolvedValue([{ id: 'r1', name: 'R One' }]);

    const items = await service.listSent('me', {
      skip: 0,
      take: 20,
      pageNumber: 1,
    });

    expect(repo.findFeedProfilesByUserIds).toHaveBeenCalledWith(['r1']);
    expect(items[0].profile).toMatchObject({ id: 'r1' });
  });
});

describe('InterestsService.dispatchMatchInterest', () => {
  it('routes { profileId } to send', async () => {
    const { service } = build();
    const spy = jest
      .spyOn(service, 'send')
      .mockResolvedValue({ id: 'x', sentAt: 'y', status: 'pending' });
    await service.dispatchMatchInterest('me', { profileId: 'p1' });
    expect(spy).toHaveBeenCalledWith('me', 'p1');
  });

  it('routes { interestId, accept } to respond', async () => {
    const { service } = build();
    const spy = jest
      .spyOn(service, 'respond')
      .mockResolvedValue({ id: 'x', sentAt: 'y', status: 'accepted' });
    await service.dispatchMatchInterest('me', {
      interestId: 'i1',
      accept: true,
    });
    expect(spy).toHaveBeenCalledWith('me', 'i1', true);
  });

  it('400s on an ambiguous/empty body', async () => {
    const { service } = build();
    await expect(
      service.dispatchMatchInterest('me', {}),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
