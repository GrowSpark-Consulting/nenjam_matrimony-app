import { AgentPermissionDeniedError } from '../ports/agent-platform-ports';
import {
  NOBODY,
  PARTNER,
  SUPER,
  actorOf,
  makeAdminHarness,
  type AdminHarness,
} from '../testing/agent-admin-harness';
import { T0 } from '../testing/agent-commission-harness';

let h: AdminHarness;
const super_ = actorOf(SUPER);
const REASON = 'member asked for the change';

beforeEach(async () => {
  h = makeAdminHarness();
  await h.seedAgent('ACTIVE', { id: 'agent-1', phoneHash: 'v1:agent-1' });
  await h.seedAgent('ACTIVE', {
    id: 'agent-2',
    phoneHash: 'v1:agent-2',
    phoneE164: '+919000000002',
  });
  await h.seedAttribution(1, { agentId: 'agent-1' });
});

describe('list', () => {
  it('needs attribution.view', async () => {
    await expect(
      h.referralsAdmin.list(actorOf(PARTNER), 'agent-1'),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    await expect(
      h.referralsAdmin.list(actorOf(NOBODY), 'agent-1'),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
  });

  it("shows the agent's referrals newest first, and refuses an unknown agent", async () => {
    await h.seedAttribution(2, { agentId: 'agent-1' });
    await h.seedAttribution(3, { agentId: 'agent-2' });
    const page = await h.referralsAdmin.list(super_, 'agent-1');
    expect(page.items.map((i) => i.id).sort()).toEqual(['attr-1', 'attr-2']);
    await expect(h.referralsAdmin.list(super_, 'nobody')).rejects.toMatchObject(
      {
        code: 'AGENT_NOT_FOUND',
      },
    );
  });

  it('filters by status and review flag, and pages', async () => {
    await h.seedAttribution(2, { agentId: 'agent-1', status: 'REJECTED' });
    await h.attributions.correct('attr-1', 'ACTIVE', { needsReview: true });
    expect(
      (
        await h.referralsAdmin.list(super_, 'agent-1', { status: 'REJECTED' })
      ).items.map((i) => i.id),
    ).toEqual(['attr-2']);
    expect(
      (
        await h.referralsAdmin.list(super_, 'agent-1', { needsReview: true })
      ).items.map((i) => i.id),
    ).toEqual(['attr-1']);
    const first = await h.referralsAdmin.list(super_, 'agent-1', { limit: 1 });
    expect(first.nextCursor).not.toBeNull();
    const second = await h.referralsAdmin.list(super_, 'agent-1', {
      limit: 1,
      cursor: first.nextCursor ?? undefined,
    });
    expect(second.items).toHaveLength(1);
    expect(second.items[0].id).not.toBe(first.items[0].id);
    expect(second.nextCursor).toBeNull();
  });
});

describe('correct', () => {
  it('needs attribution.override', async () => {
    await expect(
      h.referralsAdmin.correct(actorOf(PARTNER), 'attr-1', {
        action: 'REJECT',
        reason: REASON,
      }),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    expect((await h.attributions.findById('attr-1'))?.status).toBe('ACTIVE');
    expect(h.audit.entries).toHaveLength(0);
  });

  it('REASSIGN_AGENT credits another active agent, sets ADMIN_SET, keeps the window', async () => {
    const before = await h.attributions.findById('attr-1');
    const view = await h.referralsAdmin.correct(super_, 'attr-1', {
      action: 'REASSIGN_AGENT',
      agentId: 'agent-2',
      reason: REASON,
    });
    expect(view).toMatchObject({
      agentId: 'agent-2',
      source: 'ADMIN_SET',
      codeId: null,
    });
    expect(view.windowEndsAt).toBe(before?.windowEndsAt.toISOString());
    expect(h.audit.entries.at(-1)).toMatchObject({
      action: 'attribution.correct',
      reason: REASON,
      before: { agentId: 'agent-1' },
      after: { agentId: 'agent-2' },
    });
  });

  it('REASSIGN_AGENT refuses a target that is not active, unknown, or the member themself', async () => {
    await h.agents.update('agent-2', { status: 'SUSPENDED' });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REASSIGN_AGENT',
        agentId: 'agent-2',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'AGENT_STATUS_NOT_ALLOWED' });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REASSIGN_AGENT',
        agentId: 'nobody',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'AGENT_NOT_FOUND' });
    // The target agent's phone is the member's phone.
    await h.seedAgent('ACTIVE', {
      id: 'agent-3',
      phoneHash: 'v1:member-hash-1',
      phoneE164: '+919000000003',
    });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REASSIGN_AGENT',
        agentId: 'agent-3',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'SELF_REFERRAL' });
    expect((await h.attributions.findById('attr-1'))?.agentId).toBe('agent-1');
  });

  it('REJECT and CLEAR_REVIEW change only what they say', async () => {
    await h.attributions.correct('attr-1', 'ACTIVE', { needsReview: true });
    const cleared = await h.referralsAdmin.correct(super_, 'attr-1', {
      action: 'CLEAR_REVIEW',
      reason: REASON,
    });
    expect(cleared).toMatchObject({
      needsReview: false,
      status: 'ACTIVE',
      agentId: 'agent-1',
    });
    const rejected = await h.referralsAdmin.correct(super_, 'attr-1', {
      action: 'REJECT',
      reason: REASON,
    });
    expect(rejected.status).toBe('REJECTED');
  });

  it('a converted referral has a commission and is refused', async () => {
    await h.attributions.correct('attr-1', 'ACTIVE', { status: 'CONVERTED' });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REJECT',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'ATTRIBUTION_CONVERTED' });
  });

  it('unknown referral, bad action and missing agent or reason are refused', async () => {
    await expect(
      h.referralsAdmin.correct(super_, 'nope', {
        action: 'REJECT',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'REFERRAL_NOT_FOUND' });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'DELETE' as never,
        reason: REASON,
      }),
    ).rejects.toMatchObject({ fields: ['action'] });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REASSIGN_AGENT',
        agentId: '',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ fields: ['agentId'] });
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REJECT',
        reason: 'no',
      }),
    ).rejects.toMatchObject({ fields: ['reason'] });
    expect(h.audit.entries).toHaveLength(0);
  });

  it('losing a race throws and writes no audit row', async () => {
    jest.spyOn(h.attributions, 'correct').mockResolvedValueOnce(null);
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REJECT',
        reason: REASON,
      }),
    ).rejects.toMatchObject({ code: 'CONCURRENT_CHANGE' });
    expect(h.audit.entries).toHaveLength(0);
  });

  it('a failed audit write undoes the correction', async () => {
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit down'));
    await expect(
      h.referralsAdmin.correct(super_, 'attr-1', {
        action: 'REJECT',
        reason: REASON,
      }),
    ).rejects.toThrow('audit down');
    expect((await h.attributions.findById('attr-1'))?.status).toBe('ACTIVE');
  });

  it('never exposes a phone number', async () => {
    const view = await h.referralsAdmin.correct(super_, 'attr-1', {
      action: 'CLEAR_REVIEW',
      reason: REASON,
    });
    expect(JSON.stringify(view)).not.toContain('member-hash');
    expect(T0).toBeDefined();
  });
});
