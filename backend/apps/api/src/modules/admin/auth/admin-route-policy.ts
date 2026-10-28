import type { PermissionKey } from '../rbac/permissions';

/** Metadata key the admin route decorators write and AdminGuard reads. */
export const ADMIN_ROUTE_POLICY = 'nenjam:admin-route-policy';

export interface AdminRoutePolicy {
  /** Every one is required. Empty = any active admin. */
  permissions: readonly PermissionKey[];
  /** False only for the sign-in steps that create the session. */
  sessionRequired: boolean;
}
