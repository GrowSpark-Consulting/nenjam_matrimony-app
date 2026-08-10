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
    // Added with the reply-to-message feature; required on ChatMessage, so
    // the fixture must supply it or the returned object is not a ChatMessage.
    replyToMessageId: null,
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
    resolveDisplayName: jest.fn().mockResolvedValue('Asha Patel'),
  };
  const prisma = {
    $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
  };
  const emailDispatch = {
    sendNewMessage: jest.fn().mockResolvedValue(undefined),
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
    emailDispatch as never,
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
    emailDispatch,
  };
}

/** The chat push is dispatched fire-and-forget, after an awaited display-name
 *  lookup — so it lands a few microtasks after `send()` resolves. Flush the
 *  queue before asserting on it. */
const flushPending = () =>
  new Promise<void>((resolve) => setImmediate(resolve));

interface PushOverride {
  title: string;
  body: string;
  data: Record<string, string>;
}

/** The `override` block of the nth `dispatchPush` call, typed — the raw
 *  `mock.calls` entry is `any`. */
function pushOverride(dispatchPush: jest.Mock, index = 0): PushOverride {
  const calls = dispatchPush.mock.calls as unknown as Array<
    [unknown, { override: PushOverride }]
  >;
  return calls[index][1].override;
}

interface StoredNotification {
  userId: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

/** The notification row handed to `notifications.create` on the nth call,
 *  typed — same `any` problem as {@link pushOverride}. */
function storedNotification(create: jest.Mock, index = 0): StoredNotification {
  const calls = create.mock.calls as unknown as Array<
    [unknown, StoredNotification]
  >;
  return calls[index][1];
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
    await flushPending();

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
      expect.objectContaining({ excludeUserId: 'me' }),
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
      expect.anything(),
    );
    expect(realtime.emitToUser).not.toHaveBeenCalledWith(
      'me',
      'notification.created',
      expect.anything(),
    );
  });

  it('stores the notification row with the sender name and message text', async () => {
    const { service, notifications } = build();
    await service.send('me', { roomId: 'r1', content: 'hi there' });

    expect(notifications.create).toHaveBeenCalledWith(expect.anything(), {
      userId: 'peer',
      type: 'NEW_MESSAGE',
      title: 'Asha Patel',
      body: 'hi there',
      data: { actorId: 'me', referenceId: 'r1' },
    });
  });

  it('stores the same title and body the push carries', async () => {
    const { service, notifications } = build();
    await service.send('me', { roomId: 'r1', content: 'hi there' });
    await flushPending();

    const stored = storedNotification(notifications.create);
    const pushed = pushOverride(notifications.dispatchPush);
    expect(stored.title).toBe(pushed.title);
    expect(stored.body).toBe(pushed.body);
  });

  it('truncates the stored notification body to 120 characters', async () => {
    const { service, notifications, messageRepository } = build();
    const long = 'a'.repeat(300);
    messageRepository.create.mockResolvedValue(message({ content: long }));

    await service.send('me', { roomId: 'r1', content: long });

    const { body } = storedNotification(notifications.create);
    expect(body).toHaveLength(120);
    expect(body.endsWith('…')).toBe(true);
  });

  it('stores a generic title, and still sends, when the name lookup fails', async () => {
    const { service, notifications } = build();
    notifications.resolveDisplayName.mockRejectedValue(new Error('db down'));

    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).resolves.toMatchObject({ id: 'm1' });

    expect(storedNotification(notifications.create).title).toBe('Nenjam');
  });

  it('pushes the sender name as title and the message as body, excluding the sender devices', async () => {
    const { service, notifications } = build();
    await service.send('me', { roomId: 'r1', content: 'hi there' });
    await flushPending();

    expect(notifications.resolveDisplayName).toHaveBeenCalledWith('me');
    expect(notifications.dispatchPush).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'peer' }),
      {
        excludeUserId: 'me',
        override: {
          title: 'Asha Patel',
          body: 'hi there',
          data: { type: 'chat', conversationId: 'r1', senderId: 'me' },
        },
      },
    );
  });

  it('truncates the push body to 120 characters, ellipsis included', async () => {
    const { service, notifications, messageRepository } = build();
    const long = 'a'.repeat(300);
    messageRepository.create.mockResolvedValue(message({ content: long }));

    await service.send('me', { roomId: 'r1', content: long });
    await flushPending();

    const { body } = pushOverride(notifications.dispatchPush);
    expect(body).toHaveLength(120);
    expect(body.endsWith('…')).toBe(true);
  });

  it('falls back to a generic push title when the sender has no display name', async () => {
    const { service, notifications } = build();
    notifications.resolveDisplayName.mockResolvedValue(null);

    await service.send('me', { roomId: 'r1', content: 'hi' });
    await flushPending();

    const { title } = pushOverride(notifications.dispatchPush);
    expect(title).toBe('Nenjam');
    // Must never collide with the stored notification row's generic title —
    // that ambiguity is what made the fallback undiagnosable on a device.
    expect(title).not.toBe('New message');
  });

  it('never previews media content in a push (the stored URL is a signed link)', async () => {
    const { service, notifications, messageRepository } = build();
    messageRepository.create.mockResolvedValue(
      message({ type: 'IMAGE', content: '', mediaUrl: 'chat/x.jpg' }),
    );

    await service.send('me', {
      roomId: 'r1',
      type: 'IMAGE',
      mediaUrl: 'chat/x.jpg',
    });
    await flushPending();

    expect(pushOverride(notifications.dispatchPush).body).toBe(
      'Sent you an attachment.',
    );
  });

  it('does not fail the send when the push dispatch throws', async () => {
    const { service, notifications } = build();
    notifications.dispatchPush.mockRejectedValue(new Error('FCM down'));

    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).resolves.toMatchObject({ id: 'm1' });
    await flushPending();
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

describe('MessagesService — email workflow', () => {
  it('emails the recipient when they were offline', async () => {
    const { service, presence, emailDispatch } = build();
    presence.isOnline.mockResolvedValue(false);

    await service.send('me', {
      roomId: 'r1',
      content: 'are you free to talk?',
    });

    expect(emailDispatch.sendNewMessage).toHaveBeenCalledWith(
      'peer',
      'me',
      'are you free to talk?',
      'r1',
    );
  });

  it('sends NO email when the recipient is online', async () => {
    // They already got the real-time event; mail would just be noise.
    const { service, presence, emailDispatch } = build();
    presence.isOnline.mockResolvedValue(true);

    await service.send('me', { roomId: 'r1', content: 'hi' });

    expect(emailDispatch.sendNewMessage).not.toHaveBeenCalled();
  });

  it('never puts a media message body in the email preview', async () => {
    // Media content is a signed S3 URL that expires long before the email is
    // read — leaking it would also bypass the access check on re-fetch.
    const { service, presence, emailDispatch } = build();
    presence.isOnline.mockResolvedValue(false);

    await service.send('me', {
      roomId: 'r1',
      type: 'IMAGE',
      mediaUrl: 'https://s3.example.com/chat/r1/secret.jpg?X-Amz-Signature=abc',
    } as never);

    const call = emailDispatch.sendNewMessage.mock.calls[0] as unknown[];
    const preview = call[2] as string;
    expect(preview).toBe('Sent you an attachment.');
    expect(preview).not.toContain('secret.jpg');
  });

  it('still delivers the message when queuing the email fails', async () => {
    const { service, presence, emailDispatch } = build();
    presence.isOnline.mockResolvedValue(false);
    emailDispatch.sendNewMessage.mockRejectedValue(new Error('redis down'));

    await expect(
      service.send('me', { roomId: 'r1', content: 'hi' }),
    ).resolves.toBeDefined();
  });
});
