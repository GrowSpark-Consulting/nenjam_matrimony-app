import { defineAgentRepositoryContract } from './agent-repositories.contract';
import {
  FakeAgentPayoutDetailsRepository,
  FakeAgentRefreshTokenRepository,
  FakeAgentRepository,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentAudit } from './fake-agent-platform';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

// The in-memory fakes must pass the same suite as the Prisma adapters
// (adapters/prisma/prisma-agent-repositories.db-spec.ts).
defineAgentRepositoryContract('fakes', () => {
  const audit = new FakeAgentAudit();
  return Promise.resolve({
    uow: new FakeAgentUnitOfWork(),
    agents: new FakeAgentRepository(),
    codes: new FakeReferralCodeRepository(),
    tokens: new FakeAgentRefreshTokenRepository(),
    payout: new FakeAgentPayoutDetailsRepository(),
    audit,
    auditCount: () => Promise.resolve(audit.entries.length),
  });
});
