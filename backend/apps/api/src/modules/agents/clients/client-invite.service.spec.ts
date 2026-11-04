import type { AgentAccessClaims } from '../auth/agent-access-claims';
import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import { REFERRAL_CREDIT_WINDOW_DAYS_KEY } from '../settings/agent-program-settings';
import {
  CLIENT_DETAILS,
  CLIENT_DETAILS_SEEN,
  CLIENT_PHONE,
  CLIENT_PHONE_2,
  CREDIT_WINDOW_DAYS,
  expectServiceError,
  makeAgentHarness,
  PHONE,
  START,
  UNAPPROVED_PHONE,
  type AgentHarness,
} from '../testing/agent-test-harness';

const DAY = 86_400_000;

async function world(o: { olderPeppers?: string[] } = {}) {
  const h = makeAgentHarness({}, { olderPeppers: o.olderPeppers });
  await h.seedAgent('ACTIVE');
  const agent = await h.claimsOf(await h.signInAs(PHONE));
  return { h, agent };
}

/** A second ACTIVE agent ("Meena Raman") and their claims. */
async function secondAgent(h: AgentHarness) {
  await h.seedAgent('ACTIVE', {
    id: 'agent-2',
    phoneE164: UNAPPROVED_PHONE,
    name: 'Meena Raman',
  });
  return h.claimsOf(await h.signInAs(UNAPPROVED_PHONE));
}

/** The agent adds and submits a client: an invitation waiting for her. */
async function invite(
  h: AgentHarness,
  agent: AgentAccessClaims,
  phone = CLIENT_PHONE,
): Promise<string> {
  const draft = await h.clients.create(agent, {
    phone,
    consentConfirmed: true,
    details: CLIENT_DETAILS,
  });
  await h.clients.submit(agent, draft.id);
  return draft.id;
}

const signedIn = async (h: AgentHarness, phone = CLIENT_PHONE) =>
  h.clientClaimsOf(await h.clientSignIn(phone));

describe('ClientInviteService: the switch', () => {
  it('every call answers CLIENT_INVITES_DISABLED unless agent.clients_enabled is true', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    for (const value of [undefined, false, 'true', 1]) {
      if (value === undefined) h.settings.remove(AGENT_CLIENTS_ENABLED_KEY);
      else h.settings.set(AGENT_CLIENTS_ENABLED_KEY, value);
      for (const call of [
        () => h.clientInvites.requestCode(CLIENT_PHONE),
        () => h.clientInvites.verifyCode(CLIENT_PHONE, '123456'),
        () => h.clientInvites.listInvites(client),
        () => h.clientInvites.accept(client, id),
        () => h.clientInvites.reject(client, id),
      ]) {
        await expectServiceError(call(), 'CLIENT_INVITES_DISABLED');
      }
    }
  });
});

describe('ClientInviteService: the code and the client token', () => {
  it('sends a code to an approved test number, the same answer invited or not', async () => {
    const { h, agent } = await world();
    await invite(h, agent);
    const invited = await h.clientInvites.requestCode(CLIENT_PHONE);
    const notInvited = await h.clientInvites.requestCode(CLIENT_PHONE_2);
    expect(invited).toEqual({ expiresInSeconds: 300, resendAfterSeconds: 30 });
    expect(notInvited).toEqual(invited);
  });

  it('every other number gets OTP_DELIVERY_UNAVAILABLE; a malformed one VALIDATION_FAILED', async () => {
    const { h } = await world();
    await expectServiceError(
      h.clientInvites.requestCode(UNAPPROVED_PHONE),
      'OTP_DELIVERY_UNAVAILABLE',
    );
    await expectServiceError(
      h.clientInvites.requestCode('98765'),
      'VALIDATION_FAILED',
      { fields: ['phone'] },
    );
  });

  it('asking too often is RATE_LIMITED with the wait', async () => {
    const { h } = await world();
    for (let i = 0; i < 3; i += 1)
      await h.clientInvites.requestCode(CLIENT_PHONE);
    await expectServiceError(
      h.clientInvites.requestCode(CLIENT_PHONE),
      'RATE_LIMITED',
      { retryAfterSeconds: 600 },
    );
  });

  it('the right code gives a CLIENT token whose subject is the sealed phone', async () => {
    const { h } = await world();
    const session = await h.clientSignIn();
    expect(session).toEqual({
      accessToken: expect.any(String) as unknown,
      expiresInSeconds: 900,
      scope: 'CLIENT',
    });
    const claims = await h.clientClaimsOf(session);
    expect(claims).toMatchObject({ scope: 'CLIENT', aud: 'client-invite' });
    expect(claims.sub).not.toContain('9000000001');
    expect(h.sealer.open(AGENT_SEAL_PURPOSES.clientPhone, claims.sub)).toBe(
      CLIENT_PHONE,
    );
    // The agent signer never accepts it.
    await expect(h.signer.verify(session.accessToken)).resolves.toBeNull();
  });

  it('a wrong, missing or expired code is refused', async () => {
    const { h } = await world();
    await expectServiceError(
      h.clientInvites.verifyCode(CLIENT_PHONE, '123456'),
      'OTP_INVALID',
    );
    await h.clientInvites.requestCode(CLIENT_PHONE);
    await expectServiceError(
      h.clientInvites.verifyCode(CLIENT_PHONE, '999999'),
      'OTP_INVALID',
    );
    h.clock.advance(300_000);
    const pointer = await h.consentCodes.find([
      h.hasher.hash('PHONE', CLIENT_PHONE),
    ]);
    await expectServiceError(
      h.clientInvites.verifyCode(
        CLIENT_PHONE,
        h.otp.codeFor(pointer!.challengeId),
      ),
      'OTP_EXPIRED',
    );
    await expectServiceError(
      h.clientInvites.verifyCode('+91', 'abc'),
      'VALIDATION_FAILED',
      { fields: ['phone', 'code'] },
    );
  });

  it('the code an agent submit sent works too', async () => {
    const { h, agent } = await world();
    await invite(h, agent);
    const pointer = await h.consentCodes.find([
      h.hasher.hash('PHONE', CLIENT_PHONE),
    ]);
    await expect(
      h.clientInvites.verifyCode(
        CLIENT_PHONE,
        h.otp.codeFor(pointer!.challengeId),
      ),
    ).resolves.toMatchObject({ scope: 'CLIENT' });
  });

  it('an agent token, or a client token with a tampered subject, is UNAUTHORIZED', async () => {
    const { h, agent } = await world();
    await expectServiceError(
      h.clientInvites.listInvites(agent),
      'UNAUTHORIZED',
    );
    const client = await signedIn(h);
    await expectServiceError(
      h.clientInvites.listInvites({ ...client, sub: 'v1:not-sealed' }),
      'UNAUTHORIZED',
    );
  });
});

describe('ClientInviteService.listInvites', () => {
  it("shows her waiting invitations from ACTIVE agents, with the agent's short name and the discount", async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const other = await secondAgent(h);
    await invite(h, other);
    await h.agents.update('agent-2', { status: 'SUSPENDED' });
    await h.clients.create(agent, {
      phone: CLIENT_PHONE_2,
      consentConfirmed: true,
      details: CLIENT_DETAILS,
    });
    expect(await h.clientInvites.listInvites(await signedIn(h))).toEqual({
      items: [
        {
          id,
          agentDisplayName: 'Ravi K.',
          details: CLIENT_DETAILS_SEEN,
          expiresOn: '2026-11-11',
          referredMemberDiscountPercent: 5,
        },
      ],
    });
    // A DRAFT (not submitted) is never an invitation.
    expect(
      await h.clientInvites.listInvites(await signedIn(h, CLIENT_PHONE_2)),
    ).toEqual({
      items: [],
    });
  });

  it('an invitation whose time ran out is gone, whether or not the job has run', async () => {
    const { h, agent } = await world();
    await invite(h, agent);
    const client = await signedIn(h);
    h.clock.advance(14 * DAY);
    expect(await h.clientInvites.listInvites(client)).toEqual({ items: [] });
  });

  it('finds an invitation stored under an older pepper version', async () => {
    const { h, agent } = await world({ olderPeppers: ['old-pepper'] });
    const id = await invite(h, agent);
    const [, older] = h.hasher.hashAll('PHONE', CLIENT_PHONE);
    // As if made before the rotation.
    const row = h.drafts.peek(id)!;
    await h.drafts.close(id, 'TIMED_OUT', h.clock.now());
    await h.drafts.create({
      ...row,
      id: 'old',
      phoneHash: older,
      phoneSealed: row.phoneSealed!,
      detailsSealed: row.detailsSealed!,
    });
    await h.drafts.submit(
      'old',
      'agent-1',
      { submittedAt: START, expiresAt: row.expiresAt },
      START,
    );
    const items = (await h.clientInvites.listInvites(await signedIn(h))).items;
    expect(items.map((i) => i.id)).toEqual(['old']);
  });
});

describe('ClientInviteService.accept', () => {
  it('creates her account with step 1 filled, credits the agent and closes the invitation', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const other = await secondAgent(h);
    const otherId = await invite(h, other);
    const client = await signedIn(h);
    h.clock.advance(DAY);
    const now = h.clock.now();

    const result = await h.clientInvites.accept(client, id);
    expect(result).toEqual({
      firebaseCustomToken: 'custom-token-firebase-uid-1-1',
      agentDisplayName: 'Ravi K.',
      windowEndsAt: '2026-12-28',
      profileReady: true,
    });

    const memberId = 'new-member-1';
    expect(h.clientAccount.member(memberId)).toEqual({
      memberId,
      firebaseUid: 'firebase-uid-1',
      phoneE164: CLIENT_PHONE,
      profile: CLIENT_DETAILS_SEEN,
    });
    expect(await h.attributions.findByMemberId(memberId)).toEqual({
      id: 'client-attribution-1',
      memberId,
      agentId: 'agent-1',
      codeId: null,
      source: 'ADDED_BY_AGENT',
      memberPhoneHash: h.hasher.hash('PHONE', CLIENT_PHONE),
      attributedAt: now,
      status: 'ACTIVE',
      windowEndsAt: new Date(now.getTime() + CREDIT_WINDOW_DAYS * DAY),
      needsReview: false,
    });
    expect(h.drafts.peek(id)).toMatchObject({
      status: 'ACCEPTED',
      memberId,
      attributionId: 'client-attribution-1',
      acceptedAt: now,
      phoneSealed: null,
      detailsSealed: null,
    });
    expect(h.drafts.peek(otherId)).toMatchObject({
      status: 'EXPIRED',
      closedReason: 'CLIENT_ACCEPTED_ANOTHER',
      detailsSealed: null,
      phoneSealed: null,
    });
    const actions = h.audit.entries.slice(-3);
    expect(actions).toEqual([
      expect.objectContaining({
        actorId: memberId,
        actorType: 'MEMBER',
        action: 'AGENT_CLIENT_INVITE_ACCEPTED',
        entityId: id,
      }),
      expect.objectContaining({
        action: 'AGENT_ATTRIBUTION_CREATED',
        entityId: 'client-attribution-1',
        metadata: { source: 'ADDED_BY_AGENT', needsReview: false },
      }),
      expect.objectContaining({
        actorId: null,
        action: 'AGENT_CLIENT_INVITE_CLOSED',
        entityId: otherId,
        metadata: { reason: 'CLIENT_ACCEPTED_ANOTHER' },
      }),
    ]);
  });

  it('accepting again (a lost response) signs her in again and writes nothing', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    await h.clientInvites.accept(client, id);
    const audits = h.audit.entries.length;
    h.clock.advance(30 * DAY);
    await expect(h.clientInvites.accept(client, id)).resolves.toEqual({
      firebaseCustomToken: 'custom-token-firebase-uid-1-2',
      agentDisplayName: 'Ravi K.',
      windowEndsAt: '2026-12-27',
      profileReady: true,
    });
    expect(h.clientAccount.calls.createMember).toBe(1);
    // Her profile was made by the first accept; the repeat only checks it.
    expect(h.memberProfiles.calls.createFromDraft).toEqual(['new-member-1']);
    expect(h.audit.entries).toHaveLength(audits);
  });

  it('a mint that fails after the commit: accepting again still signs her in', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clientAccount.failMint = new Error(
      'Firebase custom token minting timed out',
    );
    await expect(h.clientInvites.accept(client, id)).rejects.toThrow(
      'timed out',
    );
    expect(h.drafts.peek(id)?.status).toBe('ACCEPTED');
    h.clientAccount.failMint = null;
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      agentDisplayName: 'Ravi K.',
    });
  });

  it('judges the expiry itself: refused at the very moment it runs out, before any job', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clock.set(h.drafts.peek(id)!.expiresAt);
    await expectServiceError(
      h.clientInvites.accept(client, id),
      'INVITE_UNAVAILABLE',
    );
    expect(h.clientAccount.count()).toBe(0);
    expect(h.clientAccount.calls.ensureFirebaseUser).toBe(0);
  });

  it('checks again under the lock: closed between the first check and the lock, nothing is created', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    // Between the first check and the lock (while Firebase is called), the
    // daily job closes it.
    jest
      .spyOn(h.clientAccount, 'ensureFirebaseUser')
      .mockImplementationOnce(async () => {
        await h.drafts.expireDue(null, h.drafts.peek(id)!.expiresAt, 10);
        return { uid: 'firebase-uid-1' };
      });
    await expectServiceError(
      h.clientInvites.accept(client, id),
      'INVITE_UNAVAILABLE',
    );
    expect(h.clientAccount.count()).toBe(0);
    expect(await h.attributions.listByAgent('agent-1')).toEqual([]);
  });

  it('refuses while the agent is paused or terminated', async () => {
    for (const status of ['SUSPENDED', 'TERMINATED'] as const) {
      const { h, agent } = await world();
      const id = await invite(h, agent);
      const client = await signedIn(h);
      await h.agents.update('agent-1', { status });
      await expectServiceError(
        h.clientInvites.accept(client, id),
        'INVITE_UNAVAILABLE',
      );
      expect(h.clientAccount.count()).toBe(0);
    }
  });

  it('a phone that joined meanwhile is ALREADY_MEMBER, and the invitation is closed', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clientAccount.addMember('member-9', CLIENT_PHONE);
    await expectServiceError(
      h.clientInvites.accept(client, id),
      'ALREADY_MEMBER',
    );
    expect(h.drafts.peek(id)).toMatchObject({
      status: 'EXPIRED',
      closedReason: 'CLIENT_ALREADY_MEMBER',
    });
    expect(h.audit.entries[h.audit.entries.length - 1]).toMatchObject({
      action: 'AGENT_CLIENT_INVITE_CLOSED',
      metadata: { reason: 'CLIENT_ALREADY_MEMBER' },
    });
  });

  it('an unknown invitation, or one for another phone, is INVITE_NOT_FOUND', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const someoneElse = await signedIn(h, CLIENT_PHONE_2);
    await expectServiceError(
      h.clientInvites.accept(someoneElse, id),
      'INVITE_NOT_FOUND',
    );
    await expectServiceError(
      h.clientInvites.accept(someoneElse, 'nope'),
      'INVITE_NOT_FOUND',
    );
  });

  it('a failure inside the transaction leaves everything as it was', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clientAccount.failCreate = new Error('database unavailable');
    await expect(h.clientInvites.accept(client, id)).rejects.toThrow(
      'database unavailable',
    );
    expect(h.drafts.peek(id)?.status).toBe('WAITING_FOR_CLIENT');
    expect(await h.attributions.listByAgent('agent-1')).toEqual([]);
    h.clientAccount.failCreate = null;
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      agentDisplayName: 'Ravi K.',
    });
  });

  it('two accepts at once by the same phone both succeed, with one account', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    const [a, b] = await Promise.all([
      h.clientInvites.accept(client, id),
      h.clientInvites.accept(client, id),
    ]);
    expect(a.agentDisplayName).toBe('Ravi K.');
    expect(b.agentDisplayName).toBe('Ravi K.');
    expect(h.clientAccount.count()).toBe(1);
    expect(await h.attributions.listByAgent('agent-1')).toHaveLength(1);
  });

  it("two agents' invitations accepted at once: one wins, the other is closed", async () => {
    const { h, agent } = await world();
    const first = await invite(h, agent);
    const other = await secondAgent(h);
    const second = await invite(h, other);
    const client = await signedIn(h);
    const results = await Promise.allSettled([
      h.clientInvites.accept(client, first),
      h.clientInvites.accept(client, second),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([
      'fulfilled',
      'rejected',
    ]);
    // The loser hears that the invitation is closed, or (if it looked after
    // the winner committed) that she is a member now.
    expect(['INVITE_UNAVAILABLE', 'ALREADY_MEMBER']).toContain(
      (
        (results.find((r) => r.status === 'rejected') as PromiseRejectedResult)
          .reason as { code: string }
      ).code,
    );
    expect(h.clientAccount.count()).toBe(1);
    const statuses = [
      h.drafts.peek(first)!.status,
      h.drafts.peek(second)!.status,
    ].sort();
    expect(statuses).toEqual(['ACCEPTED', 'EXPIRED']);
  });

  it('an invitation stored under an older pepper is accepted; the credit is written under the newest', async () => {
    const { h, agent } = await world({ olderPeppers: ['old-pepper'] });
    const id = await invite(h, agent);
    const [newest, older] = h.hasher.hashAll('PHONE', CLIENT_PHONE);
    const row = h.drafts.peek(id)!;
    await h.drafts.close(id, 'TIMED_OUT', h.clock.now());
    await h.drafts.create({
      ...row,
      id: 'old',
      phoneHash: older,
      phoneSealed: row.phoneSealed!,
      detailsSealed: row.detailsSealed!,
    });
    await h.drafts.submit(
      'old',
      'agent-1',
      { submittedAt: START, expiresAt: row.expiresAt },
      START,
    );
    await h.clientInvites.accept(await signedIn(h), 'old');
    expect(
      (await h.attributions.findByMemberId('new-member-1'))?.memberPhoneHash,
    ).toBe(newest);
  });

  it('a missing credit window is a 503 before anything is written', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.settings.remove(REFERRAL_CREDIT_WINDOW_DAYS_KEY);
    await expect(h.clientInvites.accept(client, id)).rejects.toMatchObject({
      name: 'AgentConfigError',
      missing: [REFERRAL_CREDIT_WINDOW_DAYS_KEY],
    });
    expect(h.clientAccount.calls.ensureFirebaseUser).toBe(0);
  });
});

describe('ClientInviteService.reject', () => {
  it('closes it as REJECTED, keeps the sealed phone, and that agent can never add the phone again', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    await h.clientInvites.reject(client, id);
    expect(h.drafts.peek(id)).toMatchObject({
      status: 'REJECTED',
      detailsSealed: null,
    });
    expect(h.drafts.peek(id)?.phoneSealed).not.toBeNull();
    expect(h.audit.entries[h.audit.entries.length - 1]).toEqual({
      actorId: null,
      actorType: 'MEMBER',
      action: 'AGENT_CLIENT_INVITE_REJECTED',
      entity: 'agent_client_draft',
      entityId: id,
    });
    expect(h.clientAccount.count()).toBe(0);
    await expectServiceError(
      h.clients.create(agent, {
        phone: CLIENT_PHONE,
        consentConfirmed: true,
        details: CLIENT_DETAILS,
      }),
      'CLIENT_PHONE_UNAVAILABLE',
    );
  });

  it('rejecting again answers the same and writes nothing', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    await h.clientInvites.reject(client, id);
    const audits = h.audit.entries.length;
    await expect(h.clientInvites.reject(client, id)).resolves.toBeUndefined();
    expect(h.audit.entries).toHaveLength(audits);
  });

  it('cannot reject what is accepted, expired or someone else’s', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    await expectServiceError(
      h.clientInvites.reject(await signedIn(h, CLIENT_PHONE_2), id),
      'INVITE_NOT_FOUND',
    );
    await h.clientInvites.accept(client, id);
    await expectServiceError(
      h.clientInvites.reject(client, id),
      'INVITE_UNAVAILABLE',
    );
    const later = await invite(h, agent, CLIENT_PHONE_2);
    const client2 = await signedIn(h, CLIENT_PHONE_2);
    h.clock.advance(14 * DAY);
    await expectServiceError(
      h.clientInvites.reject(client2, later),
      'INVITE_UNAVAILABLE',
    );
  });
});

describe('ClientInviteService: no PII outside the sealed columns', () => {
  it('audit rows and refusals never carry the phone, the names or a code', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    const errors = await Promise.all([
      h.clientInvites
        .verifyCode(CLIENT_PHONE, '999999')
        .catch((e: unknown) => e),
      h.clientInvites.requestCode(UNAPPROVED_PHONE).catch((e: unknown) => e),
    ]);
    await h.clientInvites.accept(client, id);
    const text =
      JSON.stringify(h.audit.entries) +
      JSON.stringify(errors) +
      errors.map(String).join();
    for (const secret of [
      '9000000001',
      '9999999999',
      'Priya',
      'Sundaram',
      '999999',
    ]) {
      expect(text).not.toContain(secret);
    }
  });
});

describe('ClientInviteService: the full profile', () => {
  it('the invitation and the new member carry every section the agent filled', async () => {
    const { h, agent } = await world();
    const extra = {
      languageDetails: { motherTongue: 'Tamil' },
      physicalDetails: { height: `5'3" (160 cm)` },
      familyDetails: {
        father: { occupation: 'Retired teacher' },
        siblings: [{ relation: 'BROTHER', age: 30 }],
        familyType: 'Nuclear Family',
      },
      horoscopeDetails: { rashi: 'Simha', star: 'Rohini' },
    };
    const draft = await h.clients.create(agent, {
      phone: CLIENT_PHONE,
      consentConfirmed: true,
      details: { ...CLIENT_DETAILS, ...extra },
    });
    await h.clients.submit(agent, draft.id);
    const client = await signedIn(h);
    const seen = { ...CLIENT_DETAILS_SEEN, ...extra };
    expect(
      (await h.clientInvites.listInvites(client)).items[0].details,
    ).toEqual(seen);
    await h.clientInvites.accept(client, draft.id);
    expect(h.clientAccount.member('new-member-1')?.profile).toEqual(seen);
  });
});

describe('ClientInviteService.accept: her member profile (she lands on the home page)', () => {
  it('is made from her registration draft after the accept has committed', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    const statusWhenMade: Array<string | undefined> = [];
    const membersWhenMade: number[] = [];
    h.memberProfiles.onCreate = () => {
      statusWhenMade.push(h.drafts.peek(id)?.status);
      membersWhenMade.push(h.clientAccount.count());
    };
    const result = await h.clientInvites.accept(client, id);
    expect(result.profileReady).toBe(true);
    expect(h.memberProfiles.has('new-member-1')).toBe(true);
    // The member, her draft and the credit were already there.
    expect(statusWhenMade).toEqual(['ACCEPTED']);
    expect(membersWhenMade).toEqual([1]);
  });

  it('a failure never fails the accept: profileReady false, logged without her details, and the next accept makes it', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    class ProfileWriteError extends Error {
      override name = 'ProfileWriteError';
    }
    h.memberProfiles.failCreate = new ProfileWriteError(
      `could not write ${CLIENT_PHONE} Priya`,
    );
    const first = await h.clientInvites.accept(client, id);
    expect(first).toMatchObject({
      firebaseCustomToken: 'custom-token-firebase-uid-1-1',
      profileReady: false,
    });
    expect(h.drafts.peek(id)?.status).toBe('ACCEPTED');
    expect(h.memberProfiles.has('new-member-1')).toBe(false);
    const logged = h.clientLog.warn.mock.calls.map((c) => c[0]);
    expect(logged).toContain(
      `No member profile was made for accepted client draft ${id} (ProfileWriteError); the next accept tries again.`,
    );
    expect(JSON.stringify(logged)).not.toContain(CLIENT_PHONE);
    expect(JSON.stringify(logged)).not.toContain('Priya');

    h.memberProfiles.failCreate = null;
    const second = await h.clientInvites.accept(client, id);
    expect(second.profileReady).toBe(true);
    expect(h.memberProfiles.has('new-member-1')).toBe(true);
    expect(h.clientAccount.calls.createMember).toBe(1);
    expect(h.memberProfiles.calls.createFromDraft).toEqual([
      'new-member-1',
      'new-member-1',
    ]);
  });

  it('a failing existence check is a failure too, not an error', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.memberProfiles.failExists = new TypeError('connection reset');
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      profileReady: false,
    });
    expect(h.clientLog.warn.mock.calls.map((c) => c[0])).toContain(
      `No member profile was made for accepted client draft ${id} (TypeError); the next accept tries again.`,
    );
  });

  it('a draft that does not make a profile row: profileReady false and logged', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.memberProfiles.makesNothing = true;
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      profileReady: false,
    });
    expect(h.clientLog.warn.mock.calls.map((c) => c[0])).toContain(
      `No member profile was made for accepted client draft ${id} (her draft lacks what a profile needs); the next accept tries again.`,
    );
  });

  it('a mint that fails after the profile was made: the repeat signs her in and does not make it again', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clientAccount.failMint = new Error('mint timed out');
    await expect(h.clientInvites.accept(client, id)).rejects.toThrow(
      'mint timed out',
    );
    expect(h.memberProfiles.has('new-member-1')).toBe(true);
    h.clientAccount.failMint = null;
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      profileReady: true,
    });
    expect(h.memberProfiles.calls.createFromDraft).toEqual(['new-member-1']);
  });

  it('a refused accept makes no profile', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clock.set(h.drafts.peek(id)!.expiresAt);
    await expect(h.clientInvites.accept(client, id)).rejects.toMatchObject({
      code: 'INVITE_UNAVAILABLE',
    });
    expect(h.memberProfiles.calls.createFromDraft).toEqual([]);
  });

  it('a second accept that read the invitation just before the first committed signs her in, and closes nothing', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    const stale = h.drafts.peek(id)!;
    await h.clientInvites.accept(client, id);
    // The second request read the row while it was still WAITING_FOR_CLIENT.
    jest.spyOn(h.drafts, 'findForPhone').mockResolvedValueOnce(stale);
    await expect(h.clientInvites.accept(client, id)).resolves.toMatchObject({
      agentDisplayName: 'Ravi K.',
      profileReady: true,
    });
    expect(h.drafts.peek(id)).toMatchObject({
      status: 'ACCEPTED',
      memberId: 'new-member-1',
    });
    expect(h.clientAccount.calls.createMember).toBe(1);
  });

  it('a stale read of an invitation whose accepted account is gone, with the phone now on another account: ALREADY_MEMBER, not a sign-in', async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    const stale = h.drafts.peek(id)!;
    await h.clientInvites.accept(client, id);
    h.clientAccount.deleteMember('new-member-1');
    h.clientAccount.addMember('later-member', CLIENT_PHONE);
    jest.spyOn(h.drafts, 'findForPhone').mockResolvedValueOnce(stale);
    await expect(h.clientInvites.accept(client, id)).rejects.toMatchObject({
      code: 'ALREADY_MEMBER',
    });
  });

  it("a phone that is really someone else's member account is still ALREADY_MEMBER", async () => {
    const { h, agent } = await world();
    const id = await invite(h, agent);
    const client = await signedIn(h);
    h.clientAccount.addMember('earlier-member', CLIENT_PHONE);
    await expect(h.clientInvites.accept(client, id)).rejects.toMatchObject({
      code: 'ALREADY_MEMBER',
    });
    expect(h.drafts.peek(id)).toMatchObject({
      status: 'EXPIRED',
      closedReason: 'CLIENT_ALREADY_MEMBER',
    });
    expect(h.memberProfiles.calls.createFromDraft).toEqual([]);
  });
});
