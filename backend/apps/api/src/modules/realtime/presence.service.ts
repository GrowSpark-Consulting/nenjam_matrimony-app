import { Injectable, Logger } from '@nestjs/common';
import { RedisService } from '@app/cache';

/**
 * Cross-instance presence. A user is "online" while at least one of their
 * devices has sent a heartbeat within {@link STALE_AFTER_MS}. Each device is a
 * member of a per-user Redis sorted set scored by its last-heartbeat epoch-ms;
 * that makes presence:
 *
 *  - **multi-device** — one member per socket, online == the set is non-empty;
 *  - **self-healing** — every read/write first drops members whose score is
 *    older than the stale window (`ZREMRANGEBYSCORE`), so a device that
 *    disconnected without a clean `onDisconnect` (crash, network drop) ages out
 *    on its own; the whole key also carries a TTL so a fully-dead user's key
 *    can't leak;
 *  - **shared across API instances** — the ZSET lives in Redis, so the delivery
 *    decision (`deliveredNow`) and last-seen are correct no matter which
 *    instance the sender and recipient sockets landed on.
 *
 * Redis is a soft dependency here exactly as it is elsewhere (see
 * auth-user-cache): when it isn't `ready` every method transparently falls back
 * to an in-process mirror with identical semantics, so a single-instance
 * deployment (or local dev without Redis) still has correct presence — it just
 * isn't shared across instances. All Redis calls are wrapped so a transient
 * Redis error degrades to the in-memory answer rather than throwing onto a
 * socket lifecycle or a message send.
 */

// Client heartbeat cadence (documented for the socket handler / client).
export const HEARTBEAT_INTERVAL_MS = 25_000;
// A device with no heartbeat within this window is considered gone (~2.4x the
// heartbeat, so a single dropped ping doesn't flap a user offline).
export const STALE_AFTER_MS = 60_000;
// Whole-key TTL guarding against a leaked set if a process dies mid-flight.
const KEY_TTL_MS = STALE_AFTER_MS * 3;
// last-seen retention.
const LAST_SEEN_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days

export interface PresenceInfo {
  online: boolean;
  lastSeenAt: Date | null;
}

@Injectable()
export class PresenceService {
  private readonly logger = new Logger(PresenceService.name);

  // In-memory mirror used whenever Redis isn't ready: userId → (deviceKey →
  // last-heartbeat epoch ms), plus a userId → lastSeen epoch ms map.
  private readonly memDevices = new Map<string, Map<string, number>>();
  private readonly memLastSeen = new Map<string, number>();

  constructor(private readonly redis: RedisService) {}

  private key(userId: string): string {
    return `presence:${userId}`;
  }

  private lastSeenKey(userId: string): string {
    return `presence:lastseen:${userId}`;
  }

  /** Redis client only when it's actually usable; null → use the memory mirror. */
  private readyClient(): ReturnType<RedisService['getClient']> | null {
    try {
      const client = this.redis.getClient();
      return client.status === 'ready' ? client : null;
    } catch {
      return null;
    }
  }

  /** Records a device as present (on connect or heartbeat) and prunes stale
   *  members. Idempotent — re-recording the same device just refreshes its
   *  score. */
  async touch(userId: string, deviceKey: string): Promise<void> {
    const now = Date.now();
    const client = this.readyClient();
    if (!client) {
      const devices = this.memDevices.get(userId) ?? new Map<string, number>();
      devices.set(deviceKey, now);
      this.pruneMem(devices, now);
      this.memDevices.set(userId, devices);
      return;
    }
    try {
      const key = this.key(userId);
      await client
        .multi()
        .zadd(key, now, deviceKey)
        .zremrangebyscore(key, 0, now - STALE_AFTER_MS)
        .pexpire(key, KEY_TTL_MS)
        .exec();
    } catch (error) {
      this.logger.warn(`presence touch fell back to memory: ${asMsg(error)}`);
      const devices = this.memDevices.get(userId) ?? new Map<string, number>();
      devices.set(deviceKey, now);
      this.memDevices.set(userId, devices);
    }
  }

  /** Removes a device (clean disconnect). When it was the user's last device,
   *  stamps last-seen to now. */
  async remove(userId: string, deviceKey: string): Promise<void> {
    const now = Date.now();
    const client = this.readyClient();
    if (!client) {
      const devices = this.memDevices.get(userId);
      if (devices) {
        devices.delete(deviceKey);
        this.pruneMem(devices, now);
        if (devices.size === 0) {
          this.memDevices.delete(userId);
          this.memLastSeen.set(userId, now);
        }
      }
      return;
    }
    try {
      const key = this.key(userId);
      await client.zrem(key, deviceKey);
      await client.zremrangebyscore(key, 0, now - STALE_AFTER_MS);
      const remaining = await client.zcard(key);
      if (remaining === 0) {
        await client.set(
          this.lastSeenKey(userId),
          String(now),
          'EX',
          LAST_SEEN_TTL_SECONDS,
        );
      }
    } catch (error) {
      this.logger.warn(`presence remove fell back to memory: ${asMsg(error)}`);
    }
  }

  /** True when the user has at least one non-stale device. Prunes on read so a
   *  crashed device never keeps a user falsely "online". */
  async isOnline(userId: string): Promise<boolean> {
    const now = Date.now();
    const client = this.readyClient();
    if (!client) {
      const devices = this.memDevices.get(userId);
      if (!devices) return false;
      this.pruneMem(devices, now);
      if (devices.size === 0) this.memDevices.delete(userId);
      return devices.size > 0;
    }
    try {
      const key = this.key(userId);
      await client.zremrangebyscore(key, 0, now - STALE_AFTER_MS);
      const count = await client.zcard(key);
      return count > 0;
    } catch (error) {
      this.logger.warn(
        `presence isOnline fell back to memory: ${asMsg(error)}`,
      );
      const devices = this.memDevices.get(userId);
      return !!devices && devices.size > 0;
    }
  }

  /** Online flag + last-seen for one user. Online users report `lastSeenAt` as
   *  now; offline users report their stored last-seen (or null if unknown). */
  async presenceOf(userId: string): Promise<PresenceInfo> {
    const online = await this.isOnline(userId);
    if (online) return { online: true, lastSeenAt: new Date() };
    const client = this.readyClient();
    if (!client) {
      const ms = this.memLastSeen.get(userId);
      return { online: false, lastSeenAt: ms ? new Date(ms) : null };
    }
    try {
      const raw = await client.get(this.lastSeenKey(userId));
      const ms = raw ? Number(raw) : NaN;
      return {
        online: false,
        lastSeenAt: Number.isFinite(ms) ? new Date(ms) : null,
      };
    } catch (error) {
      this.logger.warn(
        `presence lastSeen fell back to memory: ${asMsg(error)}`,
      );
      const ms = this.memLastSeen.get(userId);
      return { online: false, lastSeenAt: ms ? new Date(ms) : null };
    }
  }

  private pruneMem(devices: Map<string, number>, now: number): void {
    const cutoff = now - STALE_AFTER_MS;
    for (const [dev, ts] of devices) {
      if (ts <= cutoff) devices.delete(dev);
    }
  }
}

function asMsg(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
