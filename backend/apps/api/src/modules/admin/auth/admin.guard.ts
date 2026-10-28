import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SENSITIVE_PERMISSIONS } from '../rbac/permissions';
import { AdminAccessService } from '../services/admin-access.service';
import { AdminAuditService } from '../services/admin-audit.service';
import { AdminSessionService } from '../services/admin-session.service';
import {
  ADMIN_SESSION_HEADER,
  ADMIN_STEP_UP_MS,
  adminForbidden,
  adminUnauthorized,
} from './admin-auth.policy';
import { type AdminRequest, requestContextOf } from './admin-request';
import {
  ADMIN_ROUTE_POLICY,
  type AdminRoutePolicy,
} from './admin-route-policy';

/**
 * The authorisation half of every /admin/* request. Runs after
 * FirebaseAuthGuard (who is this, and is their account usable?) and answers,
 * in order:
 *
 *  1. Does the route declare a policy?            no  → 403 (deny by default)
 *  2. Is the caller active staff?                 no  → 403 ADMIN_ACCESS_REQUIRED
 *  3. Do they hold a live admin session — proof
 *     of the authenticator check — of their own?  no  → 401 ADMIN_SESSION_*
 *  4. Do their roles grant every permission?      no  → 403 ADMIN_PERMISSION_DENIED
 *  5. Sensitive permission: recent code check?    no  → 401 ADMIN_STEP_UP_REQUIRED
 *
 * Refusals at 1, 2 and 4 are written to the audit log. Everything is read
 * from the database per request, so revoking a role or switching an account
 * off takes effect on the next request.
 *
 * Hiding a button in the admin panel is not authorisation; this is.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly access: AdminAccessService,
    private readonly sessions: AdminSessionService,
    private readonly audit: AdminAuditService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const request = ctx.switchToHttp().getRequest<AdminRequest>();
    const user = request.user;
    if (!user) {
      // FirebaseAuthGuard must run first; reaching here without it is a
      // wiring bug, refused as unauthenticated rather than trusted.
      throw new UnauthorizedException('Authentication required.');
    }
    const context = requestContextOf(request);
    const routePath = (request.route as { path?: string } | undefined)?.path;
    const route = `${request.method} ${routePath ?? request.path}`;
    const now = new Date();

    const policy = this.reflector.get<AdminRoutePolicy | undefined>(
      ADMIN_ROUTE_POLICY,
      ctx.getHandler(),
    );
    if (!policy) {
      await this.denied(user.id, 'NO_ROUTE_POLICY', route, context);
      throw adminForbidden(
        'ADMIN_ROUTE_UNPROTECTED',
        'This admin route declares no permission, so it is closed.',
      );
    }

    const staff = await this.access.loadStaff(user.id);
    if (!staff) {
      await this.denied(user.id, 'NOT_STAFF', route, context);
      throw adminForbidden(
        'ADMIN_ACCESS_REQUIRED',
        'This account does not have admin access.',
      );
    }

    let sessionId: string | null = null;
    let mfaVerifiedAt: Date | null = null;
    if (policy.sessionRequired) {
      const token = request.headers[ADMIN_SESSION_HEADER];
      if (typeof token !== 'string' || token.length === 0) {
        throw adminUnauthorized(
          'ADMIN_SESSION_REQUIRED',
          'Enter the code from your authenticator app to continue.',
        );
      }
      const state = await this.sessions.validate(
        token,
        staff.adminAccountId,
        now,
      );
      if (!state.ok) {
        throw adminUnauthorized(
          'ADMIN_SESSION_INVALID',
          'Your admin session has ended. Enter a new authenticator code.',
        );
      }
      sessionId = state.session.id;
      mfaVerifiedAt = state.session.mfaVerifiedAt;
      await this.sessions.touch(state.session, now);
    }

    const grants = await this.access.grantsFor(staff.adminAccountId);
    const missing = policy.permissions.filter(
      (key) => !grants.permissions.includes(key),
    );
    if (missing.length > 0) {
      await this.denied(user.id, 'MISSING_PERMISSION', route, context, {
        missing,
      });
      throw adminForbidden(
        'ADMIN_PERMISSION_DENIED',
        `Not permitted: requires ${missing.join(', ')}.`,
        { missing },
      );
    }

    const sensitive = policy.permissions.some((key) =>
      SENSITIVE_PERMISSIONS.has(key),
    );
    if (
      sensitive &&
      (!mfaVerifiedAt ||
        now.getTime() - mfaVerifiedAt.getTime() > ADMIN_STEP_UP_MS)
    ) {
      throw adminUnauthorized(
        'ADMIN_STEP_UP_REQUIRED',
        'This action needs a fresh code from your authenticator app.',
      );
    }

    request.admin = {
      adminAccountId: staff.adminAccountId,
      userId: staff.userId,
      email: staff.email,
      department: staff.department,
      lastLoginAt: staff.lastLoginAt,
      sessionId,
      roles: grants.roles,
      permissions: grants.permissions,
    };
    return true;
  }

  private denied(
    actorId: string,
    reason: 'NO_ROUTE_POLICY' | 'NOT_STAFF' | 'MISSING_PERMISSION',
    route: string,
    context: ReturnType<typeof requestContextOf>,
    extra?: { missing: string[] },
  ): Promise<void> {
    return this.audit.recordBestEffort({
      actorId,
      actorType: reason === 'NOT_STAFF' ? 'MEMBER' : 'STAFF',
      action: 'admin.access.denied',
      entity: 'AdminRoute',
      entityId: route,
      reason,
      metadata: extra,
      context,
    });
  }
}
