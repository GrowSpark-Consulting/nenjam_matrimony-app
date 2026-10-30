/**
 * Setup for the admin service specs: the commission harness plus a fake
 * permission port, a sealer, a hasher and a status history, with the admin
 * services wired to them. Tests only.
 */
import { AgentAdminCommissionService } from '../admin/agent-admin-commission.service';
import { AgentAdminPayoutService } from '../admin/agent-admin-payout.service';
import { AgentAdminReferralService } from '../admin/agent-admin-referral.service';
import { AgentAdminService } from '../admin/agent-admin.service';
import type { AdminActor } from '../admin/agent-admin-support';
import type { AgentStatusHistoryPort } from '../ports/agent-money-ports';
import { makeCommissionHarness, T0 } from './agent-commission-harness';
import { FakeAgentSecretSealer } from './fake-agent-secret-sealer';
import {
  FakeAgentIdentifierHasher,
  FakeAgentPermission,
} from './fake-agent-platform';
import { FakeReferralCodeRepository } from './fake-agent-repositories';

export class FakeStatusHistory implements AgentStatusHistoryPort {
  readonly rows: Array<{
    agentId: string;
    action: string;
    at: Date;
    actorId: string | null;
    reason: string | null;
  }> = [];

  listForAgent(agentId: string) {
    return Promise.resolve(this.rows.filter((r) => r.agentId === agentId));
  }
}

export const SUPER = 'staff-super';
export const PAYER = 'staff-payer';
export const PARTNER = 'staff-partner';
export const NOBODY = 'staff-nobody';

/** The seeded roles (Raja, 28 Oct): SUPER_ADMIN, PARTNER_MANAGER, PAYOUT_MANAGER. */
const GRANTS: Record<string, string[]> = {
  [SUPER]: [
    'agent.view',
    'agent.approve',
    'agent.manage',
    'agent.payout_details.verify',
    'agent.pii.reveal',
    'attribution.view',
    'attribution.override',
    'commission.view',
    'commission.approve',
    'commission.cancel',
    'commission.override',
    'payout.view',
    'payout.execute',
  ],
  [PARTNER]: ['agent.view', 'agent.approve'],
  // The payer has no agent.view.
  [PAYER]: ['payout.view', 'payout.execute'],
};

export const actorOf = (userId: string, stepUpFresh = true): AdminActor => ({
  userId,
  stepUpFresh,
});

export function makeAdminHarness() {
  const base = makeCommissionHarness();
  const permission = new FakeAgentPermission();
  for (const [user, keys] of Object.entries(GRANTS)) {
    for (const key of keys) {
      const dot = key.indexOf('.');
      permission.grant(user, {
        module: key.slice(0, dot),
        action: key.slice(dot + 1),
      });
    }
  }
  const sealer = new FakeAgentSecretSealer();
  const hasher = new FakeAgentIdentifierHasher('test-secret');
  const history = new FakeStatusHistory();
  // The base harness has no referral-code repository; the admin services need one.
  const codes = new FakeReferralCodeRepository();

  let ids = 0;
  const newId = () => `adm-${++ids}`;
  // Deterministic codes: NM2222XY, NM2222XZ ... (valid alphabet).
  let codeCounter = 0;
  const random = () => {
    codeCounter += 1;
    return codeCounter % 20;
  };

  const common = {
    uow: base.uow,
    agents: base.agents,
    permission,
    audit: base.audit,
    clock: base.clock,
  };
  const agentsAdmin = new AgentAdminService(
    {
      ...common,
      codes,
      payoutDetails: base.payoutDetails,
      attributions: base.attributions,
      sealer,
      hasher,
      history,
    },
    { newId, random },
  );
  const referralsAdmin = new AgentAdminReferralService({
    ...common,
    attributions: base.attributions,
  });
  const commissionsAdmin = new AgentAdminCommissionService(
    {
      ...common,
      commissions: base.commissions,
      ledger: base.ledger,
      approval: base.approval,
    },
    { newId },
  );
  const payoutsAdmin = new AgentAdminPayoutService({
    ...common,
    codes,
    payoutDetails: base.payoutDetails,
    commissions: base.commissions,
    payouts: base.payouts,
    payoutService: base.payoutService,
    sealer,
  });

  /** A PENDING_APPROVAL applicant with a PAN, ready for approval. */
  const seedApplicant = async (id = 'agent-1') => {
    const agent = await base.seedAgent('PENDING_APPROVAL', {
      id,
      phoneE164: '+919876543210',
    });
    return base.agents.update(agent.id, {
      panLast4: '234F',
      panSealed: sealer.seal('ABCDE1234F'),
    });
  };

  /** Sealed UPI details, verified or not. */
  const seedPayoutDetails = async (
    agentId = 'agent-1',
    verifiedAt: Date | null = null,
  ) => {
    await base.agents.update(agentId, { payoutDetailsSet: true });
    await base.payoutDetails.save({
      agentId,
      method: 'UPI',
      detailsSealed: sealer.seal(
        JSON.stringify({ upi: { vpa: 'ravi@okbank' } }),
      ),
      display: 'r***@okbank',
      verifiedAt,
      changedAt: T0,
    });
  };

  return {
    ...base,
    codes,
    permission,
    sealer,
    hasher,
    history,
    agentsAdmin,
    referralsAdmin,
    commissionsAdmin,
    payoutsAdmin,
    seedApplicant,
    seedPayoutDetails,
  };
}

export type AdminHarness = ReturnType<typeof makeAdminHarness>;
