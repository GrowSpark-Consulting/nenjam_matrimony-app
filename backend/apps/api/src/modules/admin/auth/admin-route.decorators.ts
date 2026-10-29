import {
  applyDecorators,
  Controller,
  SetMetadata,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiTags } from '@nestjs/swagger';
import { FirebaseAuthGuard } from '@app/common';
import type { PermissionKey } from '../rbac/permissions';
import { AdminGuard } from './admin.guard';
import { ADMIN_SESSION_HEADER } from './admin-auth.policy';
import {
  ADMIN_ROUTE_POLICY,
  type AdminRoutePolicy,
} from './admin-route-policy';

/**
 * Every route on an `@AdminController` must declare exactly one of these.
 * There is no default: a route without one is refused at request time
 * (AdminGuard) and fails the boot-time check (AdminRouteCheck).
 */
export const RequirePermissions = (
  ...permissions: [PermissionKey, ...PermissionKey[]]
) =>
  SetMetadata(ADMIN_ROUTE_POLICY, {
    permissions,
    sessionRequired: true,
  } satisfies AdminRoutePolicy);

/** Any signed-in, active admin, whatever their roles (e.g. GET /admin/me). */
export const AllowAnyAdmin = () =>
  SetMetadata(ADMIN_ROUTE_POLICY, {
    permissions: [],
    sessionRequired: true,
  } satisfies AdminRoutePolicy);

/**
 * Only for the steps that create an admin session (authenticator enrolment
 * and sign-in): the caller must be active staff with a valid Firebase token,
 * but cannot have a session yet.
 */
export const AdminSessionNotRequired = () =>
  SetMetadata(ADMIN_ROUTE_POLICY, {
    permissions: [],
    sessionRequired: false,
  } satisfies AdminRoutePolicy);

/**
 * A staff-only controller: Firebase identity, then AdminGuard (active staff,
 * admin session, permissions). Use this for every /admin/* controller,
 * including ones in other modules (import AdminModule there).
 */
export function AdminController(path: string): ClassDecorator {
  return applyDecorators(
    Controller(path),
    UseGuards(FirebaseAuthGuard, AdminGuard),
    ApiTags('Admin'),
    ApiBearerAuth('firebase'),
    ApiHeader({
      name: ADMIN_SESSION_HEADER,
      description:
        'Admin session token from POST /admin/auth/session (not needed on the sign-in routes).',
      required: false,
    }),
  );
}
