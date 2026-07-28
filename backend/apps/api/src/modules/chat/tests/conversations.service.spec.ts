import { BadRequestException } from '@nestjs/common';
import { ConversationsService } from '../services/conversations.service';
import type {
  ChatMessage,
  ChatRoom,
} from '../../../../../../libs/database/generated/client';

function room(over: Partial<ChatRoom> = {}): ChatRoom {
  return {
    id: 'r1',
    user1Id: 'me',
    user2Id: 'peer',
    isActive: true,
    lastMessageAt: new Date('2026-01-02T00:00:00.000Z'),
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-02T00:00:00.000Z'),
    ...over,
  };
}

function message(over: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 'm1',
    roomId: 'r1',
    senderId: 'peer',
    content: 'hey',
    type: 'TEXT',
    mediaUrl: null,
    clientMessageId: null,
    status: 'SENT',
    deliveredAt: null,
    isRead: false,
    readAt: null,
    editedAt: null,
    deletedAt: null,
    createdAt: new Date('2026-01-02T00:00:00.000Z'),
    ...over,
  };
}

function build() {
  const conversationRepository = {
    findById: jest.fn().mockResolvedValue(room()),
    hasAcceptedInterest: jest.fn().mockResolvedValue(true),
    getOrCreate: jest.fn().mockResolvedValue(room()),
    listForUser: jest.fn(),
    unreadCountsByRoom: jest.fn().mockResolvedValue(new Map()),
    blockedPeerIds: jest.fn().mockResolvedValue(new Set()),
    findFeedProfilesByUserIds: jest.fn().mockResolvedValue([]),
    statesByRoom: jest.fn().mockResolvedValue(new Map()),
    upsertState: jest.fn().mockResolvedValue({}),
    block: jest.fn().mockResolvedValue({ id: 'b1' }),
    unblock: jest.fn().mockResolvedValue(undefined),
  };
  const messageRepository = {
    listPaged: jest.fn().mockResolvedValue([[], 0]),
    markRoomRead: jest.fn().mockResolvedValue(1),
  };
  const profileMapper = { toDtoList: jest.fn().mockResolvedValue([]) };
  const realtime = { emitToUser: jest.fn() };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };
  const service = new ConversationsService(
    prisma as never,
    conversationRepository as never,
    messageRepository as never,
    profileMapper as never,
    realtime as never,
  );
  return {
    service,
    conversationRepository,
    messageRepository,
    profileMapper,
    realtime,
  };
}

const PAGE = { skip: 0, take: 20, pageNumber: 1 } as never;

describe('ConversationsService.getOrCreate', () => {
  it('rejects a self-conversation', async () => {
    const { service } = build();
    await expect(service.getOrCreate('me', 'me')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('403s when there is no accepted interest', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.hasAcceptedInterest.mockResolvedValue(false);
    await expect(service.getOrCreate('me', 'peer')).rejects.toThrow(
      'Users cannot message until interest is accepted.',
    );
  });

  it('creates (or returns) the room when interest is accepted', async () => {
    const { service, conversationRepository } = build();
    const result = await service.getOrCreate('me', 'peer');
    expect(conversationRepository.getOrCreate).toHaveBeenCalled();
    expect(result).toMatchObject({ id: 'r1' });
  });
});

describe('ConversationsService.list', () => {
  it('joins rooms to peer profile + unread + block, skipping peers without a profile', async () => {
    const {
      service,
      conversationRepository,
      messageRepository,
      profileMapper,
    } = build();
    conversationRepository.listForUser.mockResolvedValue([
      [
        {
          ...room({ id: 'r1', user2Id: 'peer1' }),
          messages: [message({ senderId: 'peer1' })],
        },
        { ...room({ id: 'r2', user2Id: 'peer2' }), messages: [] },
      ],
      2,
    ]);
    conversationRepository.unreadCountsByRoom.mockResolvedValue(
      new Map([['r1', 3]]),
    );
    conversationRepository.blockedPeerIds.mockResolvedValue(new Set(['peer1']));
    // peer2 has no finalized profile → its row is dropped.
    profileMapper.toDtoList.mockResolvedValue([
      { id: 'peer1', name: 'Peer One' },
    ]);

    void messageRepository;
    const page = await service.list('me', PAGE);

    expect(page.total).toBe(2);
    expect(page.items).toHaveLength(1);
    expect(page.items[0]).toMatchObject({
      id: 'r1',
      unreadCount: 3,
      isBlocked: true,
      lastMessage: 'hey',
      lastMessageFromMe: false,
      profile: { id: 'peer1' },
    });
  });
});

describe('ConversationsService.list per-user state', () => {
  it('floats pinned to the top, applies the mark-unread override, and hides delete-for-me rows', async () => {
    const { service, conversationRepository, profileMapper } = build();
    conversationRepository.listForUser.mockResolvedValue([
      [
        {
          ...room({ id: 'r2', user2Id: 'peer2' }),
          lastMessageAt: new Date('2026-01-03T00:00:00.000Z'),
          messages: [message({ senderId: 'peer2' })],
        },
        {
          ...room({ id: 'r1', user2Id: 'peer1' }),
          lastMessageAt: new Date('2026-01-02T00:00:00.000Z'),
          messages: [message({ senderId: 'peer1' })],
        },
        {
          ...room({ id: 'r3', user2Id: 'peer3' }),
          lastMessageAt: new Date('2026-01-02T00:00:00.000Z'),
          messages: [message({ senderId: 'peer3' })],
        },
      ],
      3,
    ]);
    conversationRepository.statesByRoom.mockResolvedValue(
      new Map<string, unknown>([
        ['r1', { roomId: 'r1', markUnread: true }],
        ['r2', { roomId: 'r2', isPinned: true }],
        [
          'r3',
          { roomId: 'r3', deletedUntil: new Date('2026-01-05T00:00:00.000Z') },
        ],
      ]),
    );
    profileMapper.toDtoList.mockResolvedValue([
      { id: 'peer1', name: 'One' },
      { id: 'peer2', name: 'Two' },
      { id: 'peer3', name: 'Three' },
    ]);

    const page = await service.list('me', PAGE);

    // r3 hidden (deletedUntil newer than its last activity); r2 pinned floats top.
    expect(page.items.map((i) => i.id)).toEqual(['r2', 'r1']);
    expect(page.items[0]).toMatchObject({ id: 'r2', isPinned: true });
    // r1 has no real unread, but mark-unread surfaces one.
    expect(page.items[1]).toMatchObject({ id: 'r1', unreadCount: 1 });
  });
});

describe('ConversationsService per-user state mutators', () => {
  it('updateState maps pinned/muted/archived and upserts the caller state', async () => {
    const { service, conversationRepository } = build();
    await service.updateState('me', 'r1', {
      isPinned: true,
      isMuted: false,
      isArchived: undefined,
    });
    expect(conversationRepository.upsertState).toHaveBeenCalledWith(
      'me',
      'r1',
      {
        isPinned: true,
        isMuted: false,
        isArchived: undefined,
      },
    );
  });

  it('markUnread sets the flag', async () => {
    const { service, conversationRepository } = build();
    await service.markUnread('me', 'r1');
    expect(conversationRepository.upsertState).toHaveBeenCalledWith(
      'me',
      'r1',
      {
        markUnread: true,
      },
    );
  });

  it('deleteForMe stamps deletedUntil', async () => {
    const { service, conversationRepository } = build();
    await service.deleteForMe('me', 'r1');
    const calls = conversationRepository.upsertState.mock.calls as unknown[][];
    const patch = calls[0][2] as { deletedUntil?: Date };
    expect(patch.deletedUntil).toBeInstanceOf(Date);
  });
});

describe('ConversationsService.markRead', () => {
  it('marks read and emits a read receipt to the peer', async () => {
    const { service, realtime } = build();
    await service.markRead('me', 'r1');
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'peer',
      'chat.read',
      expect.objectContaining({ id: 'r1' }),
    );
  });

  it('does not emit when nothing changed', async () => {
    const { service, messageRepository, realtime } = build();
    messageRepository.markRoomRead.mockResolvedValue(0);
    await service.markRead('me', 'r1');
    expect(realtime.emitToUser).not.toHaveBeenCalled();
  });
});
