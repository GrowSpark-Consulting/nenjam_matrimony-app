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
