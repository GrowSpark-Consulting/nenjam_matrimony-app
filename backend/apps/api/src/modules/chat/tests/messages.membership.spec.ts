import { ForbiddenException } from '@nestjs/common';
import type { MembershipEnforcementMode } from '@app/config';
import { MessagesService } from '../services/messages.service';
import {
  inForce,
  membershipWithPlans,
} from '../../entitlements/tests/catalog-fixtures';

// Who may START a conversation (chat.initiate: Gold/Platinum), and the free
// paths around it: replying (chat.reply, every plan) and writing to a
// Platinum member who lets free members contact them. The interest/block
// eligibility check is mocked to pass — membership never replaces it.

const ROOM = 'room-1';

function build(
  mode: MembershipEnforcementMode,
  members: Parameters<typeof membershipWithPlans>[1],
  peerHasWritten: boolean,
) {
  const room = {
    id: ROOM,
    user1Id: 'sender',
    user2Id: 'receiver',
    isActive: true,
  };
  const conversationRepository = {
    findById: jest.fn().mockResolvedValue(room),
    hasAcceptedInterest: jest.fn().mockResolvedValue(true),
    isBlockedBetween: jest.fn().mockResolvedValue(false),
  };
  const created = {
    id: 'msg-1',
    roomId: ROOM,
    senderId: 'sender',
    content: 'hello',
    type: 'TEXT',
    status: 'SENT',
    createdAt: new Date(),
    editedAt: null,
    deletedAt: null,
    replyTo: null,
  };
  const messageRepository = {
    hasMessageFrom: jest.fn().mockResolvedValue(peerHasWritten),
    findByClientKey: jest.fn().mockResolvedValue(null),
    create: jest.fn().mockResolvedValue(created),
    touchRoomActivity: jest.fn().mockResolvedValue(undefined),
  };
  const service = new MessagesService(
    {
      $transaction: jest.fn((cb: (tx: unknown) => unknown) => cb({})),
    } as never,
    conversationRepository as never,
    messageRepository as never,
    { getPresignedGetUrl: jest.fn() } as never,
    { emitToUser: jest.fn() } as never,
    { isOnline: jest.fn().mockResolvedValue(false) } as never,
    { record: jest.fn(), recordDenied: jest.fn() } as never,
    {
      create: jest.fn().mockResolvedValue({}),
      invalidateUnread: jest.fn().mockResolvedValue(undefined),
      dispatchPush: jest.fn().mockResolvedValue(undefined),
      resolveDisplayName: jest.fn().mockResolvedValue('Asha'),
    } as never,
    { sendNewMessage: jest.fn().mockResolvedValue(undefined) } as never,
    { isViewing: jest.fn().mockResolvedValue(false) } as never,
    membershipWithPlans(mode, members).service,
  );
  const send = () => service.send('sender', { roomId: ROOM, content: 'hello' });
  return { send, messageRepository };
}

describe('MessagesService.send — who may start a conversation', () => {
  it('refuses a Free member starting a conversation, writing nothing', async () => {
    const { send, messageRepository } = build('enforce', {}, false);
    const error = await send().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ForbiddenException);
    expect((error as ForbiddenException).getResponse()).toMatchObject({
      code: 'MEMBERSHIP_FEATURE_UNAVAILABLE',
      feature: 'chat.initiate',
    });
    expect(messageRepository.create).not.toHaveBeenCalled();
  });

  it('lets a Free member reply once the other member has written', async () => {
    const { send, messageRepository } = build('enforce', {}, true);
    await send();
    expect(messageRepository.create).toHaveBeenCalled();
  });

  it('lets a Free member write first to a Platinum member who accepts free members', async () => {
    const { send, messageRepository } = build(
      'enforce',
      { receiver: [inForce('PLATINUM')] },
      false,
    );
    await send();
    expect(messageRepository.create).toHaveBeenCalled();
  });

  it('does not open that door to Gold members (accept-from-free is Platinum only)', async () => {
    const { send } = build('enforce', { receiver: [inForce('GOLD')] }, false);
    await expect(send()).rejects.toBeInstanceOf(ForbiddenException);
  });

  it.each(['GOLD', 'PLATINUM'] as const)(
    'lets a %s member start a conversation',
    async (plan) => {
      const { send, messageRepository } = build(
        'enforce',
        { sender: [inForce(plan)] },
        false,
      );
      await send();
      expect(messageRepository.create).toHaveBeenCalled();
      // A paid sender costs one membership lookup and nothing else.
      expect(messageRepository.hasMessageFrom).not.toHaveBeenCalled();
    },
  );

  it.each(['shadow', 'off'] as const)(
    'never blocks under %s — today’s behaviour',
    async (mode) => {
      const { send, messageRepository } = build(mode, {}, false);
      await send();
      expect(messageRepository.create).toHaveBeenCalled();
    },
  );
});
