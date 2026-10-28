import {
  AgentConflictError,
  AgentRefreshTokenRecord,
  NewAgentRecord,
  ReferralAttributionRecord,
  ReferralCodeRecord,
} from '../ports/agent-data-ports';
import {
  FakeAgentMemberRead,
  FakeAgentRefreshTokenRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';

const NOW = new Date('2026-10-28T10:00:00.000Z');
const LATER = new Date('2026-11-27T10:00:00.000Z');

const newAgent = (overrides: Partial<NewAgentRecord> = {}): NewAgentRecord => ({
  id: 'agent-1',
  phoneHash: 'phone-hash-1',
  phoneE164: '+919876543210',
  name: 'Ravi Kumar',
  city: 'Chennai',
  state: 'Tamil Nadu',
  panLast4: null,
  panSealed: null,
  createdAt: NOW,
  ...overrides,
});

const conflict = (reason: string): unknown =>
  expect.objectContaining({ name: 'AgentConflictError', reason });

describe('FakeAgentRepository', () => {
  it('creates an agent as PENDING_APPROVAL and finds it by id and phone hash', async () => {
    const repo = new FakeAgentRepository();
    const created = await repo.create(newAgent());
    expect(created).toMatchObject({
      status: 'PENDING_APPROVAL',
      rejectionReason: null,
      approvedAt: null,
      payoutDetailsSet: false,
    });
    await expect(repo.findById('agent-1')).resolves.toEqual(created);
    await expect(repo.findByPhoneHash('phone-hash-1')).resolves.toEqual(
      created,
    );
    await expect(repo.findById('nope')).resolves.toBeNull();
  });

  it('refuses a reused phone hash or id', async () => {
    const repo = new FakeAgentRepository();
    await repo.create(newAgent());
    await expect(repo.create(newAgent({ id: 'agent-2' }))).rejects.toEqual(
      conflict('DUPLICATE_PHONE_HASH'),
    );
    await expect(repo.create(newAgent({ phoneHash: 'other' }))).rejects.toEqual(
      conflict('DUPLICATE_ID'),
    );
  });

  it('applies updates, and a returned row cannot edit the store', async () => {
    const repo = new FakeAgentRepository();
    const created = await repo.create(newAgent());
    created.name = 'Hacked';
    await repo.update('agent-1', { status: 'ACTIVE', approvedAt: NOW });
    await expect(repo.findById('agent-1')).resolves.toMatchObject({
      name: 'Ravi Kumar',
      status: 'ACTIVE',
      approvedAt: NOW,
    });
    await expect(repo.update('nope', { name: 'x' })).rejects.toThrow();
  });
});

describe('FakeReferralCodeRepository', () => {
  const code = (o: Partial<ReferralCodeRecord> = {}): ReferralCodeRecord => ({
    id: 'code-1',
    agentId: 'agent-1',
    code: 'NM7K2P9X',
    isPrimary: true,
    isActive: true,
    createdAt: NOW,
    ...o,
  });

  it('finds by code, lists by agent and reports existence', async () => {
    const repo = new FakeReferralCodeRepository();
    await repo.create(code());
    await repo.create(
      code({ id: 'code-2', code: 'NM2222AA', isPrimary: false }),
    );
    await repo.create(
      code({ id: 'code-3', agentId: 'agent-2', code: 'NM3333BB' }),
    );
    expect((await repo.findByCode('NM7K2P9X'))?.id).toBe('code-1');
    expect(await repo.findByCode('NMNOPE')).toBeNull();
    expect((await repo.listByAgent('agent-1')).map((c) => c.id)).toEqual([
      'code-1',
      'code-2',
    ]);
    expect(await repo.codeExists('NM2222AA')).toBe(true);
    expect(await repo.codeExists('NMNOPE')).toBe(false);
  });

  it('refuses a duplicate code and a second primary code for one agent', async () => {
    const repo = new FakeReferralCodeRepository();
    await repo.create(code());
    await expect(repo.create(code({ id: 'code-2' }))).rejects.toEqual(
      conflict('DUPLICATE_CODE'),
    );
    await expect(
      repo.create(code({ id: 'code-2', code: 'NM2222AA' })),
    ).rejects.toEqual(conflict('DUPLICATE_PRIMARY_CODE'));
  });
});

describe('FakeAgentRefreshTokenRepository', () => {
  const token = (
    o: Partial<AgentRefreshTokenRecord> = {},
  ): AgentRefreshTokenRecord => ({
    id: 't1',
    agentId: 'agent-1',
    tokenHash: 'h1',
    expiresAt: LATER,
    revokedAt: null,
    createdAt: NOW,
    ...o,
  });

  it('stores and finds by hash', async () => {
    const repo = new FakeAgentRefreshTokenRepository();
    await repo.create(token());
    expect((await repo.findByHash('h1'))?.id).toBe('t1');
    expect(await repo.findByHash('nope')).toBeNull();
  });

  it('rotate revokes the current token and stores the next', async () => {
    const repo = new FakeAgentRefreshTokenRepository();
    await repo.create(token());
    await repo.rotate('t1', token({ id: 't2', tokenHash: 'h2' }), NOW);
    expect((await repo.findByHash('h1'))?.revokedAt).toEqual(NOW);
    expect((await repo.findByHash('h2'))?.revokedAt).toBeNull();
  });

  it('rotate on an already-revoked token fails and stores nothing', async () => {
    const repo = new FakeAgentRefreshTokenRepository();
    await repo.create(token());
    await repo.rotate('t1', token({ id: 't2', tokenHash: 'h2' }), NOW);
    await expect(
      repo.rotate('t1', token({ id: 't3', tokenHash: 'h3' }), NOW),
    ).rejects.toEqual(conflict('ALREADY_REVOKED'));
    expect(await repo.findByHash('h3')).toBeNull();
  });

  it("revokeAllForAgent revokes only that agent's active tokens and counts them", async () => {
    const repo = new FakeAgentRefreshTokenRepository();
    await repo.create(token());
    await repo.create(token({ id: 't2', tokenHash: 'h2' }));
    await repo.create(token({ id: 't3', tokenHash: 'h3', agentId: 'agent-2' }));
    await repo.rotate('t2', token({ id: 't4', tokenHash: 'h4' }), NOW);
    expect(await repo.revokeAllForAgent('agent-1', NOW)).toBe(2);
    expect((await repo.findByHash('h3'))?.revokedAt).toBeNull();
    expect(await repo.revokeAllForAgent('agent-1', NOW)).toBe(0);
  });
});

describe('FakeReferralAttributionRepository', () => {
  const attribution = (
    o: Partial<ReferralAttributionRecord> = {},
  ): ReferralAttributionRecord => ({
    id: 'attr-1',
    memberId: 'member-1',
    agentId: 'agent-1',
    codeId: 'code-1',
    source: 'CODE_AT_SIGNUP',
    memberPhoneHash: 'member-hash',
    attributedAt: NOW,
    ...o,
  });

  it('allows one attribution per member', async () => {
    const repo = new FakeReferralAttributionRepository();
    await repo.create(attribution());
    await expect(
      repo.create(attribution({ id: 'attr-2', agentId: 'agent-2' })),
    ).rejects.toEqual(conflict('DUPLICATE_ATTRIBUTION'));
    expect((await repo.findByMemberId('member-1'))?.agentId).toBe('agent-1');
    expect(await repo.findByMemberId('other')).toBeNull();
  });

  it('lists by agent and reports credited phone hashes', async () => {
    const repo = new FakeReferralAttributionRepository();
    await repo.create(attribution());
    await repo.create(
      attribution({
        id: 'attr-2',
        memberId: 'member-2',
        memberPhoneHash: null,
      }),
    );
    expect(await repo.listByAgent('agent-1')).toHaveLength(2);
    expect(await repo.listByAgent('agent-9')).toHaveLength(0);
    expect(await repo.isPhoneHashCredited('member-hash')).toBe(true);
    expect(await repo.isPhoneHashCredited('unknown')).toBe(false);
  });
});

describe('FakeAgentMemberRead', () => {
  it('returns copies and null for unknown members', async () => {
    const port = new FakeAgentMemberRead();
    port.add(
      {
        memberId: 'm1',
        phoneHash: 'h',
        signedUpAt: NOW,
        hasPaid: false,
      },
      {
        firstName: 'Priya',
        phoneE164: '+919876543210',
        age: 27,
        city: 'Madurai',
        signedUpAt: NOW,
        stage: 'REGISTERED',
        profileCompletenessPct: 40,
      },
    );
    const member = await port.getMember('m1');
    member!.hasPaid = true;
    expect((await port.getMember('m1'))?.hasPaid).toBe(false);
    expect((await port.getReferralViewFields('m1'))?.city).toBe('Madurai');
    expect(await port.getMember('nope')).toBeNull();
    expect(await port.getReferralViewFields('nope')).toBeNull();
  });
});

describe('AgentConflictError', () => {
  it('carries its reason', () => {
    const error = new AgentConflictError('DUPLICATE_CODE');
    expect(error.reason).toBe('DUPLICATE_CODE');
    expect(error).toBeInstanceOf(Error);
  });
});
