import type { AgentSession } from '../auth/agent-session-issuer';
import { AgentConflictError } from '../ports/agent-data-ports';
import { hashRefreshToken } from '../auth/refresh-token';
import {
  AgentHarness,
  AUTH_OPTIONS,
  expectServiceError,
  makeAgentHarness,
  PHONE,
} from '../testing/agent-test-harness';
import { REJECTED_MAY_REAPPLY } from '../agent/agent-status';
import {
  AgentApplicationBody,
  AgentApplicationService,
} from './agent-application.service';

const BODY: AgentApplicationBody = {
  name: 'Ravi Kumar',
  city: 'Coimbatore',
  state: 'Tamil Nadu',
  pan: 'ABCDE1234F',
};
const PHONE_HASH_OF = (h: AgentHarness) => h.hasher.hash('PHONE', PHONE);

describe('AgentApplicationService.submit', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness();
  });

  /** Sign in as a brand-new phone and return the applicant's claims. */
  const applicant = async () => h.claimsOf(await h.signInAs());

  describe('CREATE_PENDING (an applicant applies)', () => {
    it('creates a PENDING_APPROVAL agent and returns an AgentSession for it', async () => {
      const session = await h.application.submit(await applicant(), BODY);
      expect(session).toMatchObject({
        scope: 'AGENT',
        accessToken: expect.any(String) as string,
        refreshToken: expect.any(String) as string,
        agent: {
          id: 'new-agent-1',
          name: 'Ravi Kumar',
          phoneMasked: '+91 98***210',
          city: 'Coimbatore',
          state: 'Tamil Nadu',
          status: 'PENDING_APPROVAL',
          statusLabel: { en: 'Under review', ta: '<to be supplied>' },
          rejectionReason: null,
          approvedAt: null,
          panLast4: '234F',
          payoutDetailsSet: false,
          primaryCode: null,
        },
      });
    });

    it('takes the phone from the verified sign-in, never from the body', async () => {
      const session = await h.application.submit(await applicant(), {
        ...BODY,
        phone: '+919999999999',
      } as AgentApplicationBody);
      const stored = await h.agents.findById(session.agent.id);
      expect(stored!.phoneE164).toBe(PHONE);
      expect(stored!.phoneHash).toBe(PHONE_HASH_OF(h));
    });

    it('the new tokens are for the agent: AGENT scope, agent id, a stored refresh hash', async () => {
      const session = await h.application.submit(await applicant(), BODY);
      const claims = await h.claimsOf(session);
      expect(claims).toMatchObject({ scope: 'AGENT', sub: 'new-agent-1' });
      const row = await h.tokens.findByHash(
        hashRefreshToken(session.refreshToken, AUTH_OPTIONS.refreshTokenPepper),
      );
      expect(row).toMatchObject({ agentId: 'new-agent-1', revokedAt: null });
    });

    it('the new session works for refresh and for the next sign-in', async () => {
      const session = await h.application.submit(await applicant(), BODY);
      await expect(
        h.signIn.refresh(session.refreshToken),
      ).resolves.toMatchObject({
        scope: 'AGENT',
      });
      const again = (await h.signInAs()) as AgentSession;
      expect(again.agent.status).toBe('PENDING_APPROVAL');
    });

    it('stores the full PAN sealed and only the last four in clear', async () => {
      const session = await h.application.submit(await applicant(), BODY);
      const stored = await h.agents.findById(session.agent.id);
      expect(stored!.panLast4).toBe('234F');
      expect(stored!.panSealed).not.toBeNull();
      expect(stored!.panSealed).not.toContain('ABCDE1234F');
      expect(h.sealer.open(stored!.panSealed!)).toBe('ABCDE1234F');
      expect(JSON.stringify(session)).not.toContain('ABCDE1234F');
    });

    it('accepts a lower-case PAN with spaces and normalises it', async () => {
      const session = await h.application.submit(await applicant(), {
        ...BODY,
        pan: ' abcde1234f ',
      });
      const stored = await h.agents.findById(session.agent.id);
      expect(h.sealer.open(stored!.panSealed!)).toBe('ABCDE1234F');
    });

    it('PAN is optional: without it nothing is stored', async () => {
      const withoutPan: AgentApplicationBody = {
        name: BODY.name,
        city: BODY.city,
        state: BODY.state,
      };
      const session = await h.application.submit(await applicant(), withoutPan);
      const stored = await h.agents.findById(session.agent.id);
      expect(session.agent.panLast4).toBeNull();
      expect(stored).toMatchObject({ panLast4: null, panSealed: null });
    });

    it('trims name, city and state', async () => {
      const session = await h.application.submit(await applicant(), {
        name: '  Ravi Kumar ',
        city: ' Coimbatore',
        state: 'Tamil Nadu  ',
      });
      expect(session.agent).toMatchObject({
        name: 'Ravi Kumar',
        city: 'Coimbatore',
        state: 'Tamil Nadu',
      });
    });

    it('forgets the verified phone once the application is saved', async () => {
      await h.application.submit(await applicant(), BODY);
      expect(await h.applicants.find(PHONE_HASH_OF(h))).toBeNull();
    });

    it('writes one audit entry in the same transaction, without the PAN or phone', async () => {
      await h.application.submit(await applicant(), BODY);
      expect(h.audit.entries).toEqual([
        {
          actorId: 'new-agent-1',
          action: 'AGENT_APPLICATION_SUBMITTED',
          entity: 'agent',
          entityId: 'new-agent-1',
          metadata: { panProvided: true },
        },
      ]);
      expect(JSON.stringify(h.audit.entries)).not.toContain('ABCDE1234F');
    });

    it('a second submit with the same applicant token is refused (the phone is now an agent)', async () => {
      const claims = await applicant();
      await h.application.submit(claims, BODY);
      await expectServiceError(
        h.application.submit(claims, BODY),
        'PHONE_ALREADY_REGISTERED',
      );
    });

    it('rolls everything back when the tokens cannot be signed, and keeps the verified phone', async () => {
      const claims = await applicant();
      h.signer.failing = true;
      await expect(h.application.submit(claims, BODY)).rejects.toThrow(
        'signer unavailable',
      );
      h.signer.failing = false;
      expect(await h.agents.findByPhoneHash(PHONE_HASH_OF(h))).toBeNull();
      expect(await h.applicants.find(PHONE_HASH_OF(h))).not.toBeNull();
      expect(h.audit.entries).toHaveLength(0);
      await expect(h.application.submit(claims, BODY)).resolves.toBeDefined();
    });

    it('the verified phone has expired: UNAUTHORIZED, nothing created', async () => {
      const claims = await applicant();
      h.clock.advance(AUTH_OPTIONS.applicantPhoneTtlSeconds * 1000);
      await expectServiceError(
        h.application.submit(claims, BODY),
        'UNAUTHORIZED',
      );
      expect(await h.agents.findByPhoneHash(PHONE_HASH_OF(h))).toBeNull();
    });

    it('there is no remembered phone for this hash: UNAUTHORIZED', async () => {
      const claims = { ...(await applicant()), sub: 'some-other-hash' };
      await expectServiceError(
        h.application.submit(claims, BODY),
        'UNAUTHORIZED',
      );
    });

    it('a duplicate phone hash found by the database is PHONE_ALREADY_REGISTERED', async () => {
      const claims = await applicant();
      jest
        .spyOn(h.agents, 'create')
        .mockRejectedValueOnce(new AgentConflictError('DUPLICATE_PHONE_HASH'));
      await expectServiceError(
        h.application.submit(claims, BODY),
        'PHONE_ALREADY_REGISTERED',
      );
    });
  });

  describe('RESUBMIT_PENDING (a rejected agent applies again)', () => {
    const rejectedAgent = async () => {
      await h.seedAgent('REJECTED', { rejectionReason: 'Incomplete details' });
      const old = (await h.signInAs()) as AgentSession;
      return { old, claims: await h.claimsOf(old) };
    };

    it('goes back to PENDING_APPROVAL, clears the reason and keeps the same agent', async () => {
      const { claims } = await rejectedAgent();
      const session = await h.application.submit(claims, {
        name: 'Ravi K. Kumar',
        city: 'Madurai',
        state: 'Tamil Nadu',
      });
      expect(session.agent).toMatchObject({
        id: 'agent-1',
        name: 'Ravi K. Kumar',
        city: 'Madurai',
        status: 'PENDING_APPROVAL',
        rejectionReason: null,
      });
      expect(await h.agents.findByPhoneHash(PHONE_HASH_OF(h))).toMatchObject({
        id: 'agent-1',
        status: 'PENDING_APPROVAL',
        rejectionReason: null,
      });
    });

    it('starts a NEW refresh token family and revokes the old one', async () => {
      const { old, claims } = await rejectedAgent();
      const session = await h.application.submit(claims, BODY);
      expect(session.refreshToken).not.toBe(old.refreshToken);
      const oldRow = await h.tokens.findByHash(
        hashRefreshToken(old.refreshToken, AUTH_OPTIONS.refreshTokenPepper),
      );
      expect(oldRow!.revokedAt).toEqual(h.clock.now());
      await expect(
        h.signIn.refresh(session.refreshToken),
      ).resolves.toBeDefined();
    });

    it('revokes every old token, not only the one in use', async () => {
      const { old, claims } = await rejectedAgent();
      const other = (await h.signInAs()) as AgentSession; // a second device
      await h.application.submit(claims, BODY);
      await expect(h.signIn.refresh(other.refreshToken)).rejects.toMatchObject({
        code: 'REFRESH_TOKEN_REUSED',
      });
      expect(old.refreshToken).not.toBe(other.refreshToken);
    });

    it('keeps the earlier PAN when none is sent, and replaces it when one is', async () => {
      await h.seedAgent('REJECTED', {
        panLast4: '111A',
        panSealed: h.sealer.seal('AAAAA1111A'),
      });
      const claims = await h.claimsOf(await h.signInAs());
      const withoutPan: AgentApplicationBody = {
        name: BODY.name,
        city: BODY.city,
        state: BODY.state,
      };
      await h.application.submit(claims, withoutPan);
      expect((await h.agents.findById('agent-1'))!.panLast4).toBe('111A');

      await h.seedAgent('REJECTED', {
        id: 'agent-2',
        phoneE164: '+919000000002',
        panLast4: '111A',
      });
      await h.application.submit(
        await h.claimsOf(await h.signInAs('+919000000002')),
        BODY,
      );
      const second = await h.agents.findById('agent-2');
      expect(second!.panLast4).toBe('234F');
      expect(h.sealer.open(second!.panSealed!)).toBe('ABCDE1234F');
    });

    it('does not create a second agent or touch the applicant store', async () => {
      const { claims } = await rejectedAgent();
      await h.application.submit(claims, BODY);
      expect(await h.agents.findByPhoneHash(PHONE_HASH_OF(h))).toMatchObject({
        id: 'agent-1',
      });
      expect(await h.applicants.find(PHONE_HASH_OF(h))).toBeNull();
    });

    it('writes a RESUBMITTED audit entry', async () => {
      const { claims } = await rejectedAgent();
      await h.application.submit(claims, BODY);
      expect(h.audit.entries.map((e) => e.action)).toEqual([
        'AGENT_APPLICATION_RESUBMITTED',
      ]);
    });

    it('rolls back (still REJECTED, old tokens still valid) when signing fails', async () => {
      const { old, claims } = await rejectedAgent();
      h.signer.failing = true;
      await expect(h.application.submit(claims, BODY)).rejects.toThrow(
        'signer unavailable',
      );
      h.signer.failing = false;
      expect((await h.agents.findById('agent-1'))!.status).toBe('REJECTED');
      await expect(h.signIn.refresh(old.refreshToken)).resolves.toBeDefined();
    });
  });

  describe('every refusal reason', () => {
    const asAgentClaims = async (status: string) => {
      await h.seedAgent(status);
      return h.claimsOf(await h.signInAs());
    };

    it('ALREADY_PENDING, with the agent status', async () => {
      await expectServiceError(
        h.application.submit(await asAgentClaims('PENDING_APPROVAL'), BODY),
        'ALREADY_PENDING',
        { agentStatus: 'PENDING_APPROVAL' },
      );
    });

    it.each(['ACTIVE', 'SUSPENDED', 'TERMINATED'])(
      'ALREADY_AN_AGENT for a %s agent',
      async (status) => {
        await expectServiceError(
          h.application.submit(await asAgentClaims(status), BODY),
          'ALREADY_AN_AGENT',
          { agentStatus: status },
        );
      },
    );

    it('PHONE_ALREADY_REGISTERED: an applicant token, but the phone has an agent record', async () => {
      const claims = await applicant();
      await h.seedAgent('ACTIVE');
      await expectServiceError(
        h.application.submit(claims, BODY),
        'PHONE_ALREADY_REGISTERED',
      );
    });

    it('SCOPE_MISMATCH: an AGENT token whose agent record does not exist', async () => {
      const claims = await asAgentClaims('ACTIVE');
      jest.spyOn(h.agents, 'findById').mockResolvedValueOnce(null);
      await expectServiceError(
        h.application.submit(claims, BODY),
        'SCOPE_MISMATCH',
      );
    });

    it('BAD_SCOPE: a token scope that is neither AGENT nor APPLICANT', async () => {
      const claims = { ...(await applicant()), scope: 'ADMIN' as never };
      await expectServiceError(h.application.submit(claims, BODY), 'BAD_SCOPE');
    });

    it('UNKNOWN_STATUS: a stored status the program does not know', async () => {
      const claims = await asAgentClaims('ACTIVE');
      await h.agents.update('agent-1', { status: 'WEIRD' as never });
      await expectServiceError(
        h.application.submit(claims, BODY),
        'UNKNOWN_STATUS',
      );
    });

    it('refusals change nothing', async () => {
      const claims = await asAgentClaims('ACTIVE');
      await expect(h.application.submit(claims, BODY)).rejects.toBeDefined();
      expect((await h.agents.findById('agent-1'))!.name).toBe('Ravi Kumar');
      expect(h.audit.entries).toHaveLength(0);
    });
  });

  describe('REAPPLY_NOT_ALLOWED', () => {
    it('is the answer for a rejected agent when re-applying is switched off', async () => {
      const off = new AgentApplicationService({
        agents: h.agents,
        refreshTokens: h.tokens,
        applicants: h.applicants,
        sealer: h.sealer,
        uow: h.uow,
        audit: h.audit,
        clock: h.clock,
        issuer: h.issuer,
        rejectedMayReapply: false,
      });
      await h.seedAgent('REJECTED');
      const claims = await h.claimsOf(await h.signInAs());
      await expectServiceError(
        off.submit(claims, BODY),
        'REAPPLY_NOT_ALLOWED',
        {
          agentStatus: 'REJECTED',
        },
      );
      expect((await h.agents.findById('agent-1'))!.status).toBe('REJECTED');
    });

    it('the default follows REJECTED_MAY_REAPPLY', async () => {
      expect(REJECTED_MAY_REAPPLY).toBe(true);
      await h.seedAgent('REJECTED');
      const claims = await h.claimsOf(await h.signInAs());
      await expect(h.application.submit(claims, BODY)).resolves.toBeDefined();
    });
  });

  describe('validation', () => {
    it.each([
      [{ name: '' }, ['name']],
      [{ name: 'R' }, ['name']],
      [{ name: ' R ' }, ['name']],
      [{ name: 'x'.repeat(101) }, ['name']],
      [{ city: '' }, ['city']],
      [{ city: '   ' }, ['city']],
      [{ city: 'x'.repeat(81) }, ['city']],
      [{ state: '' }, ['state']],
      [{ state: 'x'.repeat(81) }, ['state']],
      [{ pan: 'ABCDE1234' }, ['pan']],
      [{ pan: 'ABCDE12345' }, ['pan']],
      [{ pan: '' }, ['pan']],
      [{ pan: null }, ['pan']],
      [{ pan: 12345 }, ['pan']],
      [{ name: '', city: '', pan: 'bad' }, ['name', 'city', 'pan']],
    ])('refuses %p (%p)', async (override, fields) => {
      const claims = await applicant();
      await expectServiceError(
        h.application.submit(claims, {
          ...BODY,
          ...(override as Partial<AgentApplicationBody>),
        }),
        'VALIDATION_FAILED',
        { fields },
      );
      expect(await h.agents.findByPhoneHash(PHONE_HASH_OF(h))).toBeNull();
    });

    it('accepts the boundary lengths', async () => {
      const session = await h.application.submit(await applicant(), {
        name: 'Ra',
        city: 'x'.repeat(80),
        state: 'y'.repeat(80),
      });
      expect(session.agent.name).toBe('Ra');
    });

    it('never puts a bad value in the error', async () => {
      const claims = await applicant();
      const error = await h.application
        .submit(claims, { ...BODY, pan: 'NOT-A-PAN-VALUE' })
        .catch((e: unknown) => e);
      expect(JSON.stringify(error)).not.toContain('NOT-A-PAN-VALUE');
      expect((error as Error).message).not.toContain('NOT-A-PAN-VALUE');
    });

    it('a missing body is a validation failure', async () => {
      await expectServiceError(
        h.application.submit(await applicant(), undefined as never),
        'VALIDATION_FAILED',
      );
    });
  });
});
