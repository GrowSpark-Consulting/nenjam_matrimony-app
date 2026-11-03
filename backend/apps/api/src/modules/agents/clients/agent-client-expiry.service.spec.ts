import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import {
  CLIENT_DETAILS,
  CLIENT_PHONE,
  CLIENT_PHONE_2,
  makeAgentHarness,
  PHONE,
  START,
  UNAPPROVED_PHONE,
  type AgentHarness,
} from '../testing/agent-test-harness';
import { AgentClientExpiryService } from './agent-client-expiry.service';

const DAY = 86_400_000;

async function world() {
  const h = makeAgentHarness();
  await h.seedAgent('ACTIVE');
  const agent = await h.claimsOf(await h.signInAs(PHONE));
  const expiry = new AgentClientExpiryService({
    drafts: h.drafts,
    codes: h.consentCodes,
    uow: h.uow,
    audit: h.audit,
  });
  const add = (phone = CLIENT_PHONE) =>
    h.clients.create(agent, { phone, details: CLIENT_DETAILS });
  return { h, agent, expiry, add };
}

const expiredAudits = (h: AgentHarness) =>
  h.audit.entries.filter((e) => e.action === 'AGENT_CLIENT_DRAFT_EXPIRED');

describe('AgentClientExpiryService.runDailyExpiry', () => {
  it('closes every open draft past its time and deletes its PII, one audit row each', async () => {
    const { h, agent, expiry, add } = await world();
    await add();
    await add(CLIENT_PHONE_2);
    await h.clients.submit(agent, 'draft-2');
    const report = await expiry.runDailyExpiry(
      new Date(START.getTime() + 14 * DAY),
      500,
    );
    expect(report).toEqual({
      expired: 2,
      closedForTerminatedAgents: 0,
      codesPurged: 1,
    });
    for (const id of ['draft-1', 'draft-2']) {
      expect(h.drafts.peek(id)).toMatchObject({
        status: 'EXPIRED',
        closedReason: 'TIMED_OUT',
        phoneSealed: null,
        detailsSealed: null,
      });
    }
    expect(expiredAudits(h)).toEqual([
      {
        actorId: null,
        action: 'AGENT_CLIENT_DRAFT_EXPIRED',
        entity: 'agent_client_draft',
        entityId: 'draft-1',
        metadata: { reason: 'TIMED_OUT' },
      },
      expect.objectContaining({ entityId: 'draft-2' }),
    ]);
  });

  it('leaves what is not due yet', async () => {
    const { h, expiry, add } = await world();
    await add();
    const report = await expiry.runDailyExpiry(
      new Date(START.getTime() + 14 * DAY - 1),
      500,
    );
    expect(report.expired).toBe(0);
    expect(h.drafts.peek('draft-1')?.status).toBe('DRAFT');
  });

  it('catches up after a two-day gap: everything due on either day is closed', async () => {
    const { h, agent, expiry, add } = await world();
    await add();
    h.clock.advance(DAY);
    await add(CLIENT_PHONE_2);
    await h.clients.submit(agent, 'draft-2');
    // draft-1 ran out on day 14, draft-2 on day 15; the job runs on day 16.
    const report = await expiry.runDailyExpiry(
      new Date(START.getTime() + 16 * DAY),
      500,
    );
    expect(report.expired).toBe(2);
  });

  it('is safe to run twice: the second run closes and audits nothing', async () => {
    const { h, expiry, add } = await world();
    await add();
    const at = new Date(START.getTime() + 20 * DAY);
    await expiry.runDailyExpiry(at, 500);
    const audits = h.audit.entries.length;
    await expect(expiry.runDailyExpiry(at, 500)).resolves.toEqual({
      expired: 0,
      closedForTerminatedAgents: 0,
      codesPurged: 0,
    });
    expect(h.audit.entries).toHaveLength(audits);
  });

  it('pages through more than one batch', async () => {
    const { h, expiry } = await world();
    for (let n = 1; n <= 5; n += 1) {
      await h.drafts.create({
        id: `bulk-${n}`,
        agentId: 'agent-1',
        phoneHash: `v1:bulk-${n}`,
        phoneSealed: 'sealed',
        phoneMasked: '+91 90***001',
        displayName: 'Priya S.',
        detailsSealed: 'sealed',
        expiresAt: new Date(START.getTime() + n * 1000),
        createdAt: START,
      });
    }
    const report = await expiry.runDailyExpiry(
      new Date(START.getTime() + DAY),
      2,
    );
    expect(report.expired).toBe(5);
    expect(h.drafts.all().every((d) => d.status === 'EXPIRED')).toBe(true);
  });

  it("closes the open drafts of a TERMINATED agent, not a paused one's", async () => {
    const { h, agent, expiry, add } = await world();
    await add();
    await h.seedAgent('ACTIVE', { id: 'agent-2', phoneE164: UNAPPROVED_PHONE });
    const other = await h.claimsOf(await h.signInAs(UNAPPROVED_PHONE));
    await h.clients.create(other, {
      phone: CLIENT_PHONE_2,
      details: CLIENT_DETAILS,
    });
    await h.clients.submit(agent, 'draft-1');
    await h.agents.update('agent-1', { status: 'TERMINATED' });
    await h.agents.update('agent-2', { status: 'SUSPENDED' });
    const report = await expiry.runDailyExpiry(START, 500);
    expect(report.closedForTerminatedAgents).toBe(1);
    expect(h.drafts.peek('draft-1')).toMatchObject({
      status: 'EXPIRED',
      closedReason: 'AGENT_TERMINATED',
      phoneSealed: null,
    });
    expect(h.drafts.peek('draft-2')?.status).toBe('DRAFT');
    expect(expiredAudits(h)[0].metadata).toEqual({
      reason: 'AGENT_TERMINATED',
    });
  });

  it('purges the code pointers that ran out, keeps the live ones', async () => {
    const { h, expiry } = await world();
    await h.clientProof.send(CLIENT_PHONE);
    h.clock.advance(300_001);
    await h.clientProof.send(CLIENT_PHONE_2);
    const report = await expiry.runDailyExpiry(h.clock.now(), 500);
    expect(report.codesPurged).toBe(1);
    expect(h.consentCodes.size()).toBe(1);
  });

  it('runs with agent.clients_enabled off: PII is never kept past its time', async () => {
    const { h, expiry, add } = await world();
    await add();
    h.settings.remove(AGENT_CLIENTS_ENABLED_KEY);
    await expiry.runDailyExpiry(new Date(START.getTime() + 14 * DAY), 500);
    expect(h.drafts.peek('draft-1')).toMatchObject({
      status: 'EXPIRED',
      detailsSealed: null,
    });
  });

  it('refuses a bad batch size (a programming error)', async () => {
    const { expiry } = await world();
    await expect(expiry.runDailyExpiry(START, 0)).rejects.toThrow(RangeError);
  });

  it('a page that fails rolls back with its audit rows', async () => {
    const { h, expiry, add } = await world();
    await add();
    jest
      .spyOn(h.audit, 'record')
      .mockRejectedValueOnce(new Error('audit unavailable'));
    await expect(
      expiry.runDailyExpiry(new Date(START.getTime() + 14 * DAY), 500),
    ).rejects.toThrow('audit unavailable');
    expect(h.drafts.peek('draft-1')?.status).toBe('DRAFT');
  });
});
