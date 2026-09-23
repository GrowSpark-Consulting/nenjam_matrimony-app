import type { Socket } from 'socket.io';
import type { FirebaseService } from '@app/firebase';
import type { PrismaService } from '@app/database';
import type { RedisService } from '@app/cache';
import { RealtimeGateway } from '../realtime.gateway';
import type { PresenceService } from '../presence.service';
import type { ActiveConversationService } from '../active-conversation.service';

/**
 * A socket is authenticated once, at handshake. Without a re-check, a member
 * banned mid-session kept a live connection — still receiving chat messages and
 * notification events — until they happened to disconnect. The presence
 * heartbeat the client already sends every ~25s is where that is caught.
 */
function build({
  status = 'ACTIVE',
  deletedAt = null as Date | null,
  withUid = true,
} = {}) {
  const findUnique = jest
    .fn()
    .mockResolvedValue({ id: 'u1', status, deletedAt });
  const prisma = {
    user: { findUnique },
    chatRoom: { findMany: jest.fn().mockResolvedValue([]) },
  } as unknown as PrismaService;

  // Empty store: every check falls through to the database, which is the
  // worst case for cost and the clearest case to assert on.
  const redis = {
    getClient: () => ({
      status: 'ready',
      get: () => Promise.resolve(null),
      set: () => Promise.resolve('OK'),
      del: () => Promise.resolve(1),
    }),
  } as unknown as RedisService;

  const presence = {
    isOnline: jest.fn().mockResolvedValue(true),
    touch: jest.fn().mockResolvedValue(undefined),
    remove: jest.fn().mockResolvedValue(undefined),
    removeAll: jest.fn().mockResolvedValue(undefined),
  };
  const activeConversation = {
    refresh: jest.fn().mockResolvedValue(undefined),
    leave: jest.fn().mockResolvedValue(undefined),
    clearUser: jest.fn().mockResolvedValue(undefined),
  };

  const gateway = new RealtimeGateway(
    {} as FirebaseService,
    prisma,
    redis,
    presence as unknown as PresenceService,
    activeConversation as unknown as ActiveConversationService,
  );
  (gateway as unknown as { server: unknown }).server = {
    to: () => ({ emit: jest.fn() }),
  };

  const emit = jest.fn();
  const disconnect = jest.fn();
  const client = {
    id: 'socket-1',
    data: { userId: 'u1', ...(withUid ? { firebaseUid: 'uid-1' } : {}) },
    emit,
    disconnect,
  } as unknown as Socket;

  return {
    gateway,
    client,
    emit,
    disconnect,
    presence,
    activeConversation,
    findUnique,
  };
}

describe('RealtimeGateway — a heartbeat re-checks the account', () => {
  it.each(['BANNED', 'SUSPENDED', 'DEACTIVATED'])(
    'disconnects a socket whose account became %s after it connected',
    async (status) => {
      const {
        gateway,
        client,
        emit,
        disconnect,
        presence,
        activeConversation,
      } = build({ status });

      await gateway.handlePresencePing(client);

      expect(disconnect).toHaveBeenCalledWith(true);
      expect(emit).toHaveBeenCalledWith('unauthorized', {
        reason: 'Account is no longer active.',
      });
      // Their devices must stop counting as online, or peers keep seeing a
      // banned member as present.
      expect(presence.removeAll).toHaveBeenCalledWith('u1');
      expect(activeConversation.leave).toHaveBeenCalledWith('u1', 'socket-1');
      // And the heartbeat itself does not proceed.
      expect(presence.touch).not.toHaveBeenCalled();
      expect(emit).not.toHaveBeenCalledWith('presence.pong', expect.anything());
    },
  );

  it('disconnects a socket whose account was soft-deleted', async () => {
    const { gateway, client, disconnect } = build({ deletedAt: new Date() });
    await gateway.handlePresencePing(client);
    expect(disconnect).toHaveBeenCalledWith(true);
  });

  it('leaves a usable account alone', async () => {
    const { gateway, client, emit, disconnect, presence } = build({
      status: 'ACTIVE',
    });

    await gateway.handlePresencePing(client);

    expect(disconnect).not.toHaveBeenCalled();
    expect(presence.touch).toHaveBeenCalledWith('u1', 'socket-1');
    expect(emit).toHaveBeenCalledWith(
      'presence.pong',
      expect.objectContaining({ at: expect.any(Number) as number }),
    );
  });

  it('admits PENDING_VERIFICATION, the state most real members are in', async () => {
    const { gateway, client, disconnect } = build({
      status: 'PENDING_VERIFICATION',
    });
    await gateway.handlePresencePing(client);
    expect(disconnect).not.toHaveBeenCalled();
  });

  it('fails open for a socket that predates the recorded uid', async () => {
    // Mid-deploy: a socket authenticated by the previous build has no
    // firebaseUid on it. It keeps working until it reconnects, rather than
    // being disconnected for a reason that is not its fault.
    const { gateway, client, disconnect, findUnique } = build({
      status: 'BANNED',
      withUid: false,
    });

    await gateway.handlePresencePing(client);

    expect(disconnect).not.toHaveBeenCalled();
    expect(findUnique).not.toHaveBeenCalled();
  });

  it('ignores a heartbeat from a socket that never authenticated', async () => {
    const { gateway, findUnique } = build();
    const emit = jest.fn();
    const anonymous = {
      id: 'socket-2',
      data: {},
      emit,
      disconnect: jest.fn(),
    } as unknown as Socket;

    await gateway.handlePresencePing(anonymous);

    expect(emit).not.toHaveBeenCalled();
    expect(findUnique).not.toHaveBeenCalled();
  });
});
