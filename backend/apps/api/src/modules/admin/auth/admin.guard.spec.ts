import {
  ExecutionContext,
  ForbiddenException,
  HttpException,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { PermissionKey } from '../rbac/permissions';
import type {
  AdminAccessService,
  StaffAccount,
} from '../services/admin-access.service';
import type { AdminAuditService } from '../services/admin-audit.service';
import type {
  AdminSessionService,
  SessionState,
} from '../services/admin-session.service';
import { AdminGuard } from './admin.guard';
import { ADMIN_STEP_UP_MS } from './admin-auth.policy';
import { type AdminRequest, hasFreshStepUp } from './admin-request';
import {
  AdminSessionNotRequired,
  AllowAnyAdmin,
  RequirePermissions,
} from './admin-route.decorators';

const STAFF: StaffAccount = {
  userId: 'user-admin',
  email: 'ops@example.com',
  adminAccountId: 'acct-1',
  department: 'PLATFORM',
  mfaEnrolledAt: new Date('2026-10-01'),
  lastLoginAt: null,
};

class Routes {
  @RequirePermissions('plan.view')
  view() {}
  @RequirePermissions('member.pii.reveal')
  reveal() {}
  @RequirePermissions('plan.view', 'plan.publish')
  publish() {}
  @AllowAnyAdmin()
  me() {}
  @AdminSessionNotRequired()
  signIn() {}
  unannotated() {}
}

function build(opts: {
  staff?: StaffAccount | null;
  permissions?: PermissionKey[];
  session?: SessionState;
}) {
  const access = {
    loadStaff: jest
      .fn()
      .mockResolvedValue(opts.staff === undefined ? STAFF : opts.staff),
    grantsFor: jest.fn().mockResolvedValue({
      roles: [{ key: 'VIEWER', name: 'Viewer' }],
      permissions: opts.permissions ?? ['plan.view'],
    }),
  };
  const now = Date.now();
  const sessions = {
    validate: jest.fn().mockResolvedValue(
      opts.session ?? {
        ok: true,
        session: {
          id: 'sess-1',
          adminAccountId: STAFF.adminAccountId,
          lastSeenAt: new Date(now),
          expiresAt: new Date(now + 3_600_000),
          mfaVerifiedAt: new Date(now),
          revokedAt: null,
        },
      },
    ),
    touch: jest.fn().mockResolvedValue(undefined),
  };
  const audit = { recordBestEffort: jest.fn().mockResolvedValue(undefined) };
  const guard = new AdminGuard(
    new Reflector(),
    access as unknown as AdminAccessService,
    sessions as unknown as AdminSessionService,
    audit as unknown as AdminAuditService,
  );
  return { guard, access, sessions, audit };
}

function contextFor(
  handler: keyof Routes,
  headers: Record<string, string> = { 'x-admin-session': 'token' },
  user: AdminRequest['user'] | null = { id: STAFF.userId, uid: 'fb-admin' },
) {
  const request = {
    headers,
    method: 'GET',
    path: `/admin/${handler}`,
    ip: '203.0.113.9',
    user: user ?? undefined,
  } as unknown as AdminRequest;
  const response = { setHeader: jest.fn() };
  const ctx = {
    switchToHttp: () => ({
      getRequest: () => request,
      getResponse: () => response,
    }),
    getHandler: () => Routes.prototype[handler],
    getClass: () => Routes,
  } as unknown as ExecutionContext;
  return { ctx, request, response };
}

async function rejection(promise: Promise<unknown>) {
  try {
    await promise;
  } catch (error) {
    return error as HttpException;
  }
  throw new Error('expected the guard to refuse');
}

describe('AdminGuard', () => {
  it('lets an admin with the permission and a live session through, and attaches them', async () => {
    const { guard, sessions } = build({});
    const { ctx, request, response } = contextFor('view');
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(request.admin).toMatchObject({
      adminAccountId: 'acct-1',
      userId: 'user-admin',
      sessionId: 'sess-1',
      permissions: ['plan.view'],
    });
    expect(request.admin?.stepUpVerifiedAt).toBeInstanceOf(Date);
    expect(response.setHeader).toHaveBeenCalledWith(
      'Cache-Control',
      'no-store',
    );
    expect(sessions.validate).toHaveBeenCalledWith(
      'token',
      'acct-1',
      expect.any(Date),
    );
    expect(sessions.touch).toHaveBeenCalled();
  });

  it('refuses a route that declares no policy, even for an admin (deny by default)', async () => {
    const { guard, access, audit } = build({});
    const error = await rejection(
      guard.canActivate(contextFor('unannotated').ctx),
    );
    expect(error).toBeInstanceOf(ForbiddenException);
    expect(error.getResponse()).toMatchObject({
      code: 'ADMIN_ROUTE_UNPROTECTED',
    });
    expect(access.loadStaff).not.toHaveBeenCalled();
    expect(audit.recordBestEffort).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'admin.access.denied',
        reason: 'NO_ROUTE_POLICY',
      }),
    );
  });

  it('refuses a member (not staff) with 403 and records it', async () => {
    const { guard, sessions, audit } = build({ staff: null });
    const error = await rejection(guard.canActivate(contextFor('me').ctx));
    expect(error).toBeInstanceOf(ForbiddenException);
    expect(error.getResponse()).toMatchObject({
      statusCode: 403,
      code: 'ADMIN_ACCESS_REQUIRED',
    });
    expect(sessions.validate).not.toHaveBeenCalled();
    expect(audit.recordBestEffort).toHaveBeenCalledWith(
      expect.objectContaining({ actorId: 'user-admin', reason: 'NOT_STAFF' }),
    );
  });

  it('refuses without a Firebase identity (FirebaseAuthGuard must run first)', async () => {
    const { guard } = build({});
    await expect(
      guard.canActivate(contextFor('me', {}, null).ctx),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('requires an admin session: 401 when the header is missing', async () => {
    const { guard } = build({});
    const error = await rejection(guard.canActivate(contextFor('me', {}).ctx));
    expect(error).toBeInstanceOf(UnauthorizedException);
    expect(error.getResponse()).toMatchObject({
      code: 'ADMIN_SESSION_REQUIRED',
    });
  });

  it.each(['UNKNOWN', 'REVOKED', 'EXPIRED', 'IDLE'] as const)(
    'refuses a %s session with 401',
    async (reason) => {
      const { guard, access } = build({ session: { ok: false, reason } });
      const error = await rejection(guard.canActivate(contextFor('me').ctx));
      expect(error).toBeInstanceOf(UnauthorizedException);
      expect(error.getResponse()).toMatchObject({
        code: 'ADMIN_SESSION_INVALID',
      });
      expect(access.grantsFor).not.toHaveBeenCalled();
    },
  );

  it('refuses an admin missing any required permission with 403, naming what is missing', async () => {
    const { guard, audit } = build({ permissions: ['plan.view'] });
    const error = await rejection(guard.canActivate(contextFor('publish').ctx));
    expect(error).toBeInstanceOf(ForbiddenException);
    expect(error.getResponse()).toMatchObject({
      code: 'ADMIN_PERMISSION_DENIED',
      missing: ['plan.publish'],
    });
    expect(audit.recordBestEffort).toHaveBeenCalledWith(
      expect.objectContaining({
        reason: 'MISSING_PERMISSION',
        metadata: { missing: ['plan.publish'] },
      }),
    );
  });

  it('lets any admin through @AllowAnyAdmin, whatever their roles', async () => {
    const { guard } = build({ permissions: [] });
    await expect(guard.canActivate(contextFor('me').ctx)).resolves.toBe(true);
  });

  it('lets active staff reach the sign-in steps without a session', async () => {
    const { guard, sessions } = build({});
    const { ctx, request } = contextFor('signIn', {});
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(sessions.validate).not.toHaveBeenCalled();
    expect(request.admin?.sessionId).toBeNull();
  });

  it('still refuses non-staff on the sign-in steps', async () => {
    const { guard } = build({ staff: null });
    await expect(
      guard.canActivate(contextFor('signIn', {}).ctx),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  describe('sensitive permissions', () => {
    const sessionVerified = (msAgo: number): SessionState => {
      const now = Date.now();
      return {
        ok: true,
        session: {
          id: 'sess-1',
          adminAccountId: STAFF.adminAccountId,
          lastSeenAt: new Date(now),
          expiresAt: new Date(now + 3_600_000),
          mfaVerifiedAt: new Date(now - msAgo),
          revokedAt: null,
        },
      };
    };

    it('pass with a recent authenticator check', async () => {
      const { guard } = build({
        permissions: ['member.pii.reveal'],
        session: sessionVerified(60_000),
      });
      await expect(guard.canActivate(contextFor('reveal').ctx)).resolves.toBe(
        true,
      );
    });

    it('need a step-up (401) once the check is older than the window', async () => {
      const { guard } = build({
        permissions: ['member.pii.reveal'],
        session: sessionVerified(ADMIN_STEP_UP_MS + 1_000),
      });
      const error = await rejection(
        guard.canActivate(contextFor('reveal').ctx),
      );
      expect(error).toBeInstanceOf(UnauthorizedException);
      expect(error.getResponse()).toMatchObject({
        code: 'ADMIN_STEP_UP_REQUIRED',
      });
    });
  });
});

describe('hasFreshStepUp', () => {
  const now = new Date('2026-10-29T10:00:00Z');
  const at = (msAgo: number) => new Date(now.getTime() - msAgo);

  it('is the guard’s 10-minute rule, for services that only reveal data to a fresh caller', () => {
    expect(hasFreshStepUp({ stepUpVerifiedAt: at(60_000) }, now)).toBe(true);
    expect(
      hasFreshStepUp({ stepUpVerifiedAt: at(ADMIN_STEP_UP_MS) }, now),
    ).toBe(true);
    expect(
      hasFreshStepUp({ stepUpVerifiedAt: at(ADMIN_STEP_UP_MS + 1) }, now),
    ).toBe(false);
    expect(hasFreshStepUp({ stepUpVerifiedAt: null }, now)).toBe(false);
  });
});
