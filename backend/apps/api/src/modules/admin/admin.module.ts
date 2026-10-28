import { Module } from '@nestjs/common';
import { DiscoveryModule } from '@nestjs/core';
import { AppConfigModule } from '@app/config';
import { AdminGuard } from './auth/admin.guard';
import { AdminRouteCheck } from './auth/admin-route-check';
import { AdminAuthController } from './controllers/admin-auth.controller';
import { AdminMeController } from './controllers/admin-me.controller';
import { AdminAccessService } from './services/admin-access.service';
import { AdminAuditService } from './services/admin-audit.service';
import { AdminMfaService } from './services/admin-mfa.service';
import { AdminSessionService } from './services/admin-session.service';

/**
 * Staff access: RBAC (roles → permissions), the authenticator second factor,
 * admin sessions and the audit writer.
 *
 * Another module's admin controllers use `@AdminController(...)` and
 * `@RequirePermissions(...)`, and import this module so AdminGuard's
 * dependencies resolve there.
 */
@Module({
  // AppConfigModule is not global: AdminMfaService reads the MFA key from it.
  imports: [AppConfigModule, DiscoveryModule],
  controllers: [AdminAuthController, AdminMeController],
  providers: [
    AdminAccessService,
    AdminAuditService,
    AdminSessionService,
    AdminMfaService,
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
