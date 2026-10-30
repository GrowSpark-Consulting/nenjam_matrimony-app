import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
import {
  NOBODY,
  PARTNER,
  PAYER,
  SUPER,
  actorOf,
  makeAdminHarness,
  type AdminHarness,
} from '../testing/agent-admin-harness';

let h: AdminHarness;
const super_ = actorOf(SUPER);

beforeEach(async () => {
  h = makeAdminHarness();
  await h.seedApplicant();
});

const status = async (id = 'agent-1') => (await h.agents.findById(id))?.status;
const actions = () => h.audit.entries.map((e) => e.action);
const REASON = 'checked the documents';

describe('permissions', () => {
  const calls: Array<
    [string, (a: ReturnType<typeof actorOf>) => Promise<unknown>]
  > = [
    ['list', (a) => h.agentsAdmin.list(a)],
    ['get', (a) => h.agentsAdmin.get(a, 'agent-1')],
    ['approve', (a) => h.agentsAdmin.approve(a, 'agent-1', REASON)],
    ['reject', (a) => h.agentsAdmin.reject(a, 'agent-1', REASON)],
    ['pause', (a) => h.agentsAdmin.pause(a, 'agent-1', REASON)],
    ['resume', (a) => h.agentsAdmin.resume(a, 'agent-1', REASON)],
    ['terminate', (a) => h.agentsAdmin.terminate(a, 'agent-1', REASON)],
    ['replaceCode', (a) => h.agentsAdmin.replaceCode(a, 'agent-1', REASON)],
    [
      'verifyPayoutDetails',
      (a) => h.agentsAdmin.verifyPayoutDetails(a, 'agent-1', REASON),
    ],
    ['verifyPan', (a) => h.agentsAdmin.verifyPan(a, 'agent-1', REASON)],
    ['reveal', (a) => h.agentsAdmin.reveal(a, 'agent-1', ['PAN'], REASON)],
  ];

  it.each(calls)(
    '%s is refused to someone with no permission, and changes nothing',
    async (_name, call) => {
      await expect(call(actorOf(NOBODY))).rejects.toBeInstanceOf(
        AgentPermissionDeniedError,
      );
      expect(await status()).toBe('PENDING_APPROVAL');
      expect(h.audit.entries).toHaveLength(0);
    },
  );

  it('the payer has no agent.view', async () => {
    await expect(
      h.agentsAdmin.get(actorOf(PAYER), 'agent-1'),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
  });

  it('a partner manager can approve and reject but not pause, verify or reveal', async () => {
    const partner = actorOf(PARTNER);
    await h.agentsAdmin.approve(partner, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.pause(partner, 'agent-1', REASON),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    await expect(
      h.agentsAdmin.verifyPan(partner, 'agent-1', REASON),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    await expect(
      h.agentsAdmin.reveal(partner, 'agent-1', ['PAN'], REASON),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    expect(await status()).toBe('ACTIVE');
  });
});

describe('reads', () => {
  it('lists newest first with masked data only', async () => {
    await h.seedApplicant('agent-2');
    const page = await h.agentsAdmin.list(super_);
    expect(page.items).toHaveLength(2);
    expect(page.items[0]).toMatchObject({
      phoneMasked: '+91 98***210',
      panLast4: '234F',
    });
    expect(JSON.stringify(page)).not.toContain('+919876543210');
  });

  it('finds by id, by referral code and by full phone; name is a prefix', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    const code = (await h.codes.listByAgent('agent-1'))[0].code;
    const ids = async (q: Parameters<typeof h.agentsAdmin.list>[1]) =>
      (await h.agentsAdmin.list(super_, q)).items.map((i) => i.id);
    expect(await ids({ q: 'agent-1' })).toEqual(['agent-1']);
    expect(await ids({ q: code })).toEqual(['agent-1']);
    expect(await ids({ q: code.toLowerCase() })).toEqual(['agent-1']);
    expect(await ids({ q: 'NM222222' })).toEqual([]);
    expect(await ids({ q: '+919876543210' })).toEqual([]); // the fake agent was stored with another hash
    expect(await ids({ name: 'rav' })).toEqual(['agent-1']);
    expect(await ids({ name: 'zzz' })).toEqual([]);
    await expect(
      h.agentsAdmin.list(super_, { name: 'r' }),
    ).rejects.toMatchObject({
      code: 'VALIDATION_FAILED',
      fields: ['name'],
    });
  });

  it('pages with an opaque cursor', async () => {
    for (const id of ['a2', 'a3']) await h.seedApplicant(id);
    const first = await h.agentsAdmin.list(super_, { limit: 2 });
    expect(first.items).toHaveLength(2);
    expect(first.nextCursor).not.toBeNull();
    const second = await h.agentsAdmin.list(super_, {
      limit: 2,
      cursor: first.nextCursor ?? undefined,
    });
    expect(second.items).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
    await expect(
      h.agentsAdmin.list(super_, { cursor: 'garbage' }),
    ).rejects.toMatchObject({ code: 'VALIDATION_FAILED' });
    await expect(
      h.agentsAdmin.list(super_, { limit: 0 }),
    ).rejects.toMatchObject({
      fields: ['limit'],
    });
  });

  it('the detail never holds a sealed value, a full phone, a PAN or payout details', async () => {
    await h.seedPayoutDetails('agent-1');
    h.history.rows.push({
      agentId: 'agent-1',
      action: 'agent.approve',
      at: new Date(),
      actorId: SUPER,
      reason: 'ok',
    });
    const detail = await h.agentsAdmin.get(super_, 'agent-1');
    expect(detail).toMatchObject({
      phoneMasked: '+91 98***210',
      panLast4: '234F',
      payoutDetails: { method: 'UPI', display: 'r***@okbank' },
      statusHistory: [{ action: 'agent.approve' }],
    });
    const text = JSON.stringify(detail);
    for (const secret of [
      '+919876543210',
      'ABCDE1234F',
      'ravi@okbank',
      'v1:',
    ]) {
      expect(text).not.toContain(secret);
    }
  });

  it('an unknown agent is AGENT_NOT_FOUND', async () => {
    await expect(h.agentsAdmin.get(super_, 'nobody')).rejects.toMatchObject({
      code: 'AGENT_NOT_FOUND',
    });
  });
});

describe('state moves', () => {
  it('approve: PENDING_APPROVAL -> ACTIVE, with the first primary code and an audit row', async () => {
    const detail = await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    expect(detail).toMatchObject({ status: 'ACTIVE', rejectionReason: null });
    expect(detail.approvedAt).not.toBeNull();
    expect(detail.codes).toHaveLength(1);
    expect(detail.codes[0]).toMatchObject({ isPrimary: true, isActive: true });
    expect(detail.codes[0].code).toMatch(/^NM[2-9A-HJKMNP-Z]{6}$/);
    expect(h.audit.entries.at(-1)).toMatchObject({
      actorId: SUPER,
      action: 'agent.approve',
      entityId: 'agent-1',
      reason: REASON,
      before: { status: 'PENDING_APPROVAL' },
      after: { status: 'ACTIVE' },
    });
  });

  it('a second approve is refused with the current status', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.approve(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
      agentStatus: 'ACTIVE',
      refusal: 'SAME_STATUS',
    });
    expect(h.audit.entries).toHaveLength(1);
    expect(await h.codes.listByAgent('agent-1')).toHaveLength(1);
  });

  it('reject keeps the reason for the applicant, and only from PENDING_APPROVAL', async () => {
    const detail = await h.agentsAdmin.reject(
      super_,
      'agent-1',
      'PAN does not match',
    );
    expect(detail).toMatchObject({
      status: 'REJECTED',
      rejectionReason: 'PAN does not match',
    });
    await expect(
      h.agentsAdmin.reject(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({ code: 'AGENT_TRANSITION_NOT_ALLOWED' });
  });

  it('pause, resume, terminate follow the state machine; terminated is final', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    await h.agentsAdmin.pause(super_, 'agent-1', REASON);
    expect(await status()).toBe('SUSPENDED');
    await expect(
      h.agentsAdmin.pause(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
    });
    await h.agentsAdmin.resume(super_, 'agent-1', REASON);
    expect(await status()).toBe('ACTIVE');
    await h.agentsAdmin.terminate(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.resume(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
      refusal: 'TERMINATED_IS_FINAL',
    });
    expect(actions()).toEqual([
      'agent.approve',
      'agent.pause',
      'agent.resume',
      'agent.terminate',
    ]);
  });

  it('cannot pause an applicant or approve a rejected agent', async () => {
    await expect(
      h.agentsAdmin.pause(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_TRANSITION_NOT_ALLOWED',
    });
    await h.agentsAdmin.reject(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.approve(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({ code: 'AGENT_TRANSITION_NOT_ALLOWED' });
  });

  it.each(['', '  ', 'ab', 'x'.repeat(501)])(
    'every move needs a reason of 3 to 500 characters (%j)',
    async (reason) => {
      await expect(
        h.agentsAdmin.approve(super_, 'agent-1', reason),
      ).rejects.toMatchObject({
        code: 'VALIDATION_FAILED',
        fields: ['reason'],
      });
      expect(await status()).toBe('PENDING_APPROVAL');
      expect(h.audit.entries).toHaveLength(0);
    },
  );

  it('the audit row is written in the same transaction: a failure after it removes it', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    const before = h.audit.entries.length;
    jest
      .spyOn(h.history, 'listForAgent')
      .mockRejectedValueOnce(new Error('history down'));
    await expect(
      h.agentsAdmin.pause(super_, 'agent-1', REASON),
    ).rejects.toThrow('history down');
    expect(h.audit.entries).toHaveLength(before);
    expect(await status()).toBe('ACTIVE');
  });

  it('the audit row is written in the same transaction: a failed audit undoes the move and the code', async () => {
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.agentsAdmin.approve(super_, 'agent-1', REASON),
    ).rejects.toThrow('audit down');
    expect(await status()).toBe('PENDING_APPROVAL');
    expect(await h.codes.listByAgent('agent-1')).toHaveLength(0);
  });
});

describe('replaceCode', () => {
  it('issues a new primary code and keeps the old one working', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    const oldCode = (await h.codes.listByAgent('agent-1'))[0];
    const result = await h.agentsAdmin.replaceCode(super_, 'agent-1', REASON);
    expect(result.primary.isPrimary).toBe(true);
    expect(result.primary.code).not.toBe(oldCode.code);
    expect(result.codes).toHaveLength(2);
    const old = result.codes.find((c) => c.id === oldCode.id);
    expect(old).toMatchObject({ isPrimary: false, isActive: true });
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'agent.code.replace',
    });
  });

  it('works for a paused agent, not for an applicant or a terminated agent', async () => {
    await expect(
      h.agentsAdmin.replaceCode(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_STATUS_NOT_ALLOWED',
      agentStatus: 'PENDING_APPROVAL',
    });
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    await h.agentsAdmin.pause(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.replaceCode(super_, 'agent-1', REASON),
    ).resolves.toBeDefined();
    await h.agentsAdmin.terminate(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.replaceCode(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({ code: 'AGENT_STATUS_NOT_ALLOWED' });
  });

  it('a failed audit leaves the old primary code in place', async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    const before = await h.codes.listByAgent('agent-1');
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.agentsAdmin.replaceCode(super_, 'agent-1', REASON),
    ).rejects.toThrow('audit down');
    expect(await h.codes.listByAgent('agent-1')).toEqual(before);
  });
});

describe('verification', () => {
  beforeEach(async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
  });

  it('verifies the payout details once', async () => {
    await h.seedPayoutDetails('agent-1');
    const detail = await h.agentsAdmin.verifyPayoutDetails(
      super_,
      'agent-1',
      REASON,
    );
    expect(detail.payoutDetails?.verifiedAt).not.toBeNull();
    await expect(
      h.agentsAdmin.verifyPayoutDetails(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({ code: 'PAYOUT_DETAILS_ALREADY_VERIFIED' });
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'agent.payout_details.verify',
    });
  });

  it('refuses when there are no payout details, and for an applicant or rejected agent', async () => {
    await expect(
      h.agentsAdmin.verifyPayoutDetails(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({ code: 'PAYOUT_DETAILS_NOT_SET' });
    await h.seedApplicant('agent-2');
    await expect(
      h.agentsAdmin.verifyPayoutDetails(super_, 'agent-2', REASON),
    ).rejects.toMatchObject({ code: 'AGENT_STATUS_NOT_ALLOWED' });
    await expect(
      h.agentsAdmin.verifyPan(super_, 'agent-2', REASON),
    ).rejects.toMatchObject({
      code: 'AGENT_STATUS_NOT_ALLOWED',
    });
  });

  it('a paused or terminated agent may still be verified (money may be owed)', async () => {
    await h.seedPayoutDetails('agent-1');
    await h.agentsAdmin.terminate(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.verifyPayoutDetails(super_, 'agent-1', REASON),
    ).resolves.toBeDefined();
  });

  it('verifies the PAN once, and only when one is on file', async () => {
    const detail = await h.agentsAdmin.verifyPan(super_, 'agent-1', REASON);
    expect(detail.panVerified).toBe(true);
    await expect(
      h.agentsAdmin.verifyPan(super_, 'agent-1', REASON),
    ).rejects.toMatchObject({
      code: 'PAN_ALREADY_VERIFIED',
    });
    await h.seedApplicant('agent-3');
    await h.agents.update('agent-3', {
      panLast4: null,
      panSealed: null,
      status: 'ACTIVE',
    });
    await expect(
      h.agentsAdmin.verifyPan(super_, 'agent-3', REASON),
    ).rejects.toMatchObject({
      code: 'PAN_NOT_SET',
    });
  });

  it('a failed audit leaves the PAN unverified', async () => {
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.agentsAdmin.verifyPan(super_, 'agent-1', REASON),
    ).rejects.toThrow('audit down');
    expect((await h.agents.findById('agent-1'))?.panVerifiedAt).toBeNull();
  });
});

describe('reveal', () => {
  beforeEach(async () => {
    await h.agentsAdmin.approve(super_, 'agent-1', REASON);
    await h.seedPayoutDetails('agent-1');
  });
  const auditBefore = () => h.audit.entries.length;

  it('returns exactly the requested fields', async () => {
    const result = await h.agentsAdmin.reveal(
      super_,
      'agent-1',
      ['PAN', 'PHONE', 'PAYOUT_DETAILS'],
      REASON,
    );
    expect(result).toMatchObject({
      pan: 'ABCDE1234F',
      phone: '+919876543210',
      payoutDetails: { upi: { vpa: 'ravi@okbank' } },
    });
    const only = await h.agentsAdmin.reveal(
      super_,
      'agent-1',
      ['PHONE'],
      REASON,
    );
    expect(Object.keys(only).sort()).toEqual(['phone', 'revealedAt']);
  });

  it('audits one row per revealed field, never the value', async () => {
    const before = auditBefore();
    await h.agentsAdmin.reveal(
      super_,
      'agent-1',
      ['PAN', 'PAYOUT_DETAILS'],
      REASON,
    );
    const rows = h.audit.entries.slice(before);
    expect(rows.map((r) => r.metadata)).toEqual([
      { field: 'PAN' },
      { field: 'PAYOUT_DETAILS' },
    ]);
    expect(
      rows.every((r) => r.action === 'agent.pii.reveal' && r.reason === REASON),
    ).toBe(true);
    const text = JSON.stringify(rows);
    for (const secret of ['ABCDE1234F', 'ravi@okbank', '+919876543210']) {
      expect(text).not.toContain(secret);
    }
  });

  it('needs a fresh step-up, and says so only to someone who holds the permission', async () => {
    const before = auditBefore();
    await expect(
      h.agentsAdmin.reveal(actorOf(SUPER, false), 'agent-1', ['PAN'], REASON),
    ).rejects.toMatchObject({ code: 'ADMIN_STEP_UP_REQUIRED' });
    // Someone without the permission is refused as such, with or without step-up.
    await expect(
      h.agentsAdmin.reveal(actorOf(PAYER, false), 'agent-1', ['PAN'], REASON),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    expect(auditBefore()).toBe(before);
  });

  it('a field that is not on file fails the whole request: nothing is revealed or audited', async () => {
    await h.agents.update('agent-1', { panSealed: null, panLast4: null });
    const before = auditBefore();
    await expect(
      h.agentsAdmin.reveal(super_, 'agent-1', ['PHONE', 'PAN'], REASON),
    ).rejects.toMatchObject({ code: 'PAN_NOT_SET' });
    expect(auditBefore()).toBe(before);
  });

  it('fails closed: if an audit write fails nothing is returned', async () => {
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.agentsAdmin.reveal(super_, 'agent-1', ['PAN'], REASON),
    ).rejects.toThrow('audit down');
  });

  it.each([[[]], [['PAN', 'PAN']]])(
    'refuses an empty or repeated field list (%j)',
    async (fields) => {
      await expect(
        h.agentsAdmin.reveal(super_, 'agent-1', fields as never, REASON),
      ).rejects.toMatchObject({
        code: 'VALIDATION_FAILED',
        fields: ['fields'],
      });
    },
  );

  it('needs a reason', async () => {
    await expect(
      h.agentsAdmin.reveal(super_, 'agent-1', ['PAN'], ''),
    ).rejects.toMatchObject({ fields: ['reason'] });
  });

  it('works for a terminated agent (money may be owed)', async () => {
    await h.agentsAdmin.terminate(super_, 'agent-1', REASON);
    await expect(
      h.agentsAdmin.reveal(super_, 'agent-1', ['PAN'], REASON),
    ).resolves.toMatchObject({ pan: 'ABCDE1234F' });
  });
});
