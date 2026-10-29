import { defineAgentCommissionContract } from './agent-commission.contract';
import {
  FakeAgentLedgerRepository,
  FakeAgentPayoutRepository,
  FakeCommissionPolicyRepository,
  FakeCommissionRepository,
} from './fake-agent-commission-repositories';
import {
  FakeAgentRepository,
  FakeReferralAttributionRepository,
} from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

// The in-memory fakes must pass the same suite as the Prisma adapters
// (adapters/prisma/prisma-agent-commission.db-spec.ts).
defineAgentCommissionContract('fakes', () => {
  const policy = new FakeCommissionPolicyRepository();
  return Promise.resolve({
    uow: new FakeAgentUnitOfWork(),
    agents: new FakeAgentRepository(),
    attributions: new FakeReferralAttributionRepository(),
    policy,
    commissions: new FakeCommissionRepository(),
    ledger: new FakeAgentLedgerRepository(() => new Date()),
    payouts: new FakeAgentPayoutRepository(),
    addPolicyVersion: (version) => {
      policy.add(version);
      return Promise.resolve();
    },
  });
});
