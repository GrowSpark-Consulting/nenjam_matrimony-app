import type { MembershipEnforcementMode } from '@app/config';
import { MembershipService } from '../services/membership.service';

/**
 * A REAL MembershipService in [mode] with stand-in collaborators. In `off`
 * mode it never touches them, so a feature spec that isn't about membership
 * gets genuine pre-membership behaviour (the legacy photo cap included)
 * rather than a stub that could drift from it. Membership specs pass real
 * fakes for the collaborators they exercise.
 */
export function membershipServiceInMode(
  mode: MembershipEnforcementMode = 'off',
  collaborators: {
    prisma?: unknown;
    catalog?: unknown;
    membershipRepository?: unknown;
    usageRepository?: unknown;
  } = {},
): MembershipService {
  return new MembershipService(
    (collaborators.prisma ?? {}) as never,
    (collaborators.catalog ?? {}) as never,
    (collaborators.membershipRepository ?? {}) as never,
    (collaborators.usageRepository ?? {}) as never,
    { membership: { enforcementMode: mode } } as never,
  );
}
