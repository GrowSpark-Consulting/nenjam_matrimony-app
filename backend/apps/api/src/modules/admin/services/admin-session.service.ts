import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import {
  ADMIN_SESSION_IDLE_MS,
  ADMIN_SESSION_MAX_AGE_MS,
  ADMIN_SESSION_TOUCH_INTERVAL_MS,
} from '../auth/admin-auth.policy';
import type { AdminRequestContext } from '../auth/admin-request';
import { hashOpaqueToken, newOpaqueToken } from '../auth/secret-box';

export interface IssuedAdminSession {
  /** Shown once; only its hash is stored. Sent back as X-Admin-Session. */
  sessionToken: string;
  expiresAt: Date;
  idleTimeoutSeconds: number;
}

export interface AdminSessionRow {
  id: string;
  adminAccountId: string;
  lastSeenAt: Date;
  expiresAt: Date;
  mfaVerifiedAt: Date;
  revokedAt: Date | null;
}

export type SessionState =
  | { ok: true; session: AdminSessionRow }
  | { ok: false; reason: 'UNKNOWN' | 'REVOKED' | 'EXPIRED' | 'IDLE' };

/**
 * Whether a stored session still stands for [adminAccountId] at [now]. A
 * session presented with another admin's Firebase token is UNKNOWN — the two
 * factors must belong to the same person.
 */
export function decideSessionState(
  session: AdminSessionRow | null,
  adminAccountId: string,
  now: Date,
): SessionState {
  if (!session || session.adminAccountId !== adminAccountId) {
    return { ok: false, reason: 'UNKNOWN' };
  }
  if (session.revokedAt) return { ok: false, reason: 'REVOKED' };
  if (session.expiresAt.getTime() <= now.getTime()) {
    return { ok: false, reason: 'EXPIRED' };
  }
  if (now.getTime() - session.lastSeenAt.getTime() > ADMIN_SESSION_IDLE_MS) {
    return { ok: false, reason: 'IDLE' };
  }
  return { ok: true, session };
}

const SESSION_SELECT = {
  id: true,
  adminAccountId: true,
  lastSeenAt: true,
  expiresAt: true,
  mfaVerifiedAt: true,
  revokedAt: true,
} as const;

@Injectable()
export class AdminSessionService {
  constructor(private readonly prisma: PrismaService) {}

  /** Issued only after a successful authenticator check, in that check's
   *  transaction. */
  async create(
    tx: Pick<Prisma.TransactionClient, 'adminSession'>,
    adminAccountId: string,
    context: AdminRequestContext,
    now: Date,
  ): Promise<IssuedAdminSession & { sessionId: string }> {
    const sessionToken = newOpaqueToken();
    const expiresAt = new Date(now.getTime() + ADMIN_SESSION_MAX_AGE_MS);
    const created = await tx.adminSession.create({
      data: {
        adminAccountId,
        tokenHash: hashOpaqueToken(sessionToken),
        createdAt: now,
        lastSeenAt: now,
        expiresAt,
        mfaVerifiedAt: now,
        ipAddress: context.ipAddress ?? null,
        userAgent: context.userAgent ?? null,
      },
      select: { id: true },
    });
    return {
      sessionId: created.id,
      sessionToken,
      expiresAt,
      idleTimeoutSeconds: ADMIN_SESSION_IDLE_MS / 1000,
    };
  }

  async validate(
    token: string,
    adminAccountId: string,
    now: Date,
  ): Promise<SessionState> {
    const session = await this.prisma.adminSession.findUnique({
      where: { tokenHash: hashOpaqueToken(token) },
      select: SESSION_SELECT,
    });
    return decideSessionState(session, adminAccountId, now);
  }

  /** Keeps an active session from idling out. Best effort and rate limited:
   *  one write a minute, never on a revoked session. */
  async touch(session: AdminSessionRow, now: Date): Promise<void> {
    if (
      now.getTime() - session.lastSeenAt.getTime() <
      ADMIN_SESSION_TOUCH_INTERVAL_MS
    ) {
      return;
    }
    await this.prisma.adminSession
      .updateMany({
        where: { id: session.id, revokedAt: null },
        data: { lastSeenAt: now },
      })
      .catch(() => undefined);
  }

  /** Records a fresh authenticator check (step-up) on [sessionId]. */
  async markVerified(
    tx: Pick<Prisma.TransactionClient, 'adminSession'>,
    sessionId: string,
    now: Date,
  ): Promise<void> {
    await tx.adminSession.update({
      where: { id: sessionId },
      data: { mfaVerifiedAt: now, lastSeenAt: now },
    });
  }

  async revoke(
    tx: Pick<Prisma.TransactionClient, 'adminSession'>,
    sessionId: string,
    reason: string,
    now: Date,
  ): Promise<void> {
    await tx.adminSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { revokedAt: now, revokeReason: reason },
    });
  }
}

/**
 * Ends every live session of an admin — on deactivation, an authenticator
 * reset or a role removal. Exported as a function so the provisioning script
 * can use it without a Nest container.
 */
export async function revokeAllAdminSessions(
  tx: Pick<Prisma.TransactionClient, 'adminSession'>,
  adminAccountId: string,
  reason: string,
  now: Date,
): Promise<number> {
  const { count } = await tx.adminSession.updateMany({
    where: { adminAccountId, revokedAt: null },
    data: { revokedAt: now, revokeReason: reason },
  });
  return count;
}
