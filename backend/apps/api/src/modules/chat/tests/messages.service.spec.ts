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
    isRead: false,
    readAt: null,
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
    listPaged: jest.fn(),
  };
  const s3 = {
    isConfigured: jest.fn().mockReturnValue(true),
    getPresignedGetUrl: jest.fn().mockResolvedValue('https://signed/x'),
  };
  const realtime = { emitToUser: jest.fn() };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };
  const service = new MessagesService(
    prisma as never,
    conversationRepository as never,
    messageRepository as never,
    s3 as never,
    realtime as never,
  );
  return { service, conversationRepository, messageRepository, s3, realtime };
}

const PAGE = { skip: 0, take: 30, pageNumber: 1 } as never;

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
});

describe('MessagesService.list', () => {
  it('403s a non-participant', async () => {
    const { service, conversationRepository } = build();
    conversationRepository.findById.mockResolvedValue(
      room({ user1Id: 'x', user2Id: 'y' }),
    );
    await expect(service.list('me', 'r1', PAGE)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it('maps a page newest-first with isMine + presigned media', async () => {
    const { service, messageRepository } = build();
    messageRepository.listPaged.mockResolvedValue([
      [
        message({ id: 'a', senderId: 'me' }),
        message({
          id: 'b',
          senderId: 'peer',
          type: 'IMAGE',
          mediaUrl: 'chat-media/k',
        }),
      ],
      2,
    ]);

    const page = await service.list('me', 'r1', PAGE);

    expect(page).toMatchObject({
      page: 1,
      limit: 30,
      total: 2,
      hasMore: false,
    });
    expect(page.items[0]).toMatchObject({ id: 'a', isMine: true });
    expect(page.items[1]).toMatchObject({
      id: 'b',
      isMine: false,
      mediaUrl: 'https://signed/x',
    });
  });
});
