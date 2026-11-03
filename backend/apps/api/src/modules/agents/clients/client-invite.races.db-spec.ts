/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the
 * accept races of ClientInviteService on the Prisma adapters and a
 * throwaway LOCAL Postgres. Only Firebase is a stand-in.
 *
 * - two accepts of one invitation at once: both answer, one account;
 * - two agents' invitations for one phone accepted at once: one account, no
 *   deadlock (the accept locks every open draft of the phone in id order);
 * - an accept against the expiry: exactly one of them wins, and the
 *   database agrees with the answers.
 */
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { PrismaAgentClientAccount } from '../adapters/prisma/prisma-agent-client-account';
import { PrismaAgentClientDraftRepository } from '../adapters/prisma/prisma-agent-client-draft.repository';
import { PrismaAgentRepository } from '../adapters/prisma/prisma-agent.repository';
import { PrismaAgentUnitOfWork } from '../adapters/prisma/prisma-agent-unit-of-work';
import { PrismaReferralAttributionRepository } from '../adapters/prisma/prisma-referral-attribution.repository';
import { PrismaTestAudit } from '../adapters/prisma/prisma-test-audit';
import {
  freshTestDatabase,
  openTestDatabase,
} from '../adapters/prisma/prisma-test-database';
import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import { REFERRAL_CREDIT_WINDOW_DAYS_KEY } from '../settings/agent-program-settings';
import { CLIENT_DETAILS } from '../testing/agent-test-harness';
import {
  FakeAgentClock,
  FakeAgentTokenSigner,
} from '../testing/fake-agent-infra';
import {
  FakeAgentIdentifierHasher,
  FakeAgentSettings,
} from '../testing/fake-agent-platform';
import { FakeAgentSecretSealer } from '../testing/fake-agent-secret-sealer';
import { ClientInviteService } from './client-invite.service';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());
beforeEach(() => freshTestDatabase(prisma));

const PHONE = '+919000000001';
const T0 = new Date('2026-11-03T09:00:00.000Z');
const DAY = 86_400_000;

const sealer = new FakeAgentSecretSealer();
const hasher = new FakeAgentIdentifierHasher('race-pepper');

function service(clock: FakeAgentClock) {
  const proofUnused = {
    canReach: () => true,
    send: () => Promise.reject(new Error('not used')),
    verify: () => Promise.reject(new Error('not used')),
  };
  return new ClientInviteService({
    settings: new FakeAgentSettings({
      [AGENT_CLIENTS_ENABLED_KEY]: true,
      [REFERRAL_CREDIT_WINDOW_DAYS_KEY]: 60,
    }),
    proof: proofUnused,
    hasher,
    drafts: new PrismaAgentClientDraftRepository(prisma),
    agents: new PrismaAgentRepository(prisma),
    attributions: new PrismaReferralAttributionRepository(prisma),
    accounts: new PrismaAgentClientAccount(prisma, {
      findOrCreateUser: ({ phone }) =>
        Promise.resolve({ uid: `uid-${phone.slice(1)}`, created: true }),
      createCustomToken: (uid) => Promise.resolve(`custom-token-${uid}`),
    }),
    sealer,
    uow: new PrismaAgentUnitOfWork(prisma),
    audit: new PrismaTestAudit(prisma),
    clock,
    signer: new FakeAgentTokenSigner('unused'),
    options: { issuer: 'nenjam-api', audience: 'nenjam-client-invite' },
  });
}

const clientClaims = (phone = PHONE): AgentAccessClaims => ({
  sub: sealer.seal(AGENT_SEAL_PURPOSES.clientPhone, phone),
  scope: 'CLIENT',
  aud: 'nenjam-client-invite',
  iss: 'nenjam-api',
  iat: Math.floor(T0.getTime() / 1000),
  exp: Math.floor(T0.getTime() / 1000) + 900,
});

let agents = 0;
async function seedAgent(id: string) {
  agents += 1;
  await prisma.agent.create({
    data: {
      id,
      phone: `+91900000${String(agents).padStart(4, '0')}`,
      phoneHash: `v1:agent-${id}`,
      name: 'Ravi Kumar',
      city: 'Madurai',
      state: 'Tamil Nadu',
      status: 'ACTIVE',
    },
  });
}

/** A waiting invitation from `agentId` for `phone`, open until `expiresAt`. */
async function waitingInvite(
  id: string,
  agentId: string,
  expiresAt = new Date(T0.getTime() + 14 * DAY),
  phone = PHONE,
) {
  const drafts = new PrismaAgentClientDraftRepository(prisma);
  await drafts.create({
    id,
    agentId,
    phoneHash: hasher.hash('PHONE', phone),
    phoneSealed: sealer.seal(AGENT_SEAL_PURPOSES.clientPhone, phone),
    phoneMasked: '+91 90***001',
    displayName: 'Priya S.',
    detailsSealed: sealer.seal(
      AGENT_SEAL_PURPOSES.clientDetails,
      JSON.stringify(CLIENT_DETAILS),
    ),
    expiresAt,
    createdAt: new Date(T0.getTime() - DAY),
  });
  const submitted = await drafts.submit(
    id,
    agentId,
    { submittedAt: new Date(T0.getTime() - DAY), expiresAt },
    new Date(T0.getTime() - DAY),
  );
  if (submitted === null) throw new Error('set-up: submit failed');
}

describe('ClientInviteService races on the real database', () => {
  it('two accepts of one invitation at once: both answer, one member, one credit', async () => {
    await seedAgent('agent-1');
    await waitingInvite('draft-1', 'agent-1');
    const invites = service(new FakeAgentClock(T0));
    const [a, b] = await Promise.all([
      invites.accept(clientClaims(), 'draft-1'),
      invites.accept(clientClaims(), 'draft-1'),
    ]);
    expect(a.firebaseCustomToken).toBe('custom-token-uid-919000000001');
    expect(b.firebaseCustomToken).toBe('custom-token-uid-919000000001');
    expect(await prisma.user.count()).toBe(1);
    expect(await prisma.referralAttribution.count()).toBe(1);
    expect(await prisma.registrationStep.count()).toBe(1);
  });

  it("two agents' invitations for one phone accepted at once: one member, no deadlock", async () => {
    await seedAgent('agent-1');
    await seedAgent('agent-2');
    await waitingInvite('draft-1', 'agent-1');
    await waitingInvite('draft-2', 'agent-2');
    const invites = service(new FakeAgentClock(T0));
    const results = await Promise.allSettled([
      invites.accept(clientClaims(), 'draft-2'),
      invites.accept(clientClaims(), 'draft-1'),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([
      'fulfilled',
      'rejected',
    ]);
    const lost = results.find(
      (r): r is PromiseRejectedResult => r.status === 'rejected',
    );
    expect(['INVITE_UNAVAILABLE', 'ALREADY_MEMBER']).toContain(
      (lost?.reason as { code?: string }).code,
    );
    expect(await prisma.user.count()).toBe(1);
    expect(await prisma.referralAttribution.count()).toBe(1);
    const statuses = await prisma.agentClientDraft.findMany({
      orderBy: { id: 'asc' },
      select: { status: true, closedReason: true },
    });
    expect(statuses.map((s) => s.status).sort()).toEqual([
      'ACCEPTED',
      'EXPIRED',
    ]);
  });

  it('an accept against the expiry: exactly one wins, and the rows agree', async () => {
    await seedAgent('agent-1');
    for (let round = 1; round <= 3; round += 1) {
      const expiresAt = new Date(T0.getTime() + round * 60_000);
      const phone = `+91900000000${round}`;
      await waitingInvite(`draft-${round}`, 'agent-1', expiresAt, phone);
      const invites = service(
        new FakeAgentClock(new Date(expiresAt.getTime() - 1)),
      );
      const [accept, expire] = await Promise.allSettled([
        invites.accept(clientClaims(phone), `draft-${round}`),
        new PrismaAgentClientDraftRepository(prisma).expireDue(
          null,
          expiresAt,
          10,
        ),
      ]);
      const row = await prisma.agentClientDraft.findUniqueOrThrow({
        where: { id: `draft-${round}` },
      });
      if (row.status === 'ACCEPTED') {
        expect(accept.status).toBe('fulfilled');
        expect(expire).toEqual({ status: 'fulfilled', value: [] });
      } else {
        expect(row).toMatchObject({
          status: 'EXPIRED',
          closedReason: 'TIMED_OUT',
        });
        expect(accept).toMatchObject({
          status: 'rejected',
          reason: { code: 'INVITE_UNAVAILABLE' },
        });
        expect(expire).toEqual({
          status: 'fulfilled',
          value: [`draft-${round}`],
        });
      }
      expect(await prisma.user.count({ where: { phone } })).toBe(
        row.status === 'ACCEPTED' ? 1 : 0,
      );
    }
  });
});
