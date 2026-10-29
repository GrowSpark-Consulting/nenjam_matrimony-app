/**
 * Fakes wired to `AgentAdminAgentsService` for the PR A specs. Tests only.
 */
import { AgentAdminAgentsService } from '../admin/agent-admin-agents.service';
import type { AgentStatus } from '../agent/agent-status';
import type { AgentRecord } from '../ports/agent-data-ports';
import { FakeAgentAdminRead } from './fake-agent-admin-read';
import { FakeAgentClock } from './fake-agent-infra';
import {
  FakeAgentAudit,
  FakeAgentIdentifierHasher,
  FakeAgentPermission,
} from './fake-agent-platform';
import {
  FakeAgentPayoutDetailsRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

export const NOW = new Date('2026-10-29T10:00:00.000Z');
export const VIEWER = 'staff-viewer';
export const APPROVER = 'staff-approver';
export const NOBODY = 'staff-nobody';
export const SEALED_PAN = 'v1:sealed-pan-ABCDE1234F';
export const SEALED_DETAILS = 'v1:sealed-details-ravi@okbank';

export function makeAgentAdminHarness() {
  const uow = new FakeAgentUnitOfWork();
  const agents = new FakeAgentRepository();
  const codes = new FakeReferralCodeRepository();
  const payoutDetails = new FakeAgentPayoutDetailsRepository();
  const attributions = new FakeReferralAttributionRepository();
  const audit = new FakeAgentAudit();
  const read = new FakeAgentAdminRead(
    agents,
    codes,
    payoutDetails,
    attributions,
    audit,
  );
  const permission = new FakeAgentPermission();
  permission.grant(VIEWER, { module: 'agent', action: 'view' });
  permission.grant(APPROVER, { module: 'agent', action: 'view' });
  permission.grant(APPROVER, { module: 'agent', action: 'approve' });
  const hasher = new FakeAgentIdentifierHasher('test-secret', ['old-secret']);
  const clock = new FakeAgentClock(NOW);

  let ids = 0;
  const newId = () =>
    `00000000-0000-4000-8000-${String(++ids).padStart(12, '0')}`;
  let draws = 0;
  const random = () => (draws++ * 7) % 23;

  const service = new AgentAdminAgentsService(
    {
      uow,
      agents,
      codes,
      payoutDetails,
      attributions,
      read,
      permission,
      audit,
      hasher,
      clock,
    },
    { newId, random },
  );

  /** An agent; `n` makes the id, phone and createdAt distinct. */
  const seedAgent = async (
    n: number,
    status: AgentStatus = 'PENDING_APPROVAL',
    o: Partial<AgentRecord> = {},
  ) => {
    const id = `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
    const phone = `+9190000000${String(n).padStart(2, '0')}`;
    await agents.create({
      id,
      phoneHash: hasher.hash('PHONE', phone),
      phoneE164: phone,
      name: o.name ?? `Agent ${n}`,
      city: 'Madurai',
      state: 'Tamil Nadu',
      panLast4: '234F',
      panSealed: SEALED_PAN,
      createdAt: new Date(NOW.getTime() - (100 - n) * 60_000),
    });
    if (status !== 'PENDING_APPROVAL' || Object.keys(o).length > 0) {
      await agents.update(id, {
        status,
        ...(status === 'REJECTED' && { rejectionReason: 'Earlier reason' }),
        ...o,
      });
    }
    read.track(id);
    return { id, phone };
  };

  return {
    uow,
    agents,
    codes,
    payoutDetails,
    attributions,
    audit,
    read,
    permission,
    hasher,
    clock,
    service,
    seedAgent,
  };
}

export type AgentAdminHarness = ReturnType<typeof makeAgentAdminHarness>;
