import { Module } from '@nestjs/common';
import { AppConfigModule } from '@app/config';
import { EntitlementService } from './services/entitlement.service';
import { EntitlementRepository } from './repositories/entitlement.repository';
import { MembershipService } from './services/membership.service';
import { MembershipRepository } from './repositories/membership.repository';
import { UsageRepository } from './repositories/usage.repository';
import { PlanCatalogService } from './catalog/plan-catalog.service';

/**
 * Membership entitlements — the read and enforcement side of plans:
 *
 *  - MembershipService: the central engine every feature asks ("may this
 *    member do X / use one more Y?"), applying MEMBERSHIP_ENFORCEMENT_MODE.
 *  - PlanCatalogService: the cached, validated plan catalogue.
 *  - EntitlementService: the original "has any paid plan?" probe, kept as-is
 *    for privacy settings.
 *
 * Writes to subscriptions (checkout, payments, lifecycle) live in
 * SubscriptionModule, which imports this one — never the reverse. Only READS
 * UserSubscription rows, so features can depend on it without pulling in
 * payments. PrismaService is provided by its @Global module.
 */
@Module({
  imports: [AppConfigModule],
  providers: [
    EntitlementService,
    EntitlementRepository,
    MembershipService,
    MembershipRepository,
    UsageRepository,
    PlanCatalogService,
  ],
  exports: [EntitlementService, MembershipService, PlanCatalogService],
})
export class EntitlementsModule {}
