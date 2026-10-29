import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
import { AgentConflictError } from '../ports/agent-data-ports';
import {
  APPROVER,
  NOBODY,
  SEALED_DETAILS,
  SEALED_PAN,
  VIEWER,
  makeAgentAdminHarness,
  type AgentAdminHarness,
} from '../testing/agent-admin-agents-harness';

let h: AgentAdminHarness;
const approver = { userId: APPROVER, context: { requestId: 'req-1' } };
const viewer = { userId: VIEWER };
const REASON = 'Documents checked and match.';

beforeEach(() => {
  h = makeAgentAdminHarness();
});

const statusOf = async (id: string) => (await h.agents.findById(id))?.status;

describe('permissions are checked inside the transaction, first', () => {
  it.each([
    [
      'summary',
      (s: AgentAdminHarness['service']) => s.summary({ userId: NOBODY }),
    ],
    ['list', (s: AgentAdminHarness['service']) => s.list({ userId: NOBODY })],
    [
      'get',
      (s: AgentAdminHarness['service'], id: string) =>
        s.get({ userId: NOBODY }, id),
    ],
  ])('%s needs agent.view', async (_name, call) => {
    const { id } = await h.seedAgent(1);
    await expect(call(h.service, id)).rejects.toBeInstanceOf(
      AgentPermissionDeniedError,
    );
  });

  it.each(['approve', 'reject'] as const)(
    '%s needs agent.approve (agent.view is not enough) and changes nothing',
    async (action) => {
      const { id } = await h.seedAgent(1);
      await expect(
        h.service[action](viewer, id, REASON),
      ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
      expect(await statusOf(id)).toBe('PENDING_APPROVAL');
      expect(h.audit.entries).toHaveLength(0);
      expect(await h.codes.listByAgent(id)).toHaveLength(0);
    },
  );

  it('the permission is checked with the transaction', async () => {
    const { id } = await h.seedAgent(1);
    const spy = jest.spyOn(h.permission, 'assert');
    await h.service.approve(approver, id, REASON);
    expect(spy).toHaveBeenCalledWith(
      APPROVER,
      { module: 'agent', action: 'approve' },
      expect.anything(),
    );
  });
});

describe('approve', () => {
  it('PENDING_APPROVAL -> ACTIVE: approvedAt, the first primary code, an audit row', async () => {
    const { id } = await h.seedAgent(1);
    const view = await h.service.approve(approver, id, REASON);
    expect(view).toMatchObject({
      id,
      status: 'ACTIVE',
      rejectionReason: null,
      approvedAt: '2026-10-29T10:00:00.000Z',
    });
    expect(view.codes).toHaveLength(1);
    expect(view.codes[0]).toMatchObject({ isPrimary: true, isActive: true });
    expect(view.codes[0].code).toMatch(/^NM[2-9A-HJKMNP-Z]{6}$/);
    expect(h.audit.entries).toEqual([
      expect.objectContaining({
        actorId: APPROVER,
        actorType: 'STAFF',
        action: 'agent.approve',
        entity: 'Agent',
        entityId: id,
        reason: REASON,
        before: { status: 'PENDING_APPROVAL' },
        after: { status: 'ACTIVE' },
        context: { requestId: 'req-1' },
      }),
    ]);
    expect(view.statusHistory).toEqual([
      expect.objectContaining({
        from: 'PENDING_APPROVAL',
        to: 'ACTIVE',
        reason: REASON,
      }),
    ]);
  });

  it('a collision with an existing code is retried by the generator', async () => {
    const { id } = await h.seedAgent(1);
    const exists = jest.spyOn(h.codes, 'codeExists');
    exists.mockResolvedValueOnce(true).mockResolvedValueOnce(true);
    const view = await h.service.approve(approver, id, REASON);
    expect(view.codes).toHaveLength(1);
    expect(exists.mock.calls.length).toBeGreaterThanOrEqual(3);
  });

  it('a collision at insert (a race) retries the whole transaction', async () => {
    const { id } = await h.seedAgent(1);
    jest
      .spyOn(h.codes, 'create')
      .mockRejectedValueOnce(new AgentConflictError('DUPLICATE_CODE'));
    const view = await h.service.approve(approver, id, REASON);
    expect(view.status).toBe('ACTIVE');
    expect(view.codes).toHaveLength(1);
    expect(h.audit.entries).toHaveLength(1);
  });

  it('gives up after repeated collisions at insert and changes nothing', async () => {
    const { id } = await h.seedAgent(1);
    jest
      .spyOn(h.codes, 'create')
      .mockRejectedValue(new AgentConflictError('DUPLICATE_CODE'));
    await expect(h.service.approve(approver, id, REASON)).rejects.toMatchObject(
      {
        reason: 'DUPLICATE_CODE',
      },
    );
    expect(await statusOf(id)).toBe('PENDING_APPROVAL');
    expect(h.audit.entries).toHaveLength(0);
  });

  it.each(['ACTIVE', 'SUSPENDED', 'TERMINATED', 'REJECTED'] as const)(
    'is refused from %s with the current status and a refusal',
    async (status) => {
      const { id } = await h.seedAgent(1, status);
      await expect(
        h.service.approve(approver, id, REASON),
      ).rejects.toMatchObject({
        code: 'AGENT_TRANSITION_NOT_ALLOWED',
        agentStatus: status,
      });
      expect(h.audit.entries).toHaveLength(0);
    },
  );

  it('does not issue a second code to an agent that already has one', async () => {
    const { id } = await h.seedAgent(1);
    await h.codes.create({
      id: 'code-old',
      agentId: id,
      code: 'NM7K2P9X',
      isPrimary: true,
      isActive: true,
      createdAt: new Date(),
    });
    const view = await h.service.approve(approver, id, REASON);
    expect(view.codes.map((c) => c.code)).toEqual(['NM7K2P9X']);
  });

  it('a failed audit write rolls back the status and the code', async () => {
    const { id } = await h.seedAgent(1);
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(h.service.approve(approver, id, REASON)).rejects.toThrow(
      'audit down',
    );
    expect(await statusOf(id)).toBe('PENDING_APPROVAL');
    expect(await h.codes.listByAgent(id)).toHaveLength(0);
  });

  it('the audit row is written with the transaction', async () => {
    const { id } = await h.seedAgent(1);
    const spy = jest.spyOn(h.audit, 'record');
    await h.service.approve(approver, id, REASON);
    expect(spy.mock.calls[0][1]).toBeDefined();
  });

  it('an unknown agent is AGENT_NOT_FOUND', async () => {
    await expect(
      h.service.approve(
        approver,
        '11111111-1111-4111-8111-999999999999',
        REASON,
      ),
    ).rejects.toMatchObject({ code: 'AGENT_NOT_FOUND' });
  });
});

describe('reject', () => {
  it('PENDING_APPROVAL -> REJECTED; the reason is kept for the applicant', async () => {
    const { id } = await h.seedAgent(1);
    const view = await h.service.reject(
      approver,
      id,
      'The PAN does not match.',
    );
    expect(view).toMatchObject({
      status: 'REJECTED',
      rejectionReason: 'The PAN does not match.',
    });
    expect(view.codes).toHaveLength(0);
    expect(h.audit.entries[0]).toMatchObject({
      action: 'agent.reject',
      reason: 'The PAN does not match.',
      before: { status: 'PENDING_APPROVAL' },
      after: { status: 'REJECTED' },
    });
  });

  it('is refused from any other status', async () => {
    const { id } = await h.seedAgent(1, 'ACTIVE');
    await expect(h.service.reject(approver, id, REASON)).rejects.toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
      agentStatus: 'ACTIVE',
      refusal: 'TRANSITION_NOT_ALLOWED',
    });
  });

  it('a failed audit write leaves the agent pending', async () => {
    const { id } = await h.seedAgent(1);
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(h.service.reject(approver, id, REASON)).rejects.toThrow(
      'audit down',
    );
    expect(await statusOf(id)).toBe('PENDING_APPROVAL');
    expect((await h.agents.findById(id))?.rejectionReason).toBeNull();
  });
});

describe('the reason', () => {
  it.each(['', '  ', 'ab', 'x'.repeat(501)])(
    '%j is refused before anything happens',
    async (reason) => {
      const { id } = await h.seedAgent(1);
      for (const action of ['approve', 'reject'] as const) {
        await expect(
          h.service[action](approver, id, reason),
        ).rejects.toMatchObject({
          code: 'VALIDATION_FAILED',
          fields: ['reason'],
        });
      }
      expect(await statusOf(id)).toBe('PENDING_APPROVAL');
    },
  );

  it('is trimmed; 3 and 500 characters are allowed', async () => {
    const { id } = await h.seedAgent(1);
    await h.service.reject(approver, id, '  abc  ');
    expect((await h.agents.findById(id))?.rejectionReason).toBe('abc');
    const other = await h.seedAgent(2);
    await expect(
      h.service.approve(approver, other.id, 'x'.repeat(500)),
    ).resolves.toBeDefined();
  });
});

describe('reads', () => {
  it('summary counts every status and leaves the commission numbers null', async () => {
    await h.seedAgent(1);
    await h.seedAgent(2, 'ACTIVE');
    await h.seedAgent(3, 'ACTIVE');
    h.read.referralsNeedingReview = 4;
    await h.payoutDetails.save({
      agentId: (await h.seedAgent(4, 'ACTIVE')).id,
      method: 'UPI',
      detailsSealed: SEALED_DETAILS,
      display: 'r***@okbank',
      verifiedAt: null,
      changedAt: new Date(),
    });
    expect(await h.service.summary(viewer)).toEqual({
      byStatus: {
        PENDING_APPROVAL: 1,
        ACTIVE: 3,
        REJECTED: 0,
        SUSPENDED: 0,
        TERMINATED: 0,
      },
      payoutDetailsAwaitingVerification: 1,
      referralsNeedingReview: 4,
      commissionsReady: null,
      payoutsCreated: null,
    });
  });

  it('lists newest first, with the contract fields, and pages with a cursor', async () => {
    for (let n = 1; n <= 3; n++) await h.seedAgent(n);
    const first = await h.service.list(viewer, { limit: 2 });
    expect(first.items.map((i) => i.name)).toEqual(['Agent 3', 'Agent 2']);
    expect(first.items[0]).toEqual({
      id: expect.any(String) as unknown,
      name: 'Agent 3',
      phoneMasked: '+91 99***999',
      city: 'Madurai',
      state: 'Tamil Nadu',
      status: 'PENDING_APPROVAL',
      createdAt: expect.any(String) as unknown,
      approvedAt: null,
      panOnFile: true,
      panVerified: false,
      payoutDetailsSet: false,
      payoutDetailsVerified: false,
      primaryCode: null,
    });
    expect(first.nextCursor).not.toBeNull();
    const second = await h.service.list(viewer, {
      limit: 2,
      cursor: first.nextCursor ?? undefined,
    });
    expect(second.items.map((i) => i.name)).toEqual(['Agent 1']);
    expect(second.nextCursor).toBeNull();
  });

  it('defaults to 25 and refuses a page size outside 1 to 100', async () => {
    for (let n = 1; n <= 27; n++) await h.seedAgent(n);
    expect((await h.service.list(viewer)).items).toHaveLength(25);
    for (const limit of [0, 101, 1.5]) {
      expect(() => h.service.list(viewer, { limit })).toThrow(
        expect.objectContaining({
          code: 'VALIDATION_FAILED',
          fields: ['limit'],
        }) as Error,
      );
    }
    expect((await h.service.list(viewer, { limit: 100 })).items).toHaveLength(
      27,
    );
  });

  it('a bad cursor is VALIDATION_FAILED', () => {
    expect(() => h.service.list(viewer, { cursor: 'garbage' })).toThrow(
      expect.objectContaining({
        code: 'VALIDATION_FAILED',
        fields: ['cursor'],
      }) as Error,
    );
  });

  it('q finds by exact id, by code, by E.164 phone (every pepper version) or by name prefix', async () => {
    const a = await h.seedAgent(1, 'PENDING_APPROVAL', { name: 'Ravi Kumar' });
    const b = await h.seedAgent(2, 'PENDING_APPROVAL', { name: 'Mala' });
    await h.service.approve(approver, b.id, REASON);
    const code = (await h.codes.listByAgent(b.id))[0].code;
    const ids = async (q: string) =>
      (await h.service.list(viewer, { q })).items.map((i) => i.id);
    expect(await ids(a.id)).toEqual([a.id]);
    expect(await ids(code)).toEqual([b.id]);
    expect(await ids(code.toLowerCase())).toEqual([b.id]);
    expect(code).not.toBe('NM7K2P9X');
    expect(await ids('NM7K2P9X')).toEqual([]);
    expect(await ids(a.phone)).toEqual([a.id]);
    expect(await ids('ravi')).toEqual([a.id]);
    expect(await ids('zz')).toEqual([]);
    // A phone stored under an older pepper version is still found.
    await h.agents.create({
      id: '11111111-1111-4111-8111-000000000077',
      phoneHash: h.hasher.hashAll('PHONE', '+919999999999')[1],
      phoneE164: '+919999999999',
      name: 'Old',
      city: 'C',
      state: 'S',
      panLast4: null,
      panSealed: null,
      createdAt: new Date(),
    });
    h.read.track('11111111-1111-4111-8111-000000000077');
    expect(await ids('+919999999999')).toEqual([
      '11111111-1111-4111-8111-000000000077',
    ]);
  });

  it('filters by status and by name', async () => {
    await h.seedAgent(1, 'PENDING_APPROVAL', { name: 'Ravi' });
    await h.seedAgent(2, 'ACTIVE', { name: 'Raja' });
    const names = async (
      q: Parameters<AgentAdminHarness['service']['list']>[1],
    ) => (await h.service.list(viewer, q)).items.map((i) => i.name);
    expect(await names({ status: 'ACTIVE' })).toEqual(['Raja']);
    expect(await names({ name: 'ra' })).toEqual(['Raja', 'Ravi']);
    expect(await names({ name: 'ra', status: 'PENDING_APPROVAL' })).toEqual([
      'Ravi',
    ]);
  });

  it('the detail is masked: never a sealed value, a full phone, a full PAN or payout details', async () => {
    const { id, phone } = await h.seedAgent(1, 'ACTIVE');
    await h.payoutDetails.save({
      agentId: id,
      method: 'UPI',
      detailsSealed: SEALED_DETAILS,
      display: 'r***@okbank',
      verifiedAt: null,
      changedAt: new Date('2026-10-28T00:00:00.000Z'),
    });
    const detail = await h.service.get(viewer, id);
    expect(detail).toMatchObject({
      phoneMasked: '+91 90***001',
      panLast4: '234F',
      panOnFile: true,
      payoutDetails: {
        method: 'UPI',
        display: 'r***@okbank',
        verifiedAt: null,
      },
      counts: { referrals: 0, needsReview: 0 },
      commissions: null,
    });
    const text = JSON.stringify(detail);
    for (const secret of [
      SEALED_PAN,
      SEALED_DETAILS,
      phone,
      'ABCDE1234F',
      'ravi@okbank',
    ]) {
      expect(text).not.toContain(secret);
    }
    const listText = JSON.stringify(await h.service.list(viewer));
    for (const secret of [SEALED_PAN, SEALED_DETAILS, phone]) {
      expect(listText).not.toContain(secret);
    }
  });

  it('an unknown agent is AGENT_NOT_FOUND', async () => {
    await expect(
      h.service.get(viewer, '11111111-1111-4111-8111-999999999999'),
    ).rejects.toMatchObject({ code: 'AGENT_NOT_FOUND' });
  });
});
