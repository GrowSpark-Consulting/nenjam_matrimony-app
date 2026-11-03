import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import {
  AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY,
  AGENT_CLIENT_DRAFT_LIMIT_KEY,
} from '../settings/agent-program-settings';
import {
  CLIENT_DETAILS,
  CLIENT_DETAILS_SEEN,
  CLIENT_PHONE,
  CLIENT_PHONE_2,
  expectServiceError,
  makeAgentHarness,
  PHONE,
  START,
  UNAPPROVED_PHONE,
  type AgentHarness,
} from '../testing/agent-test-harness';
import type { AgentAccessClaims } from '../auth/agent-access-claims';

const DAY = 86_400_000;
const add = (
  h: AgentHarness,
  claims: AgentAccessClaims,
  phone = CLIENT_PHONE,
) =>
  h.clients.create(claims, {
    phone,
    consentConfirmed: true,
    details: CLIENT_DETAILS,
  });

async function world(
  o: {
    status?: string;
    settings?: Record<string, unknown>;
    agentPhone?: string;
    olderPeppers?: string[];
  } = {},
) {
  const h = makeAgentHarness(o.settings ?? {}, {
    olderPeppers: o.olderPeppers,
  });
  await h.seedAgent(o.status ?? 'ACTIVE', {
    phoneE164: o.agentPhone ?? PHONE,
  });
  const claims = await h.claimsOf(await h.signInAs(o.agentPhone ?? PHONE));
  return { h, claims };
}

/** A second ACTIVE agent and their claims. */
async function otherAgent(h: AgentHarness) {
  await h.seedAgent('ACTIVE', { id: 'agent-2', phoneE164: UNAPPROVED_PHONE });
  return h.claimsOf(await h.signInAs(UNAPPROVED_PHONE));
}

const auditText = (h: AgentHarness) => JSON.stringify(h.audit.entries);

describe('AgentClientDraftService: the switch', () => {
  it.each([
    ['missing', undefined],
    ['false', false],
    ['the string "true"', 'true'],
  ])(
    'with agent.clients_enabled %s every call answers CLIENT_INVITES_DISABLED',
    async (_label, value) => {
      const { h, claims } = await world();
      await add(h, claims);
      if (value === undefined) h.settings.remove(AGENT_CLIENTS_ENABLED_KEY);
      else h.settings.set(AGENT_CLIENTS_ENABLED_KEY, value);
      for (const call of [
        () => add(h, claims, CLIENT_PHONE_2),
        () => h.clients.list(claims),
        () => h.clients.get(claims, 'draft-1'),
        () => h.clients.update(claims, 'draft-1', { details: CLIENT_DETAILS }),
        () => h.clients.discard(claims, 'draft-1'),
        () => h.clients.submit(claims, 'draft-1'),
      ]) {
        await expectServiceError(call(), 'CLIENT_INVITES_DISABLED');
      }
    },
  );

  it('is judged before the agent status (a paused agent also hears it is off)', async () => {
    const { h, claims } = await world({ status: 'SUSPENDED' });
    h.settings.remove(AGENT_CLIENTS_ENABLED_KEY);
    await expectServiceError(add(h, claims), 'CLIENT_INVITES_DISABLED');
  });
});

describe('AgentClientDraftService: who may call what', () => {
  it('SUSPENDED may read but not add, edit, discard or submit', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await h.agents.update('agent-1', { status: 'SUSPENDED' });
    await expect(h.clients.list(claims)).resolves.toMatchObject({
      items: [{ id: 'draft-1' }],
    });
    await expect(h.clients.get(claims, 'draft-1')).resolves.toMatchObject({
      id: 'draft-1',
    });
    for (const call of [
      () => add(h, claims, CLIENT_PHONE_2),
      () => h.clients.update(claims, 'draft-1', { details: CLIENT_DETAILS }),
      () => h.clients.discard(claims, 'draft-1'),
      () => h.clients.submit(claims, 'draft-1'),
    ]) {
      await expectServiceError(call(), 'AGENT_NOT_ACTIVE', {
        agentStatus: 'SUSPENDED',
      });
    }
  });

  it('TERMINATED and PENDING_APPROVAL agents have no client routes at all', async () => {
    for (const status of ['TERMINATED', 'PENDING_APPROVAL']) {
      const { h, claims } = await world({ status });
      await expectServiceError(h.clients.list(claims), 'AGENT_NOT_ACTIVE');
      await expectServiceError(add(h, claims), 'AGENT_NOT_ACTIVE');
    }
  });

  it('an applicant token is refused', async () => {
    const h = makeAgentHarness();
    const claims = await h.claimsOf(await h.signInAs());
    await expectServiceError(add(h, claims), 'UNAUTHORIZED');
  });
});

describe('AgentClientDraftService.create', () => {
  it('stores a DRAFT with the phone and details sealed, and shows it masked', async () => {
    const { h, claims } = await world();
    const view = await add(h, claims);
    expect(view).toEqual({
      id: 'draft-1',
      status: 'DRAFT',
      statusLabel: expect.objectContaining({ en: 'Draft' }) as unknown,
      displayName: 'Priya S.',
      phoneMasked: '+91 90***001',
      details: CLIENT_DETAILS_SEEN,
      missingRequired: [],
      editable: true,
      createdAt: START.toISOString(),
      submittedOn: null,
      expiresOn: '2026-11-11',
      acceptedOn: null,
      referralId: null,
    });
    const row = h.drafts.peek('draft-1')!;
    expect(row.phoneHash).toBe(h.hasher.hash('PHONE', CLIENT_PHONE));
    expect(row.expiresAt).toEqual(new Date(START.getTime() + 14 * DAY));
    expect(row.phoneSealed).not.toContain('9000000001');
    expect(
      h.sealer.open(AGENT_SEAL_PURPOSES.clientPhone, row.phoneSealed!),
    ).toBe(CLIENT_PHONE);
    expect(row.detailsSealed).not.toContain('Priya');
    expect(h.audit.entries).toEqual([
      expect.objectContaining({
        actorId: 'agent-1',
        action: 'AGENT_CLIENT_DRAFT_CREATED',
        entity: 'agent_client_draft',
        entityId: 'draft-1',
      }),
    ]);
    expect(h.clientAccount.count()).toBe(0);
  });

  it('names the bad fields, never their values', async () => {
    const { h, claims } = await world();
    const error = await h.clients
      .create(claims, {
        phone: '98765',
        consentConfirmed: true,
        details: {
          ...CLIENT_DETAILS,
          basicDetails: {
            ...CLIENT_DETAILS.basicDetails,
            firstName: 7,
            gender: 'X',
          },
        },
      })
      .catch((e: unknown) => e);
    expect(error).toMatchObject({
      code: 'VALIDATION_FAILED',
      fields: [
        'phone',
        'details.basicDetails.firstName',
        'details.basicDetails.gender',
      ],
    });
    expect(JSON.stringify(error)).not.toContain('98765');
  });

  it('a phone that is not an approved test number gets OTP_DELIVERY_UNAVAILABLE before anything is looked up', async () => {
    const { h, claims } = await world();
    h.clientAccount.addMember('member-9', UNAPPROVED_PHONE);
    const findMember = jest.spyOn(h.clientAccount, 'findMemberByPhone');
    await expectServiceError(
      add(h, claims, UNAPPROVED_PHONE),
      'OTP_DELIVERY_UNAVAILABLE',
    );
    expect(findMember).not.toHaveBeenCalled();
    expect(h.drafts.all()).toEqual([]);
    expect(h.audit.entries).toEqual([]);
  });

  it('a second open draft for the same phone is CLIENT_DRAFT_EXISTS; another agent may add it', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await expectServiceError(add(h, claims), 'CLIENT_DRAFT_EXISTS');
    await h.clients.submit(claims, 'draft-1');
    await expectServiceError(add(h, claims), 'CLIENT_DRAFT_EXISTS');
    const other = await otherAgent(h);
    await expect(add(h, other)).resolves.toMatchObject({ status: 'DRAFT' });
  });

  it('the limit counts DRAFT and WAITING_FOR_CLIENT; a discard frees a slot', async () => {
    const { h, claims } = await world({
      settings: { [AGENT_CLIENT_DRAFT_LIMIT_KEY]: 1 },
    });
    await add(h, claims);
    await h.clients.submit(claims, 'draft-1');
    await expectServiceError(
      add(h, claims, CLIENT_PHONE_2),
      'CLIENT_DRAFT_LIMIT_REACHED',
    );
    h.settings.set(AGENT_CLIENT_DRAFT_LIMIT_KEY, 2);
    await add(h, claims, CLIENT_PHONE_2);
    h.settings.set(AGENT_CLIENT_DRAFT_LIMIT_KEY, 1);
    await expectServiceError(
      add(h, claims, CLIENT_PHONE_2),
      'CLIENT_DRAFT_EXISTS',
    );
    // Discarding the DRAFT frees its slot: one open (the waiting one) again.
    await h.clients.discard(claims, 'draft-2');
    h.settings.set(AGENT_CLIENT_DRAFT_LIMIT_KEY, 2);
    await expect(add(h, claims, CLIENT_PHONE_2)).resolves.toMatchObject({
      status: 'DRAFT',
    });
  });

  it('two creates at once cannot pass the limit (the agent is locked while counting)', async () => {
    const { h, claims } = await world({
      settings: { [AGENT_CLIENT_DRAFT_LIMIT_KEY]: 1 },
    });
    const results = await Promise.allSettled([
      add(h, claims, CLIENT_PHONE),
      add(h, claims, CLIENT_PHONE_2),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([
      'fulfilled',
      'rejected',
    ]);
    const rejected = results.find((r) => r.status === 'rejected');
    expect(rejected?.reason).toMatchObject({
      code: 'CLIENT_DRAFT_LIMIT_REACHED',
    });
    expect(h.drafts.all()).toHaveLength(1);
  });

  it('an overdue draft is closed first: it holds neither a slot nor the phone', async () => {
    const { h, claims } = await world({
      settings: { [AGENT_CLIENT_DRAFT_LIMIT_KEY]: 1 },
    });
    await add(h, claims);
    h.clock.advance(14 * DAY);
    await expect(add(h, claims)).resolves.toMatchObject({ id: 'draft-2' });
    expect(h.drafts.peek('draft-1')).toMatchObject({
      status: 'EXPIRED',
      closedReason: 'TIMED_OUT',
      phoneSealed: null,
      detailsSealed: null,
    });
    expect(h.audit.entries.map((e) => e.action)).toEqual([
      'AGENT_CLIENT_DRAFT_CREATED',
      'AGENT_CLIENT_DRAFT_EXPIRED',
      'AGENT_CLIENT_DRAFT_CREATED',
    ]);
  });

  describe('a phone that cannot be added: one answer, the reason audited', () => {
    const refusedWith = async (
      h: AgentHarness,
      call: Promise<unknown>,
      reason: string,
    ) => {
      await expectServiceError(call, 'CLIENT_PHONE_UNAVAILABLE');
      const last = h.audit.entries[h.audit.entries.length - 1];
      expect(last).toEqual({
        actorId: 'agent-1',
        action: 'AGENT_CLIENT_DRAFT_REFUSED',
        entity: 'agent_client_draft',
        entityId: null,
        metadata: { reason, step: 'CREATE' },
      });
    };

    it('an existing member (any account row)', async () => {
      const { h, claims } = await world();
      h.clientAccount.addMember('member-1', CLIENT_PHONE);
      await refusedWith(h, add(h, claims), 'MEMBER');
      expect(h.drafts.all()).toEqual([]);
    });

    it('a phone already credited to an agent, under any pepper version', async () => {
      const { h, claims } = await world({ olderPeppers: ['old-pepper'] });
      await h.attributions.create({
        id: 'attribution-x',
        memberId: null,
        agentId: 'agent-1',
        codeId: null,
        source: 'CODE_AT_SIGNUP',
        memberPhoneHash: h.hasher.hashAll('PHONE', CLIENT_PHONE)[1],
        attributedAt: START,
        status: 'ACTIVE',
        windowEndsAt: START,
        needsReview: false,
      });
      await refusedWith(h, add(h, claims), 'CREDITED');
    });

    it("the agent's own phone", async () => {
      const { h, claims } = await world({ agentPhone: CLIENT_PHONE_2 });
      await refusedWith(h, add(h, claims, CLIENT_PHONE_2), 'OWN_PHONE');
    });

    it('a client who rejected this agent before, under any pepper version', async () => {
      const { h, claims } = await world({ olderPeppers: ['old-pepper'] });
      await add(h, claims);
      await h.clients.submit(claims, 'draft-1');
      await h.drafts.markRejected(
        'draft-1',
        h.hasher.hashAll('PHONE', CLIENT_PHONE),
        h.clock.now(),
      );
      await refusedWith(h, add(h, claims), 'REJECTED_BEFORE');
      // The same block when the rejection was stored under the older pepper.
      const { h: h2, claims: c2 } = await world({
        olderPeppers: ['old-pepper'],
      });
      const [, older] = h2.hasher.hashAll('PHONE', CLIENT_PHONE);
      await h2.drafts.create({
        id: 'old-draft',
        agentId: 'agent-1',
        phoneHash: older,
        phoneSealed: 'sealed',
        phoneMasked: '+91 90***001',
        displayName: 'Priya S.',
        detailsSealed: 'sealed',
        expiresAt: new Date(START.getTime() + DAY),
        createdAt: START,
      });
      await h2.drafts.submit(
        'old-draft',
        'agent-1',
        { submittedAt: START, expiresAt: new Date(START.getTime() + DAY) },
        START,
      );
      await h2.drafts.markRejected('old-draft', [older], START);
      await refusedWith(h2, add(h2, c2), 'REJECTED_BEFORE');
    });

    it('another agent may still add a phone this client rejected for someone else', async () => {
      const { h, claims } = await world();
      await add(h, claims);
      await h.clients.submit(claims, 'draft-1');
      await h.drafts.markRejected(
        'draft-1',
        [h.hasher.hash('PHONE', CLIENT_PHONE)],
        h.clock.now(),
      );
      const other = await otherAgent(h);
      await expect(add(h, other)).resolves.toMatchObject({ status: 'DRAFT' });
    });
  });

  it('a missing setting is a 503 naming the key (AgentConfigError)', async () => {
    const { h, claims } = await world();
    h.settings.remove(AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY);
    await expect(add(h, claims)).rejects.toMatchObject({
      name: 'AgentConfigError',
      missing: [AGENT_CLIENT_DRAFT_EXPIRY_DAYS_KEY],
    });
  });
});

describe('AgentClientDraftService.update and discard', () => {
  it('replaces the details and the display name of a DRAFT', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    const view = await h.clients.update(claims, 'draft-1', {
      details: {
        ...CLIENT_DETAILS,
        basicDetails: {
          ...CLIENT_DETAILS.basicDetails,
          firstName: 'Meena',
          lastName: 'Raman',
        },
      },
    });
    expect(view).toMatchObject({
      displayName: 'Meena R.',
      details: { basicDetails: { firstName: 'Meena', lastName: 'Raman' } },
    });
    expect(h.audit.entries[1]).toMatchObject({
      action: 'AGENT_CLIENT_DRAFT_UPDATED',
      metadata: { fields: ['details'] },
    });
  });

  it('is locked once submitted, closed or overdue; another agent sees nothing', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    const other = await otherAgent(h);
    await expectServiceError(
      h.clients.update(other, 'draft-1', { details: CLIENT_DETAILS }),
      'CLIENT_DRAFT_NOT_FOUND',
    );
    await expectServiceError(
      h.clients.discard(other, 'draft-1'),
      'CLIENT_DRAFT_NOT_FOUND',
    );
    await h.clients.submit(claims, 'draft-1');
    await expectServiceError(
      h.clients.update(claims, 'draft-1', { details: CLIENT_DETAILS }),
      'CLIENT_DRAFT_LOCKED',
    );
    await expectServiceError(
      h.clients.discard(claims, 'draft-1'),
      'CLIENT_DRAFT_LOCKED',
    );
    await add(h, claims, CLIENT_PHONE_2);
    h.clock.advance(14 * DAY);
    await expectServiceError(
      h.clients.update(claims, 'draft-2', { details: CLIENT_DETAILS }),
      'CLIENT_DRAFT_LOCKED',
    );
  });

  it('validates the new details', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await expectServiceError(
      h.clients.update(claims, 'draft-1', { details: { firstName: 'A' } }),
      'VALIDATION_FAILED',
    );
  });

  it('discard deletes the DRAFT and audits it', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await h.clients.discard(claims, 'draft-1');
    expect(h.drafts.peek('draft-1')).toBeUndefined();
    await expectServiceError(
      h.clients.get(claims, 'draft-1'),
      'CLIENT_DRAFT_NOT_FOUND',
    );
    expect(h.audit.entries[1]).toMatchObject({
      action: 'AGENT_CLIENT_DRAFT_DISCARDED',
      entityId: 'draft-1',
    });
  });
});

describe('AgentClientDraftService.submit', () => {
  it('locks the draft, restarts its time from now and sends a code to the client', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    h.clock.advance(2 * DAY);
    const send = jest.spyOn(h.otp, 'send');
    const view = await h.clients.submit(claims, 'draft-1');
    expect(view).toMatchObject({
      status: 'WAITING_FOR_CLIENT',
      editable: false,
      details: CLIENT_DETAILS,
      submittedOn: '2026-10-30',
      expiresOn: '2026-11-13',
    });
    expect(send).toHaveBeenCalledWith('AGENT_CLIENT_CONSENT', CLIENT_PHONE);
    expect(h.consentCodes.size()).toBe(1);
    expect(h.audit.entries[1]).toMatchObject({
      action: 'AGENT_CLIENT_DRAFT_SUBMITTED',
      entityId: 'draft-1',
    });
    await expectServiceError(
      h.clients.submit(claims, 'draft-1'),
      'CLIENT_DRAFT_LOCKED',
    );
  });

  it('checks the phone again: one that joined since is refused and the draft stays a DRAFT', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    h.clientAccount.addMember('member-1', CLIENT_PHONE);
    await expectServiceError(
      h.clients.submit(claims, 'draft-1'),
      'CLIENT_PHONE_UNAVAILABLE',
    );
    expect(h.drafts.peek('draft-1')?.status).toBe('DRAFT');
    expect(h.audit.entries[1]).toMatchObject({
      action: 'AGENT_CLIENT_DRAFT_REFUSED',
      metadata: { reason: 'MEMBER', step: 'SUBMIT' },
    });
  });

  it('still succeeds when the code cannot be sent, and logs no phone', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    for (let i = 0; i < 3; i += 1) await h.clientProof.send(CLIENT_PHONE);
    await expect(h.clients.submit(claims, 'draft-1')).resolves.toMatchObject({
      status: 'WAITING_FOR_CLIENT',
    });
    expect(h.clientLog.warn).toHaveBeenCalledTimes(1);
    const line = String(h.clientLog.warn.mock.calls[0][0]);
    expect(line).toContain('draft-1');
    expect(line).not.toContain('9000000001');
  });

  it('an overdue DRAFT cannot be submitted', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    h.clock.advance(14 * DAY);
    await expectServiceError(
      h.clients.submit(claims, 'draft-1'),
      'CLIENT_DRAFT_LOCKED',
    );
  });
});

describe('AgentClientDraftService.list and get', () => {
  it("lists only the agent's drafts, newest first, with a cursor", async () => {
    const { h, claims } = await world();
    await add(h, claims);
    h.clock.advance(1000);
    await add(h, claims, CLIENT_PHONE_2);
    const other = await otherAgent(h);
    await add(h, other);
    const first = await h.clients.list(claims, { limit: 1 });
    expect(first.items.map((i) => i.id)).toEqual(['draft-2']);
    expect(first.nextCursor).not.toBeNull();
    const rest = await h.clients.list(claims, {
      limit: 1,
      cursor: first.nextCursor!,
    });
    expect(rest).toEqual({
      items: [expect.objectContaining({ id: 'draft-1' })],
      nextCursor: null,
    });
  });

  it('filters by the status the agent sees, and shows no details once closed', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await add(h, claims, CLIENT_PHONE_2);
    await h.clients.submit(claims, 'draft-2');
    h.clock.advance(14 * DAY);
    const expired = await h.clients.list(claims, { status: 'EXPIRED' });
    expect(expired.items.map((i) => [i.id, i.details])).toEqual([
      ['draft-2', null],
      ['draft-1', null],
    ]);
    expect((await h.clients.list(claims, { status: 'DRAFT' })).items).toEqual(
      [],
    );
  });

  it('never even opens the sealed details of a draft whose time ran out', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    h.clock.advance(14 * DAY);
    const open = jest.spyOn(h.sealer, 'open');
    await h.clients.list(claims);
    await h.clients.get(claims, 'draft-1');
    expect(
      open.mock.calls.filter(
        ([purpose]) => purpose === AGENT_SEAL_PURPOSES.clientDetails,
      ),
    ).toEqual([]);
  });

  it('refuses a bad status, limit or cursor', async () => {
    const { h, claims } = await world();
    await expectServiceError(
      h.clients.list(claims, { status: 'OPEN', limit: 51, cursor: '!!' }),
      'VALIDATION_FAILED',
      { fields: ['limit', 'status', 'cursor'] },
    );
  });

  it("another agent's draft looks like a missing one", async () => {
    const { h, claims } = await world();
    await add(h, claims);
    const other = await otherAgent(h);
    await expectServiceError(
      h.clients.get(other, 'draft-1'),
      'CLIENT_DRAFT_NOT_FOUND',
    );
    await expect(h.clients.get(claims, 'draft-1')).resolves.toMatchObject({
      id: 'draft-1',
    });
  });
});

describe('AgentClientDraftService: no PII outside the sealed columns', () => {
  it('audit rows and refusals never carry the phone or the names', async () => {
    const { h, claims } = await world();
    await add(h, claims);
    await h.clients.update(claims, 'draft-1', { details: CLIENT_DETAILS });
    await h.clients.submit(claims, 'draft-1');
    h.clientAccount.addMember('member-1', CLIENT_PHONE_2);
    const refused = await add(h, claims, CLIENT_PHONE_2).catch(
      (e: unknown) => e,
    );
    const text = auditText(h) + JSON.stringify(refused) + String(refused);
    for (const secret of ['9000000001', '9000000002', 'Priya', 'Sundaram']) {
      expect(text).not.toContain(secret);
    }
  });
});
