import { Module } from '@nestjs/common';
import { DiscoveryModule } from '@nestjs/core';
import { AppConfigModule } from '@app/config';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { SubscriptionModule } from '../subscription/subscription.module';
import { AdminGuard } from './auth/admin.guard';
import { AdminRouteCheck } from './auth/admin-route-check';
import { AdminAuthController } from './controllers/admin-auth.controller';
import { AdminMeController } from './controllers/admin-me.controller';
import {
  AdminAuditLogsController,
  AdminOverviewController,
  AdminRolesController,
  AdminSubscriptionsController,
} from './controllers/admin-operations.controller';
import {
  AdminPlanDraftsController,
  AdminPlansController,
} from './controllers/admin-plans.controller';
import { AdminAccessService } from './services/admin-access.service';
import { AdminAuditService } from './services/admin-audit.service';
import { AdminMfaService } from './services/admin-mfa.service';
import { AdminQueriesService } from './services/admin-queries.service';
import { AdminSessionService } from './services/admin-session.service';

/**
 * Staff access — RBAC (roles → permissions), the authenticator second factor,
 * admin sessions, the audit writer — and the admin API over membership
 * (plans, drafts, subscriptions), the audit log, the overview and roles.
 *
 * Wraps SubscriptionModule's services; nothing there depends on this module.
 * Another module's admin controllers use `@AdminController(...)` and
 * `@RequirePermissions(...)`, and import this module so AdminGuard's
 * dependencies resolve there.
 */
@Module({
  // AppConfigModule is not global: AdminMfaService reads the MFA key from it.
  imports: [
    AppConfigModule,
    DiscoveryModule,
    EntitlementsModule,
    SubscriptionModule,
  ],
  controllers: [
    AdminAuthController,
    AdminMeController,
    AdminOverviewController,
    AdminPlansController,
    AdminPlanDraftsController,
    AdminSubscriptionsController,
    AdminAuditLogsController,
    AdminRolesController,
  ],
  providers: [
    AdminAccessService,
    AdminAuditService,
    AdminSessionService,
    AdminMfaService,
    AdminQueriesService,
    AdminGuard,
    AdminRouteCheck,
  ],
  exports: [
    AdminAccessService,
    AdminAuditService,
    AdminSessionService,
    AdminGuard,
  ],
})
export class AdminModule {}
