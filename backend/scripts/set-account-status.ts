/**
 * Suspend, ban, deactivate or restore a member — and make it take effect now.
 *
 *   pnpm account:status <email | phone | userId> <STATUS>
 *   pnpm account:status abuse@example.com BANNED
 *   pnpm account:status +919876543210 ACTIVE
 *
 * Why this exists rather than an UPDATE in a SQL console: the auth guard caches
 * each account's status in Redis, so a status changed behind the API's back
 * keeps working until that entry expires. This writes the row AND drops the
 * cache entry, so the very next request is refused. It is the supported way to
 * action a report until an admin surface exists.
 *
 * What a ban stops, and when:
 *   - HTTP requests            — immediately (FirebaseAuthGuard returns 403)
 *   - an open WebSocket        — within one presence heartbeat (~25s), when the
 *                                gateway re-checks and disconnects it
 *   - already-issued push/mail — not at all; those are already sent
 *
 * This does not touch Firebase. The member's ID token stays cryptographically
 * valid until it expires; the API refuses it regardless, which is the point.
 */
import { config } from 'dotenv';
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { Logger, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppConfigModule } from '@app/config';
import { PrismaModule, PrismaService } from '@app/database';
import { RedisModule, RedisService } from '@app/cache';
import { invalidateCachedUserId } from '@app/common';

@Module({ imports: [AppConfigModule, PrismaModule, RedisModule] })
class AccountStatusModule {}

/** Mirrors the `UserStatus` enum in schema.prisma. */
const STATUSES = [
  'PENDING_VERIFICATION',
  'ACTIVE',
  'SUSPENDED',
  'DEACTIVATED',
  'BANNED',
] as const;
type Status = (typeof STATUSES)[number];

function isStatus(value: string): value is Status {
  return (STATUSES as readonly string[]).includes(value);
}

function usage(message: string): never {
  console.error(
    `${message}\n\n` +
      '  Usage: pnpm account:status <email | phone | userId> <STATUS>\n' +
      `  STATUS: ${STATUSES.join(' | ')}\n`,
  );
  process.exit(1);
}

async function main(): Promise<void> {
  const [identifier, requested] = process.argv.slice(2);
  if (!identifier || !requested) usage('Both arguments are required.');

  const status = requested.toUpperCase();
  if (!isStatus(status)) usage(`Unknown status "${requested}".`);

  Logger.overrideLogger(['error']);
  const app = await NestFactory.createApplicationContext(AccountStatusModule, {
    logger: ['error'],
  });

  try {
    const prisma = app.get(PrismaService);
    const redis = app.get(RedisService);

    // One lookup covering all three ways a support request might identify
    // someone. `id` is a uuid, so a stray email can never collide with it.
    const user = await prisma.user.findFirst({
      where: {
        OR: [{ id: identifier }, { email: identifier }, { phone: identifier }],
      },
      select: {
        id: true,
        email: true,
        phone: true,
        status: true,
        firebaseUid: true,
        deletedAt: true,
      },
    });

    if (!user) {
      console.error(`No account matches "${identifier}".`);
      process.exit(1);
    }

    if (user.deletedAt) {
      console.error(
        `Account ${user.id} is already deleted (${user.deletedAt.toISOString()}); ` +
          'status changes on a deleted account have no effect.',
      );
      process.exit(1);
    }

    if (user.status === status) {
      console.log(`Account ${user.id} is already ${status}. Nothing to do.`);
      // Still drop the cache: the point of running this is that the live
      // system should agree with the database, and it may not.
      await invalidateCachedUserId(redis, user.firebaseUid);
      console.log('Auth cache entry dropped anyway.');
      return;
    }

    const previous = user.status;
    await prisma.user.update({ where: { id: user.id }, data: { status } });
    await invalidateCachedUserId(redis, user.firebaseUid);

    console.log(
      [
        '',
        `  account   : ${user.id}`,
        `  email     : ${user.email}`,
        `  phone     : ${user.phone ?? '—'}`,
        `  status    : ${previous} -> ${status}`,
        '  auth cache: dropped (next request re-reads the database)',
        '',
        status === 'ACTIVE' || status === 'PENDING_VERIFICATION'
          ? '  The member can use the API again immediately.'
          : '  HTTP is refused immediately; any open socket drops within ~25s.',
        '',
      ].join('\n'),
    );
  } finally {
    await app.close();
  }
}

void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
