import { Injectable } from '@nestjs/common';
import { EntitlementRepository } from '../repositories/entitlement.repository';

/**
 * The one place a service asks "is this member premium?".
 *
 * Premium is derived from the member's UserSubscription rows only — never
 * from a client-supplied flag — so it can't be forged from the app. The rule
 * itself (ACTIVE, started, not yet ended, paid plan) is
 * `activePremiumSubscriptionWhere` in @app/database, shared with the list
 * queries that evaluate premium per candidate inside the same SQL statement.
 *
 * Use this for a single member (typically the caller). Never loop it over a
 * page of candidates — that is an N+1; select the premium probe in the list
 * query instead (see `photoPrivacySelectFor`).
 */
@Injectable()
export class EntitlementService {
  constructor(private readonly entitlementRepository: EntitlementRepository) {}

  hasActivePremiumSubscription(
    userId: string,
    now: Date = new Date(),
  ): Promise<boolean> {
    return this.entitlementRepository.hasActivePremiumSubscription(userId, now);
  }
}
