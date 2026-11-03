import type { AgentStatus } from '../agent/agent-status';
import { defineAgentClientContract } from './agent-clients.contract';
import {
  FakeAgentClientConsentCodeStore,
  FakeAgentClientDraftRepository,
} from './fake-agent-clients';
import { FakeAgentRepository } from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

// The in-memory fakes must pass the same suite as the Prisma adapters
// (adapters/prisma/prisma-agent-clients.db-spec.ts).
defineAgentClientContract('fakes', () => {
  const agents = new FakeAgentRepository();
  let n = 0;
  return Promise.resolve({
    uow: new FakeAgentUnitOfWork(),
    drafts: new FakeAgentClientDraftRepository(agents),
    codes: new FakeAgentClientConsentCodeStore(),
    seedAgent: async (id: string, status: AgentStatus = 'ACTIVE') => {
      n += 1;
      await agents.create({
        id,
        phoneHash: `v1:agent-${n}`,
        phoneE164: `+91900000000${n}`,
        name: `Agent ${n}`,
        city: 'Madurai',
        state: 'Tamil Nadu',
        panLast4: null,
        panSealed: null,
        createdAt: new Date('2026-11-01T00:00:00.000Z'),
      });
      await agents.update(id, { status });
    },
    setAgentStatus: async (id: string, status: AgentStatus) => {
      await agents.update(id, { status });
    },
    seedMember: () => Promise.resolve(),
    seedAttribution: () => Promise.resolve(),
  });
});
