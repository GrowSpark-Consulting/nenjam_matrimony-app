import { defineAgentStoresContract } from './agent-stores.contract';
import {
  FakeAgentApplicantRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
  FakeReferralCodeAttemptStore,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';

// The in-memory fakes must pass the same suite as the Prisma adapters
// (adapters/prisma/prisma-agent-stores.db-spec.ts).
defineAgentStoresContract('fakes', () =>
  Promise.resolve({
    agents: new FakeAgentRepository(),
    codes: new FakeReferralCodeRepository(),
    attributions: new FakeReferralAttributionRepository(),
    applicants: new FakeAgentApplicantRepository(),
    attempts: new FakeReferralCodeAttemptStore(),
    seedMember: () => Promise.resolve(),
  }),
);
