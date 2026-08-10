import type { RedisService } from '@app/cache';
import { ActiveConversationService } from '../active-conversation.service';
import { STALE_AFTER_MS } from '../presence.service';

/**
 * Exercised against the in-memory fallback path: `getClient()` throws, which is
 * exactly what the service treats as "Redis not usable". That keeps the suite
 * fast and hermetic while covering the same branching logic the Redis path
 * uses — enter / leave / clear / staleness / per-device isolation.
 */
function build() {
  const redis = {
    getClient: () => {
      throw new Error('redis unavailable in test');
    },
  } as unknown as RedisService;
  return new ActiveConversationService(redis);
}

describe('ActiveConversationService', () => {
  const USER = 'user-a';
  const PEER = 'user-b';
  const CONV_A = 'conv-a';
  const CONV_B = 'conv-b';
  const DEVICE = 'socket-1';

  it('Test 5: entering a conversation registers it', async () => {
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);

    expect(await svc.isViewing(USER, CONV_A)).toBe(true);
  });

  it('Test 6: leaving clears it', async () => {
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);
    await svc.leave(USER, DEVICE);

    expect(await svc.isViewing(USER, CONV_A)).toBe(false);
  });

  it('Test 7: switching A -> B stops suppressing A and starts suppressing B', async () => {
    // The regression this guards: one entry PER DEVICE, so the previous
    // conversation cannot linger and keep swallowing its pushes.
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);
    await svc.enter(USER, DEVICE, CONV_B);

    expect(await svc.isViewing(USER, CONV_A)).toBe(false);
    expect(await svc.isViewing(USER, CONV_B)).toBe(true);
  });

  it('Test 8: a disconnect clears the entry, so future messages notify', async () => {
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);
    // What RealtimeGateway.handleDisconnect calls.
    await svc.leave(USER, DEVICE);

    expect(await svc.isViewing(USER, CONV_A)).toBe(false);
  });

  it('Test 10: both members viewing each other suppresses for both', async () => {
    const svc = build();
    await svc.enter(USER, 'socket-a', CONV_A);
    await svc.enter(PEER, 'socket-b', CONV_A);

    expect(await svc.isViewing(USER, CONV_A)).toBe(true);
    expect(await svc.isViewing(PEER, CONV_A)).toBe(true);
  });

  it('never reports viewing a conversation the member has not opened', async () => {
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);

    expect(await svc.isViewing(USER, CONV_B)).toBe(false);
  });

  it('reports nothing for a member with no state at all', async () => {
    const svc = build();
    expect(await svc.isViewing('nobody', CONV_A)).toBe(false);
  });

  it('an entry older than the stale window stops suppressing', async () => {
    // The safety valve: a client that crashed or lost network inside a chat
    // must resume receiving pushes on its own, with no cleanup event.
    jest.useFakeTimers();
    try {
      const svc = build();
      await svc.enter(USER, DEVICE, CONV_A);
      expect(await svc.isViewing(USER, CONV_A)).toBe(true);

      jest.advanceTimersByTime(STALE_AFTER_MS + 1_000);
      expect(await svc.isViewing(USER, CONV_A)).toBe(false);
    } finally {
      jest.useRealTimers();
    }
  });

  it('the heartbeat refresh keeps a live entry from ageing out', async () => {
    jest.useFakeTimers();
    try {
      const svc = build();
      await svc.enter(USER, DEVICE, CONV_A);

      // Two ticks just under the window, each refreshed — as presence.ping does.
      for (let i = 0; i < 2; i++) {
        jest.advanceTimersByTime(STALE_AFTER_MS - 5_000);
        await svc.refresh(USER, DEVICE);
      }

      expect(await svc.isViewing(USER, CONV_A)).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });

  it('refresh is a no-op for a device with no entry', async () => {
    const svc = build();
    await svc.refresh(USER, DEVICE);

    expect(await svc.isViewing(USER, CONV_A)).toBe(false);
  });

  it('clearUser drops every device (backgrounding)', async () => {
    const svc = build();
    await svc.enter(USER, 'socket-1', CONV_A);
    await svc.enter(USER, 'socket-2', CONV_B);

    await svc.clearUser(USER);

    expect(await svc.isViewing(USER, CONV_A)).toBe(false);
    expect(await svc.isViewing(USER, CONV_B)).toBe(false);
  });

  it('one device leaving does not clear another device of the same member', async () => {
    const svc = build();
    await svc.enter(USER, 'phone', CONV_A);
    await svc.enter(USER, 'laptop', CONV_A);

    await svc.leave(USER, 'phone');

    // Documented limitation: the decision is user-level, so as long as ANY
    // device still has the thread open, the push stays suppressed.
    expect(await svc.isViewing(USER, CONV_A)).toBe(true);
  });

  it('members are isolated from one another', async () => {
    const svc = build();
    await svc.enter(USER, DEVICE, CONV_A);

    expect(await svc.isViewing(PEER, CONV_A)).toBe(false);
  });
});
