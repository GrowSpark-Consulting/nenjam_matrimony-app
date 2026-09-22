import { Module } from '@nestjs/common';
import { EntitlementService } from './services/entitlement.service';
import { EntitlementRepository } from './repositories/entitlement.repository';

/**
 * Premium entitlement checks, independent of the (still unimplemented)
 * subscription/checkout module: this only READS UserSubscription rows, so it
 * works unchanged once checkout and the Razorpay webhook start writing them.
 * PrismaService is provided by its @Global module.
 */
@Module({
  providers: [EntitlementService, EntitlementRepository],
  exports: [EntitlementService],
})
export class EntitlementsModule {}
