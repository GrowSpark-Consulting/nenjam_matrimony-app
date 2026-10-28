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
  FakeReferralCodeAttemptStore,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

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
    status: 'ACTIVE',
    windowEndsAt: LATER,
    needsReview: false,
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

describe('FakeReferralAttributionRepository paging and scoping', () => {
  const row = (
    id: string,
    agentId: string,
    at: Date,
  ): ReferralAttributionRecord => ({
    id,
    memberId: `m-${id}`,
    agentId,
    codeId: 'code-1',
    source: 'CODE_AT_SIGNUP',
    memberPhoneHash: `h-${id}`,
    attributedAt: at,
    status: 'ACTIVE',
    windowEndsAt: LATER,
    needsReview: false,
  });
  const at = (day: number) => new Date(NOW.getTime() + day * 86_400_000);

  const seeded = async () => {
    const repo = new FakeReferralAttributionRepository();
    await repo.create(row('a', 'agent-1', at(1)));
    await repo.create(row('b', 'agent-1', at(3)));
    await repo.create(row('c', 'agent-1', at(2)));
    await repo.create(row('x', 'agent-2', at(9)));
    return repo;
  };

  it('listPageByAgent is newest first and only for that agent', async () => {
    const repo = await seeded();
    const page = await repo.listPageByAgent('agent-1', { limit: 10 });
    expect(page.map((r) => r.id)).toEqual(['b', 'c', 'a']);
  });

  it('listPageByAgent honours limit and returns rows strictly after the cursor', async () => {
    const repo = await seeded();
    const first = await repo.listPageByAgent('agent-1', { limit: 2 });
    expect(first.map((r) => r.id)).toEqual(['b', 'c']);
    const second = await repo.listPageByAgent('agent-1', {
      limit: 2,
      after: { at: first[1].attributedAt, id: first[1].id },
    });
    expect(second.map((r) => r.id)).toEqual(['a']);
  });

  it('listPageByAgent breaks equal times by id, descending, with no repeats', async () => {
    const repo = new FakeReferralAttributionRepository();
    for (const id of ['p', 'q', 'r'])
      await repo.create(row(id, 'agent-1', at(1)));
    const first = await repo.listPageByAgent('agent-1', { limit: 2 });
    expect(first.map((r) => r.id)).toEqual(['r', 'q']);
    const rest = await repo.listPageByAgent('agent-1', {
      limit: 2,
      after: { at: first[1].attributedAt, id: first[1].id },
    });
    expect(rest.map((r) => r.id)).toEqual(['p']);
  });

  it('findByIdForAgent answers null for another agent\x27s row and for an unknown id alike', async () => {
    const repo = await seeded();
    expect((await repo.findByIdForAgent('a', 'agent-1'))?.id).toBe('a');
    expect(await repo.findByIdForAgent('x', 'agent-1')).toBeNull();
    expect(await repo.findByIdForAgent('nope', 'agent-1')).toBeNull();
  });

  it('returns copies, so a caller cannot edit stored rows', async () => {
    const repo = await seeded();
    const [first] = await repo.listPageByAgent('agent-1', { limit: 1 });
    first.status = 'REJECTED';
    expect((await repo.findByIdForAgent('b', 'agent-1'))?.status).toBe(
      'ACTIVE',
    );
  });
});

describe('FakeReferralCodeAttemptStore', () => {
  const at = (seconds: number) => new Date(NOW.getTime() + seconds * 1000);

  it('counts attempts after the cut-off, and reports the oldest', async () => {
    const store = new FakeReferralCodeAttemptStore();
    await store.record({
      requesterKey: 'ip:1',
      codeKey: 'NMAAAAAA',
      at: at(0),
    });
    await store.record({
      requesterKey: 'ip:1',
      codeKey: 'NMBBBBBB',
      at: at(10),
    });
    await store.record({
      requesterKey: 'ip:2',
      codeKey: 'NMAAAAAA',
      at: at(20),
    });
    expect(await store.window('REQUESTER', 'ip:1', at(-1))).toEqual({
      count: 2,
      oldestAt: at(0),
    });
    expect(await store.window('CODE', 'NMAAAAAA', at(-1))).toEqual({
      count: 2,
      oldestAt: at(0),
    });
  });

  it('an attempt exactly at the cut-off is outside the window', async () => {
    const store = new FakeReferralCodeAttemptStore();
    await store.record({ requesterKey: 'ip:1', codeKey: null, at: at(0) });
    expect(await store.window('REQUESTER', 'ip:1', at(0))).toEqual({
      count: 0,
      oldestAt: null,
    });
  });

  it('keeps the two dimensions apart, and never counts a null code', async () => {
    const store = new FakeReferralCodeAttemptStore();
    await store.record({ requesterKey: 'same', codeKey: null, at: at(0) });
    expect((await store.window('REQUESTER', 'same', at(-1))).count).toBe(1);
    expect((await store.window('CODE', 'same', at(-1))).count).toBe(0);
  });

  it.each(['1.2.3.4', '::1', 'requester:203.0.113.7'])(
    'refuses a raw IP address as the requester key (%p) and stores nothing',
    async (requesterKey) => {
      const store = new FakeReferralCodeAttemptStore();
      await expect(
        store.record({ requesterKey, codeKey: null, at: at(0) }),
      ).rejects.toThrow(RangeError);
      expect(store.size).toBe(0);
    },
  );

  it('accepts an opaque hashed key', async () => {
    const store = new FakeReferralCodeAttemptStore();
    await expect(
      store.record({
        requesterKey: 'requester:v1:ab12',
        codeKey: null,
        at: at(0),
      }),
    ).resolves.toBeUndefined();
    expect(store.size).toBe(1);
  });

  it('an attempt recorded in a failed transaction is undone', async () => {
    const store = new FakeReferralCodeAttemptStore();
    const uow = new FakeAgentUnitOfWork();
    await expect(
      uow.run(async (tx) => {
        await store.record(
          { requesterKey: 'ip:1', codeKey: null, at: at(0) },
          tx,
        );
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(store.size).toBe(0);
  });
});

describe('FakeReferralAttributionRepository phone uniqueness', () => {
  it('refuses a second attribution for the same non-null phone hash', async () => {
    const repo = new FakeReferralAttributionRepository();
    const base = {
      agentId: 'agent-1',
      codeId: 'code-1',
      source: 'CODE_AT_SIGNUP' as const,
      attributedAt: NOW,
      status: 'ACTIVE' as const,
      windowEndsAt: LATER,
      needsReview: false,
    };
    await repo.create({
      ...base,
      id: 'a',
      memberId: 'm1',
      memberPhoneHash: 'h',
    });
    await expect(
      repo.create({ ...base, id: 'b', memberId: 'm2', memberPhoneHash: 'h' }),
    ).rejects.toMatchObject({ reason: 'DUPLICATE_ATTRIBUTION' });
  });

  it('allows several attributions that have no phone hash', async () => {
    const repo = new FakeReferralAttributionRepository();
    const base = {
      agentId: 'agent-1',
      codeId: 'code-1',
      source: 'ENTERED_AT_PAYMENT' as const,
      attributedAt: NOW,
      status: 'ACTIVE' as const,
      windowEndsAt: LATER,
      needsReview: true,
      memberPhoneHash: null,
    };
    await repo.create({ ...base, id: 'a', memberId: 'm1' });
    await expect(
      repo.create({ ...base, id: 'b', memberId: 'm2' }),
    ).resolves.toBeDefined();
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
