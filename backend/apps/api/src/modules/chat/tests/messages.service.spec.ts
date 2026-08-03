import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { MessagesService } from '../services/messages.service';
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
    lastMessageAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    ...over,
  };
}

function message(over: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 'm1',
    roomId: 'r1',
    senderId: 'me',
    content: 'hi',
    type: 'TEXT',
    mediaUrl: null,
    clientMessageId: null,
    status: 'SENT',
    deliveredAt: null,
    isRead: false,
    readAt: null,
    editedAt: null,
    deletedAt: null,
    createdAt: new Date('2026-01-01T00:00:00.000Z'),
    ...over,
  };
}

function build() {
  const conversationRepository = {
    findById: jest.fn().mockResolvedValue(room()),
    hasAcceptedInterest: jest.fn().mockResolvedValue(true),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
  };
  const messageRepository = {
    create: jest.fn().mockResolvedValue(message()),
    touchRoomActivity: jest.fn().mockResolvedValue({}),
    findByClientKey: jest.fn().mockResolvedValue(null),
    listPaged: jest.fn(),
    listByCursor: jest.fn(),
    findById: jest.fn(),
    updateContent: jest.fn((id: string, content: string, editedAt: Date) =>
      Promise.resolve(message({ id, content, editedAt })),
    ),
    softDelete: jest.fn((id: string, deletedAt: Date) =>
      Promise.resolve(message({ id, deletedAt })),
    ),
  };
  const s3 = {
    isConfigured: jest.fn().mockReturnValue(true),
    getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed/x'),
  };
  const realtime = {
    emitToUser: jest.fn(),
  };
  const presence = {
    isOnline: jest.fn().mockResolvedValue(false),
  };
  const audit = {
    record: jest.fn().mockResolvedValue(undefined),
    recordDenied: jest.fn(),
  };
  const notifications = {
    create: jest.fn().mockResolvedValue(undefined),
    invalidateUnread: jest.fn().mockResolvedValue(undefined),
    dispatchPush: jest.fn().mockResolvedValue(undefined),
  };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };
  const service = new MessagesService(
    prisma as never,
    conversationRepository as never,
    messageRepository as never,
    s3 as never,
    realtime as never,
    presence as never,
    audit as never,
    notifications as never,
  );
  return {
    service,
    conversationRepository,
    messageRepository,
    s3,
    realtime,
    presence,
    audit,
    notifications,
  };
}

// Offset-mode query (no cursor → legacy page path).
const query = (over: Record<string, unknown> = {}) =>
  ({
    conversationId: 'r1',
    skip: 0,
    take: 30,
    pageNumber: 1,
    ...over,
  }) as never;

describe('MessagesService.send', () => {
  it('404s when the room does not exist', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.findById.mockResolvedValue(null);
    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('403s when the caller is not a participant', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.findById.mockResolvedValue(
      room({ user1Id: 'x', user2Id: 'y' }),
    );
    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('403s when no accepted interest exists', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.hasAcceptedInterest.mockResolvedValue(false);
    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).rejects.toThrow('Users cannot message until interest is accepted.');
  });

  it('403s when the pair is blocked', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.isBlockedBetween.mockResolvedValue(true);
    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('400s on empty text', async () => {
    const { service } = build();
    await expect(
      service.send('me', { roomId: 'r1', content: '   ' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('400s on a media message with no mediaUrl', async () => {
    const { service } = build();
    await expect(
      service.send('me', { roomId: 'r1', content: '', type: 'IMAGE' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('creates the message, bumps room activity, and pushes to both parties', async () => {
    const { service, messageRepository, realtime } = build();
    const result = await service.send('me', {
      roomId: 'r1',
      content: 'hi',
      clientMessageId: 'c-123',
    });

    expect(messageRepository.create).toHaveBeenCalledTimes(1);
    expect(messageRepository.touchRoomActivity).toHaveBeenCalledTimes(1);
    // recipient + sender's other devices
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'peer',
      'chat.message',
      expect.objectContaining({ id: 'm1', isMine: false }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'me',
      'chat.message',
      expect.objectContaining({ id: 'm1', isMine: true }),
    );
    expect(result).toMatchObject({
      id: 'm1',
      isMine: true,
      content: 'hi',
      clientMessageId: 'c-123',
    });
  });

  it('creates a NEW_MESSAGE notification for the recipient and dispatches a push — never to the sender', async () => {
    const { service, notifications, realtime } = build();
    await service.send('me', { roomId: 'r1', content: 'hi' });

    expect(notifications.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        userId: 'peer',
        type: 'NEW_MESSAGE',
        data: { actorId: 'me', referenceId: 'r1' },
      }),
    );
    expect(notifications.invalidateUnread).toHaveBeenCalledWith('peer');
    expect(notifications.dispatchPush).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'peer', type: 'NEW_MESSAGE' }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'peer',
      'notification.created',
      expect.objectContaining({ id: 'm1' }),
    );

    // Never the sender.
    expect(notifications.create).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: 'me' }),
    );
    expect(notifications.dispatchPush).not.toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'me' }),
    );
    expect(realtime.emitToUser).not.toHaveBeenCalledWith(
      'me',
      'notification.created',
      expect.anything(),
    );
  });

  it('does not create a duplicate-send notification on an idempotent retry', async () => {
    const { service, messageRepository, notifications } = build();
    messageRepository.findByClientKey.mockResolvedValue(
      message({ id: 'existing' }),
    );
    await service.send('me', {
      roomId: 'r1',
      content: 'hi',
      clientMessageId: 'c-1',
    });
    expect(notifications.create).not.toHaveBeenCalled();
    expect(notifications.dispatchPush).not.toHaveBeenCalled();
  });

  it('is idempotent: a repeated clientMessageId returns the existing message, no second insert', async () => {
    const { service, messageRepository } = build();
    messageRepository.findByClientKey.mockResolvedValue(
      message({ id: 'existing' }),
    );
    const result = await service.send('me', {
      roomId: 'r1',
      content: 'hi',
      clientMessageId: 'c-1',
    });
    expect(result.id).toBe('existing');
    expect(messageRepository.create).not.toHaveBeenCalled();
  });

  it('marks DELIVERED when the recipient is online', async () => {
    const { service, messageRepository, presence } = build();
    presence.isOnline.mockResolvedValue(true);
    messageRepository.create.mockResolvedValue(
      message({ status: 'DELIVERED' }),
    );
    const result = await service.send('me', { roomId: 'r1', content: 'hi' });
    expect(messageRepository.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ status: 'DELIVERED' }),
    );
    expect(result.status).toBe('delivered');
  });
});

describe('MessagesService.edit', () => {
  const recent = () =>
    message({ senderId: 'me', type: 'TEXT', createdAt: new Date() });

  it('404s an unknown or already-deleted message', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(null);
    await expect(service.edit('me', 'm1', 'x')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    messageRepository.findById.mockResolvedValue(
      message({ senderId: 'me', deletedAt: new Date() }),
    );
    await expect(service.edit('me', 'm1', 'x')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('403s a non-sender', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(
      message({ senderId: 'peer', type: 'TEXT', createdAt: new Date() }),
    );
    await expect(service.edit('me', 'm1', 'x')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('400s editing a non-text message', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(
      message({ senderId: 'me', type: 'IMAGE', createdAt: new Date() }),
    );
    await expect(service.edit('me', 'm1', 'x')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('403s once the edit window has passed', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(
      message({
        senderId: 'me',
        type: 'TEXT',
        createdAt: new Date(Date.now() - 16 * 60 * 1000),
      }),
    );
    await expect(service.edit('me', 'm1', 'x')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('400s on empty new content', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(recent());
    await expect(service.edit('me', 'm1', '   ')).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('updates content, stamps editedAt, and broadcasts to both parties', async () => {
    const { service, messageRepository, realtime } = build();
    messageRepository.findById.mockResolvedValue(recent());
    const result = await service.edit('me', 'm1', '  fixed  ');
    expect(messageRepository.updateContent).toHaveBeenCalledWith(
      'm1',
      'fixed',
      expect.any(Date),
    );
    expect(result.content).toBe('fixed');
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'peer',
      'chat.messageEdited',
      expect.objectContaining({ id: 'm1', content: 'fixed', isMine: false }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'me',
      'chat.messageEdited',
      expect.objectContaining({ id: 'm1', isMine: true }),
    );
  });
});

describe('MessagesService.remove', () => {
  it('404s an unknown or already-deleted message', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(null);
    await expect(service.remove('me', 'm1')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('403s a non-sender', async () => {
    const { service, messageRepository } = build();
    messageRepository.findById.mockResolvedValue(message({ senderId: 'peer' }));
    await expect(service.remove('me', 'm1')).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('soft-deletes and broadcasts chat.messageDeleted to both parties', async () => {
    const { service, messageRepository, realtime } = build();
    messageRepository.findById.mockResolvedValue(message({ senderId: 'me' }));
    await service.remove('me', 'm1');
    expect(messageRepository.softDelete).toHaveBeenCalledWith(
      'm1',
      expect.any(Date),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'peer',
      'chat.messageDeleted',
      expect.objectContaining({ id: 'm1', roomId: 'r1' }),
    );
    expect(realtime.emitToUser).toHaveBeenCalledWith(
      'me',
      'chat.messageDeleted',
      expect.objectContaining({ id: 'm1' }),
    );
  });
});

describe('MessagesService.list', () => {
  it('403s a non-participant', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.findById.mockResolvedValue(
      room({ user1Id: 'x', user2Id: 'y' }),
    );
    await expect(service.list('me', query())).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('maps a page oldest-first for the client despite the DB returning it newest-first (offset mode)', async () => {
    const { service, messageRepository } = build();
    // The repository queries `createdAt desc` (newest first) to grab "the
    // last N" — the service must reverse that to oldest-first before it
    // reaches the wire, since the client renders index 0 as the top of the
    // list with no client-side sort/reverse of its own.
    messageRepository.listPaged.mockResolvedValue([
      [
        message({
          id: 'b',
          senderId: 'peer',
          type: 'IMAGE',
          mediaUrl: 'chat-media/k',
        }),
        message({ id: 'a', senderId: 'me' }),
      ],
      2,
    ]);

    const page = await service.list('me', query());

    expect(messageRepository.listByCursor).not.toHaveBeenCalled();
    expect(page).toMatchObject({
      page: 1,
      limit: 30,
      total: 2,
      hasMore: false,
      nextCursor: null,
    });
    expect(page.items[0]).toMatchObject({
      id: 'a',
      isMine: true,
    });
    expect(page.items[1]).toMatchObject({
      id: 'b',
      isMine: false,
      mediaUrl: 'https://signed/x',
    });
  });

  it('uses keyset mode, echoes nextCursor, and reverses the DB order to oldest-first', async () => {
    const { service, messageRepository } = build();
    messageRepository.listByCursor.mockResolvedValue({
      items: [
        message({
          id: 'b',
          senderId: 'peer',
          createdAt: new Date('2026-01-02T00:00:00.000Z'),
        }),
        message({
          id: 'a',
          senderId: 'me',
          createdAt: new Date('2026-01-01T00:00:00.000Z'),
        }),
      ],
      hasMore: true,
      nextCursor: 'a',
    });

    const page = await service.list('me', query({ cursor: 'z' }));

    expect(messageRepository.listByCursor).toHaveBeenCalledWith('r1', 'z', 30);
    expect(messageRepository.listPaged).not.toHaveBeenCalled();
    expect(page).toMatchObject({ hasMore: true, nextCursor: 'a' });
    expect(page.items.map((i) => i.id)).toEqual(['a', 'b']);
  });

  it('treats an empty cursor as the first keyset page (null cursorId)', async () => {
    const { service, messageRepository } = build();
    messageRepository.listByCursor.mockResolvedValue({
      items: [],
      hasMore: false,
      nextCursor: null,
    });

    await service.list('me', query({ cursor: '' }));

    expect(messageRepository.listByCursor).toHaveBeenCalledWith('r1', null, 30);
  });
});
