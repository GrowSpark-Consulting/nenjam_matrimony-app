import type { AgentMemberProfilePort } from '../../ports/agent-money-ports';

/**
 * PENDING DECISION (Raja): what makes a member's profile "verified" for
 * `commission.require_verified_profile`. There is no KYC yet and the setting
 * is seeded `false`, so the daily approval never asks.
 *
 * Until the rule is decided this answers "not verified" for everyone, which
 * fails closed: if the setting is switched on, commissions wait in
 * AWAITING_VERIFICATION and no money is credited by mistake.
 */
export class UnverifiedMemberProfiles implements AgentMemberProfilePort {
  isProfileVerified(): Promise<boolean> {
    return Promise.resolve(false);
  }
}
