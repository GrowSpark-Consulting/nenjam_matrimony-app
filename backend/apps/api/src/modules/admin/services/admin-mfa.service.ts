import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { AppConfigService } from '@app/config';
import { PrismaService } from '@app/database';
import {
  ADMIN_MFA_LOCK_MS,
  ADMIN_MFA_MAX_FAILURES,
  ADMIN_STEP_UP_MS,
  adminForbidden,
  adminLocked,
  adminUnauthorized,
} from '../auth/admin-auth.policy';
import type {
  AdminRequestContext,
  AuthenticatedAdmin,
} from '../auth/admin-request';
import {
  hashEnrollmentCode,
  open,
  parseSecretKey,
  seal,
} from '../auth/secret-box';
import { generateTotpSecret, matchTotp, otpauthUri } from '../auth/totp';
import { AdminAccessService, type StaffAccount } from './admin-access.service';
import { AdminAuditService } from './admin-audit.service';
import {
  AdminSessionService,
  type IssuedAdminSession,
} from './admin-session.service';

const ISSUER = 'Nenjam Admin';

interface MfaAccount {
  id: string;
  mfaSecretEncrypted: string | null;
  mfaEnrolledAt: Date | null;
  mfaLastUsedStep: number | null;
  mfaLockedUntil: Date | null;
  mfaEnrollmentCodeHash: string | null;
  mfaEnrollmentExpiresAt: Date | null;
}

const MFA_SELECT = {
  id: true,
  mfaSecretEncrypted: true,
  mfaEnrolledAt: true,
  mfaLastUsedStep: true,
  mfaLockedUntil: true,
  mfaEnrollmentCodeHash: true,
  mfaEnrollmentExpiresAt: true,
} as const;

/**
 * The second factor for staff: authenticator-app (TOTP) codes checked here,
 * on our side, so it works on any Firebase plan.
 *
 *  - Enrolment needs the one-time code `pnpm admin:provision` printed. A
 *    stolen Firebase login alone therefore cannot enrol its own
 *    authenticator, even on an account that has none yet.
 *  - A code is accepted once (replay-proof per time step), and a run of wrong
 *    codes — or wrong enrolment codes — locks the second factor for a while.
 *  - A correct code issues an admin session (AdminSessionService).
 */
@Injectable()
export class AdminMfaService {
  private readonly logger = new Logger(AdminMfaService.name);
  private readonly key: Buffer | null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly access: AdminAccessService,
    private readonly sessions: AdminSessionService,
    private readonly audit: AdminAuditService,
    config: AppConfigService,
  ) {
    this.key = parseSecretKey(config.admin.mfaEncryptionKey);
    if (!this.key) {
      this.logger.warn(
        'ADMIN_MFA_ENCRYPTION_KEY is not set: admin sign-in answers 503.',
      );
    }
  }

  /** Step 1 of enrolment: a new secret for the admin's authenticator app. */
  async beginEnrollment(
    userId: string,
    enrollmentCode: string,
    context: AdminRequestContext,
    now: Date = new Date(),
  ): Promise<{ secret: string; otpauthUri: string }> {
    const key = this.requireKey();
    const staff = await this.requireStaff(userId);
    const account = await this.loadAccount(staff.adminAccountId);
    this.refuseIfEnrolled(account);
    await this.checkEnrollmentCode(
      account,
      staff,
      enrollmentCode,
      context,
      now,
    );

    const secret = generateTotpSecret();
    await this.prisma.adminAccount.update({
      where: { id: account.id },
      data: { mfaSecretEncrypted: seal(key, secret), mfaLastUsedStep: null },
    });
    await this.audit.recordBestEffort({
      actorId: staff.userId,
      actorType: 'STAFF',
      action: 'admin.mfa.enrollment.started',
      entity: 'AdminAccount',
      entityId: account.id,
      context,
    });
    return {
      secret,
      otpauthUri: otpauthUri({
        secret,
        accountName: staff.email,
        issuer: ISSUER,
      }),
    };
  }

  /** Step 2: the first code from the app proves it holds the secret; the
   *  enrolment code is spent and the admin is signed in. */
  async confirmEnrollment(
    userId: string,
    enrollmentCode: string,
    code: string,
    context: AdminRequestContext,
    now: Date = new Date(),
  ): Promise<IssuedAdminSession> {
    const key = this.requireKey();
    const staff = await this.requireStaff(userId);
    const account = await this.loadAccount(staff.adminAccountId);
    this.refuseIfEnrolled(account);
    await this.checkEnrollmentCode(
      account,
      staff,
      enrollmentCode,
      context,
      now,
    );
    if (!account.mfaSecretEncrypted) {
      throw new BadRequestException(
        'Start enrolment first: there is no authenticator secret to confirm.',
      );
    }
    await this.acceptCode(account, staff, key, code, context, now);

    return this.prisma.$transaction(async (tx) => {
      const spent = await tx.adminAccount.updateMany({
        where: {
          id: account.id,
          mfaEnrolledAt: null,
          mfaEnrollmentCodeHash: account.mfaEnrollmentCodeHash,
        },
        data: {
          mfaEnrolledAt: now,
          mfaEnrollmentCodeHash: null,
          mfaEnrollmentExpiresAt: null,
          lastLoginAt: now,
        },
      });
      if (spent.count !== 1) {
        // Another request confirmed (or the code was reset) in between.
        throw adminForbidden(
          'ADMIN_ENROLLMENT_CODE_INVALID',
          'This enrolment code is not valid or has expired.',
        );
      }
      const session = await this.sessions.create(tx, account.id, context, now);
      await this.audit.record(tx, {
        actorId: staff.userId,
        actorType: 'STAFF',
        action: 'admin.mfa.enrolled',
        entity: 'AdminAccount',
        entityId: account.id,
        context,
      });
      await this.audit.record(tx, {
        actorId: staff.userId,
        actorType: 'STAFF',
        action: 'admin.session.created',
        entity: 'AdminSession',
        entityId: session.sessionId,
        context,
      });
      return publicSession(session);
    });
  }

  /** Sign-in: an enrolled admin's authenticator code → an admin session. */
  async signIn(
    userId: string,
    code: string,
    context: AdminRequestContext,
    now: Date = new Date(),
  ): Promise<IssuedAdminSession> {
    const key = this.requireKey();
    const staff = await this.requireStaff(userId);
    const account = await this.loadAccount(staff.adminAccountId);
    if (!account.mfaEnrolledAt || !account.mfaSecretEncrypted) {
      throw adminForbidden(
        'ADMIN_MFA_NOT_ENROLLED',
        'Set up your authenticator first, using the enrolment code you were given.',
      );
    }
    await this.acceptCode(account, staff, key, code, context, now);

    return this.prisma.$transaction(async (tx) => {
      const session = await this.sessions.create(tx, account.id, context, now);
      await tx.adminAccount.update({
        where: { id: account.id },
        data: { lastLoginAt: now },
      });
      await this.audit.record(tx, {
        actorId: staff.userId,
        actorType: 'STAFF',
        action: 'admin.session.created',
        entity: 'AdminSession',
        entityId: session.sessionId,
        context,
      });
      return publicSession(session);
    });
  }

  /** A fresh code on the current session, for sensitive permissions. */
  async stepUp(
    admin: AuthenticatedAdmin,
    code: string,
    context: AdminRequestContext,
    now: Date = new Date(),
  ): Promise<{ stepUpValidUntil: Date }> {
    const key = this.requireKey();
    const staff = await this.requireStaff(admin.userId);
    const account = await this.loadAccount(staff.adminAccountId);
    if (!admin.sessionId || !account.mfaSecretEncrypted) {
      throw adminUnauthorized(
        'ADMIN_SESSION_REQUIRED',
        'Sign in with your authenticator first.',
      );
    }
    await this.acceptCode(account, staff, key, code, context, now);
    const sessionId = admin.sessionId;
    await this.prisma.$transaction(async (tx) => {
      await this.sessions.markVerified(tx, sessionId, now);
      await this.audit.record(tx, {
        actorId: staff.userId,
        actorType: 'STAFF',
        action: 'admin.session.step_up',
        entity: 'AdminSession',
        entityId: sessionId,
        context,
      });
    });
    return { stepUpValidUntil: new Date(now.getTime() + ADMIN_STEP_UP_MS) };
  }

  async logout(
    admin: AuthenticatedAdmin,
    context: AdminRequestContext,
    now: Date = new Date(),
  ): Promise<void> {
    const sessionId = admin.sessionId;
    if (!sessionId) return;
    await this.prisma.$transaction(async (tx) => {
      await this.sessions.revoke(tx, sessionId, 'LOGOUT', now);
      await this.audit.record(tx, {
        actorId: admin.userId,
        actorType: 'STAFF',
        action: 'admin.session.ended',
        entity: 'AdminSession',
        entityId: sessionId,
        reason: 'LOGOUT',
        context,
      });
    });
  }

  // --------------------------------------------------------------------------

  private requireKey(): Buffer {
    if (!this.key) {
      throw new ServiceUnavailableException(
        'Admin sign-in is not configured on this server.',
      );
    }
    return this.key;
  }

  private async requireStaff(userId: string): Promise<StaffAccount> {
    const staff = await this.access.loadStaff(userId);
    if (!staff) {
      throw adminForbidden(
        'ADMIN_ACCESS_REQUIRED',
        'This account does not have admin access.',
      );
    }
    return staff;
  }

  private loadAccount(adminAccountId: string): Promise<MfaAccount> {
    return this.prisma.adminAccount.findUniqueOrThrow({
      where: { id: adminAccountId },
      select: MFA_SELECT,
    });
  }

  private refuseIfEnrolled(account: MfaAccount): void {
    if (account.mfaEnrolledAt) {
      throw adminForbidden(
        'ADMIN_MFA_ALREADY_ENROLLED',
        'An authenticator is already set up. Ask a super admin to reset it if you lost it.',
      );
    }
  }

  private async checkEnrollmentCode(
    account: MfaAccount,
    staff: StaffAccount,
    enrollmentCode: string,
    context: AdminRequestContext,
    now: Date,
  ): Promise<void> {
    this.refuseIfLocked(account, now);
    const valid =
      !!account.mfaEnrollmentCodeHash &&
      !!account.mfaEnrollmentExpiresAt &&
      account.mfaEnrollmentExpiresAt.getTime() > now.getTime() &&
      hashEnrollmentCode(enrollmentCode) === account.mfaEnrollmentCodeHash;
    if (!valid) {
      await this.recordFailure(account, staff, 'ENROLLMENT_CODE', context, now);
      throw adminForbidden(
        'ADMIN_ENROLLMENT_CODE_INVALID',
        'This enrolment code is not valid or has expired.',
      );
    }
  }

  /**
   * Accepts [code] once: the matching time step must be newer than the last
   * one used, claimed with a conditional update so two concurrent requests
   * can't both spend it. Returns the step.
   */
  private async acceptCode(
    account: MfaAccount,
    staff: StaffAccount,
    key: Buffer,
    code: string,
    context: AdminRequestContext,
    now: Date,
  ): Promise<number> {
    this.refuseIfLocked(account, now);
    const secret = open(key, account.mfaSecretEncrypted!);
    const step = matchTotp(secret, code, now.getTime());
    const claimed =
      step !== null &&
      (
        await this.prisma.adminAccount.updateMany({
          where: {
            id: account.id,
            OR: [{ mfaLastUsedStep: null }, { mfaLastUsedStep: { lt: step } }],
          },
          data: {
            mfaLastUsedStep: step,
            mfaFailedAttempts: 0,
            mfaLockedUntil: null,
          },
        })
      ).count === 1;
    if (!claimed) {
      await this.recordFailure(account, staff, 'TOTP', context, now);
      throw adminUnauthorized(
        'ADMIN_MFA_INVALID_CODE',
        'That code is not correct. Check your authenticator app and try again.',
      );
    }
    return step;
  }

  private refuseIfLocked(account: MfaAccount, now: Date): void {
    const until = account.mfaLockedUntil?.getTime() ?? 0;
    if (until > now.getTime()) {
      throw adminLocked(Math.ceil((until - now.getTime()) / 1000));
    }
  }

  private async recordFailure(
    account: MfaAccount,
    staff: StaffAccount,
    kind: 'TOTP' | 'ENROLLMENT_CODE',
    context: AdminRequestContext,
    now: Date,
  ): Promise<void> {
    const { mfaFailedAttempts } = await this.prisma.adminAccount.update({
      where: { id: account.id },
      data: { mfaFailedAttempts: { increment: 1 } },
      select: { mfaFailedAttempts: true },
    });
    const locked = mfaFailedAttempts >= ADMIN_MFA_MAX_FAILURES;
    if (locked) {
      await this.prisma.adminAccount.update({
        where: { id: account.id },
        data: {
          mfaFailedAttempts: 0,
          mfaLockedUntil: new Date(now.getTime() + ADMIN_MFA_LOCK_MS),
        },
      });
    }
    await this.audit.recordBestEffort({
      actorId: staff.userId,
      actorType: 'STAFF',
      action: locked ? 'admin.mfa.locked' : 'admin.mfa.failed',
      entity: 'AdminAccount',
      entityId: account.id,
      metadata: { kind, attempts: mfaFailedAttempts },
      context,
    });
  }
}

function publicSession(
  session: IssuedAdminSession & { sessionId: string },
): IssuedAdminSession {
  return {
    sessionToken: session.sessionToken,
    expiresAt: session.expiresAt,
    idleTimeoutSeconds: session.idleTimeoutSeconds,
  };
}
