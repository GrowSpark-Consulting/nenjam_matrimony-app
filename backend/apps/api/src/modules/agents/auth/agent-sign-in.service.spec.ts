import type { AgentOtpPurpose } from '../ports/agent-platform-ports';
import { AgentConfigError } from '../config/agent-config.service';
import {
  AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY,
  AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
} from '../settings/agent-program-settings';
import {
  ACCESS_TTL,
  AgentHarness,
  AUTH_OPTIONS,
  expectServiceError,
  makeAgentHarness,
  OTP_TTL_MS,
  PHONE,
  REFRESH_TTL,
  RESEND_AFTER,
} from '../testing/agent-test-harness';
import { hashRefreshToken } from './refresh-token';
import { validateAgentAccessClaims } from './agent-access-claims';
import type {
  AgentApplicantSession,
  AgentSession,
} from './agent-session-issuer';

const OTHER_PURPOSE = 'MEMBER_SIGN_IN' as unknown as AgentOtpPurpose;

const asAgent = (session: unknown) => session as AgentSession;
const asApplicant = (session: unknown) => session as AgentApplicantSession;

describe('AgentSignInService', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness();
  });

  describe('start', () => {
    it('returns a challenge id and the two timings', async () => {
      const result = await h.signIn.start(PHONE);
      expect(result).toEqual({
        challengeId: expect.any(String) as string,
        expiresInSeconds: OTP_TTL_MS / 1000,
        resendAfterSeconds: RESEND_AFTER,
      });
    });

    it('rounds expiresInSeconds up and never reports less than 1', async () => {
      const result = await h.signIn.start(PHONE);
      expect(Number.isInteger(result.expiresInSeconds)).toBe(true);
      expect(result.expiresInSeconds).toBeGreaterThanOrEqual(1);
    });

    it('gives the same answer whether or not the phone is an agent', async () => {
      const unknown = await h.signIn.start('+919000000001');
      await h.seedAgent('ACTIVE');
      const known = await h.signIn.start(PHONE);
      expect(Object.keys(known).sort()).toEqual(Object.keys(unknown).sort());
      expect(known.expiresInSeconds).toBe(unknown.expiresInSeconds);
      expect(known.resendAfterSeconds).toBe(unknown.resendAfterSeconds);
    });

    it('does not look the phone up at all', async () => {
      const spy = jest.spyOn(h.agents, 'findByPhoneHash');
      await h.signIn.start(PHONE);
      expect(spy).not.toHaveBeenCalled();
    });

    it.each([
      '',
      '9876543210',
      '+0123456789',
      '+91 98765 43210',
      '+91987',
      '+9198765432101234567',
      'abc',
    ])('refuses the phone %p', async (phone) => {
      await expectServiceError(h.signIn.start(phone), 'VALIDATION_FAILED', {
        fields: ['phone'],
      });
    });

    it('refuses a phone that is not a string', async () => {
      await expectServiceError(
        h.signIn.start(undefined as unknown as string),
        'VALIDATION_FAILED',
      );
    });

    it("turns the port's rate limit into RATE_LIMITED carrying retryAfterSeconds", async () => {
      for (let i = 0; i < 3; i++) await h.signIn.start(PHONE);
      await expectServiceError(h.signIn.start(PHONE), 'RATE_LIMITED', {
        retryAfterSeconds: 600,
      });
    });

    it('allows sending again once the window has passed', async () => {
      for (let i = 0; i < 3; i++) await h.signIn.start(PHONE);
      h.clock.advance(600_000);
      await expect(h.signIn.start(PHONE)).resolves.toBeDefined();
    });

    it('fails clearly, and sends nothing, when the resend setting is missing', async () => {
      h.settings.remove(AGENT_OTP_RESEND_AFTER_SECONDS_KEY);
      const send = jest.spyOn(h.otp, 'send');
      await expect(h.signIn.start(PHONE)).rejects.toBeInstanceOf(
        AgentConfigError,
      );
      await expect(h.signIn.start(PHONE)).rejects.toThrow(
        AGENT_OTP_RESEND_AFTER_SECONDS_KEY,
      );
      expect(send).not.toHaveBeenCalled();
    });

    it.each([0, -1, 1.5, '30'])(
      'fails with a RangeError when the resend setting is %p',
      async (value) => {
        h.settings.set(AGENT_OTP_RESEND_AFTER_SECONDS_KEY, value);
        await expect(h.signIn.start(PHONE)).rejects.toThrow(RangeError);
      },
    );
  });

  describe('verify: input and OTP failures', () => {
    it.each([
      ['', '123456', ['challengeId']],
      ['c', 'abc', ['code']],
      ['c', '123', ['code']],
      ['c', '123456789', ['code']],
      ['', '', ['challengeId', 'code']],
    ])(
      'refuses challenge %p with code %p before asking the OTP port',
      async (challengeId, code, fields) => {
        const verify = jest.spyOn(h.otp, 'verify');
        await expectServiceError(
          h.signIn.verify(challengeId, code),
          'VALIDATION_FAILED',
          { fields },
        );
        expect(verify).not.toHaveBeenCalled();
      },
    );

    it('a wrong code is OTP_INVALID, creates nothing, and can be retried', async () => {
      const { challengeId } = await h.signIn.start(PHONE);
      await expectServiceError(
        h.signIn.verify(challengeId, '000000'),
        'OTP_INVALID',
      );
      expect(await h.applicants.find(h.hasher.hash('PHONE', PHONE))).toBeNull();
      const session = await h.signIn.verify(
        challengeId,
        h.otp.codeFor(challengeId),
      );
      expect(session.scope).toBe('APPLICANT');
    });

    it('an expired code is OTP_EXPIRED', async () => {
      const { challengeId } = await h.signIn.start(PHONE);
      h.clock.advance(OTP_TTL_MS);
      await expectServiceError(
        h.signIn.verify(challengeId, h.otp.codeFor(challengeId)),
        'OTP_EXPIRED',
      );
    });

    it('an unknown challenge is OTP_INVALID', async () => {
      await expectServiceError(
        h.signIn.verify('nope', '123456'),
        'OTP_INVALID',
      );
    });

    it('a used code is OTP_INVALID (single use)', async () => {
      const { challengeId } = await h.signIn.start(PHONE);
      const code = h.otp.codeFor(challengeId);
      await h.signIn.verify(challengeId, code);
      await expectServiceError(
        h.signIn.verify(challengeId, code),
        'OTP_INVALID',
      );
    });

    it('a challenge created for another purpose is OTP_INVALID, even with the right code', async () => {
      const { challengeId } = await h.otp.send(OTHER_PURPOSE, PHONE);
      await expectServiceError(
        h.signIn.verify(challengeId, h.otp.codeFor(challengeId)),
        'OTP_INVALID',
      );
      expect(await h.applicants.find(h.hasher.hash('PHONE', PHONE))).toBeNull();
    });

    it('too many wrong tries is RATE_LIMITED', async () => {
      const { challengeId } = await h.signIn.start(PHONE);
      for (let i = 0; i < 3; i++) {
        await expectServiceError(
          h.signIn.verify(challengeId, '000000'),
          'OTP_INVALID',
        );
      }
      await expectServiceError(
        h.signIn.verify(challengeId, h.otp.codeFor(challengeId)),
        'RATE_LIMITED',
      );
    });

    it('a missing token lifetime fails before the OTP is used up', async () => {
      const { challengeId } = await h.signIn.start(PHONE);
      const code = h.otp.codeFor(challengeId);
      h.settings.remove(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY);
      await expect(h.signIn.verify(challengeId, code)).rejects.toBeInstanceOf(
        AgentConfigError,
      );
      h.settings.set(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY, ACCESS_TTL);
      await expect(h.signIn.verify(challengeId, code)).resolves.toBeDefined();
    });
  });

  describe('verify: applicant (no agent record)', () => {
    it('gets an access token only: scope APPLICANT, no refresh token', async () => {
      const session = asApplicant(await h.signInAs());
      expect(session).toEqual({
        accessToken: expect.any(String) as string,
        expiresInSeconds: ACCESS_TTL,
        scope: 'APPLICANT',
      });
      expect(session).not.toHaveProperty('refreshToken');
      expect(session).not.toHaveProperty('agent');
    });

    it('the access token carries the phone hash and the applicant scope', async () => {
      const session = asApplicant(await h.signInAs());
      const claims = await h.signer.verify(session.accessToken);
      const check = validateAgentAccessClaims(claims, {
        issuer: AUTH_OPTIONS.issuer,
        audience: AUTH_OPTIONS.audience,
        now: h.clock.now(),
      });
      expect(check).toMatchObject({
        ok: true,
        claims: {
          scope: 'APPLICANT',
          sub: h.hasher.hash('PHONE', PHONE),
          exp: Math.floor(h.clock.now().getTime() / 1000) + ACCESS_TTL,
        },
      });
    });

    it('creates no agent and no refresh token', async () => {
      await h.signInAs();
      expect(
        await h.agents.findByPhoneHash(h.hasher.hash('PHONE', PHONE)),
      ).toBeNull();
      expect(await h.tokens.revokeAllForAgent('agent-1', h.clock.now())).toBe(
        0,
      );
    });

    it('remembers the verified phone, sealed, with an expiry', async () => {
      await h.signInAs();
      const stored = await h.applicants.find(h.hasher.hash('PHONE', PHONE));
      expect(stored).not.toBeNull();
      expect(stored!.phoneSealed.startsWith('v1:')).toBe(true);
      expect(stored!.phoneSealed).not.toContain('9876543210');
      expect(h.sealer.open(stored!.phoneSealed)).toBe(PHONE);
      expect(stored!.expiresAt.getTime()).toBe(
        h.clock.now().getTime() + AUTH_OPTIONS.applicantPhoneTtlSeconds * 1000,
      );
    });

    it('signing in again replaces the remembered phone rather than adding another', async () => {
      await h.signInAs();
      h.clock.advance(60_000);
      await h.signInAs();
      const stored = await h.applicants.find(h.hasher.hash('PHONE', PHONE));
      expect(stored!.expiresAt.getTime()).toBe(
        h.clock.now().getTime() + AUTH_OPTIONS.applicantPhoneTtlSeconds * 1000,
      );
    });

    it('rolls back (nothing remembered) when the token cannot be signed', async () => {
      h.signer.failing = true;
      await expect(h.signInAs()).rejects.toThrow('signer unavailable');
      expect(await h.applicants.find(h.hasher.hash('PHONE', PHONE))).toBeNull();
    });
  });

  describe('verify: existing agent', () => {
    it('gets an agent session with a refresh token and the profile', async () => {
      await h.seedAgent('ACTIVE');
      const session = asAgent(await h.signInAs());
      expect(session).toMatchObject({
        accessToken: expect.any(String) as string,
        refreshToken: expect.any(String) as string,
        expiresInSeconds: ACCESS_TTL,
        scope: 'AGENT',
        agent: {
          id: 'agent-1',
          name: 'Ravi Kumar',
          phoneMasked: '+91 98***210',
          city: 'Coimbatore',
          state: 'Tamil Nadu',
          status: 'ACTIVE',
          statusLabel: { en: 'Active', ta: '<to be supplied>' },
          rejectionReason: null,
          approvedAt: '2026-10-28',
          panLast4: null,
          payoutDetailsSet: false,
          primaryCode: null,
        },
      });
    });

    it('the access token is for the agent id with scope AGENT', async () => {
      await h.seedAgent('ACTIVE');
      const session = asAgent(await h.signInAs());
      const check = validateAgentAccessClaims(
        await h.signer.verify(session.accessToken),
        {
          issuer: AUTH_OPTIONS.issuer,
          audience: AUTH_OPTIONS.audience,
          now: h.clock.now(),
        },
      );
      expect(check).toMatchObject({
        ok: true,
        claims: { scope: 'AGENT', sub: 'agent-1' },
      });
    });

    it('stores only a keyed hash of the refresh token, with the configured lifetime', async () => {
      await h.seedAgent('ACTIVE');
      const session = asAgent(await h.signInAs());
      const stored = await h.tokens.findByHash(
        hashRefreshToken(session.refreshToken, AUTH_OPTIONS.refreshTokenPepper),
      );
      expect(stored).toMatchObject({ agentId: 'agent-1', revokedAt: null });
      expect(stored!.tokenHash).not.toContain(session.refreshToken);
      expect(stored!.expiresAt.getTime()).toBe(
        h.clock.now().getTime() + REFRESH_TTL * 1000,
      );
      expect(await h.tokens.findByHash(session.refreshToken)).toBeNull();
    });

    it('does not remember an applicant phone for an existing agent', async () => {
      await h.seedAgent('ACTIVE');
      await h.signInAs();
      expect(await h.applicants.find(h.hasher.hash('PHONE', PHONE))).toBeNull();
    });

    it('shows the primary code once the agent has one', async () => {
      await h.seedAgent('ACTIVE');
      await h.codes.create({
        id: 'code-1',
        agentId: 'agent-1',
        code: 'NM7K2P9X',
        isPrimary: true,
        isActive: true,
        createdAt: h.clock.now(),
      });
      expect(asAgent(await h.signInAs()).agent.primaryCode).toBe('NM7K2P9X');
    });

    it('the profile holds only the contract fields, nothing sealed or hashed', async () => {
      await h.seedAgent('ACTIVE', { panLast4: '234F', panSealed: 'v1:secret' });
      const { agent } = asAgent(await h.signInAs());
      expect(Object.keys(agent).sort()).toEqual(
        [
          'approvedAt',
          'city',
          'id',
          'name',
          'panLast4',
          'payoutDetailsSet',
          'phoneMasked',
          'primaryCode',
          'rejectionReason',
          'state',
          'status',
          'statusLabel',
        ].sort(),
      );
      expect(JSON.stringify(agent)).not.toContain('9876543210');
      expect(JSON.stringify(agent)).not.toContain('v1:secret');
    });

    it.each([
      ['PENDING_APPROVAL', 'Under review'],
      ['REJECTED', 'Rejected'],
      ['ACTIVE', 'Active'],
      ['SUSPENDED', 'Paused'],
      ['TERMINATED', 'Terminated'],
    ])('a %s agent signs in as an agent (%s)', async (status, label) => {
      await h.seedAgent(status, { rejectionReason: 'Incomplete details' });
      const session = asAgent(await h.signInAs());
      expect(session.scope).toBe('AGENT');
      expect(session.refreshToken).toEqual(expect.any(String));
      expect(session.agent.status).toBe(status);
      expect(session.agent.statusLabel.en).toBe(label);
      expect(session.agent.rejectionReason).toBe(
        status === 'REJECTED' ? 'Incomplete details' : null,
      );
    });

    it('a suspended agent still gets a full session (read access is decided later)', async () => {
      await h.seedAgent('SUSPENDED');
      const session = asAgent(await h.signInAs());
      expect(session.agent.status).toBe('SUSPENDED');
      expect(session.agent.statusLabel.en).toBe('Paused');
    });

    it('a terminated agent may sign in (read-only)', async () => {
      await h.seedAgent('TERMINATED');
      expect(asAgent(await h.signInAs()).agent.status).toBe('TERMINATED');
    });

    it('a status the program does not know is refused', async () => {
      await h.seedAgent('WEIRD');
      await expectServiceError(h.signInAs(), 'UNAUTHORIZED');
    });

    it('rolls back the refresh token when the access token cannot be signed', async () => {
      await h.seedAgent('ACTIVE');
      h.signer.failing = true;
      await expect(h.signInAs()).rejects.toThrow('signer unavailable');
      expect(await h.tokens.revokeAllForAgent('agent-1', h.clock.now())).toBe(
        0,
      );
    });

    it("two agents never see each other's session", async () => {
      await h.seedAgent('ACTIVE');
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000002',
      });
      expect(asAgent(await h.signInAs('+919000000002')).agent.id).toBe(
        'agent-2',
      );
      expect(asAgent(await h.signInAs(PHONE)).agent.id).toBe('agent-1');
    });
  });

  describe('refresh', () => {
    const signedIn = async (status = 'ACTIVE') => {
      await h.seedAgent(status);
      return asAgent(await h.signInAs());
    };

    it('returns a new pair and revokes the old refresh token', async () => {
      const first = await signedIn();
      h.clock.advance(60_000);
      const second = await h.signIn.refresh(first.refreshToken);
      expect(second.scope).toBe('AGENT');
      expect(second.refreshToken).not.toBe(first.refreshToken);
      expect(second.accessToken).not.toBe(first.accessToken);
      expect(second.agent.id).toBe('agent-1');
      const oldRow = await h.tokens.findByHash(
        hashRefreshToken(first.refreshToken, AUTH_OPTIONS.refreshTokenPepper),
      );
      expect(oldRow!.revokedAt).toEqual(h.clock.now());
    });

    it('the new refresh token works again (a chain of rotations)', async () => {
      let session = await signedIn();
      for (let i = 0; i < 3; i++) {
        session = await h.signIn.refresh(session.refreshToken);
      }
      expect(session.agent.id).toBe('agent-1');
    });

    it('uses the lifetimes from the settings at the moment of refresh', async () => {
      const first = await signedIn();
      h.settings.set(AGENT_ACCESS_TOKEN_TTL_SECONDS_KEY, 60);
      const second = await h.signIn.refresh(first.refreshToken);
      expect(second.expiresInSeconds).toBe(60);
    });

    it('reusing a rotated token revokes EVERY token of the agent and answers REFRESH_TOKEN_REUSED', async () => {
      const first = await signedIn();
      const second = await h.signIn.refresh(first.refreshToken);
      await expectServiceError(
        h.signIn.refresh(first.refreshToken),
        'REFRESH_TOKEN_REUSED',
      );
      // the newest token was revoked too
      await expectServiceError(
        h.signIn.refresh(second.refreshToken),
        'REFRESH_TOKEN_REUSED',
      );
    });

    it('records the reuse in the audit log, without any token', async () => {
      const first = await signedIn();
      await h.signIn.refresh(first.refreshToken);
      await expectServiceError(
        h.signIn.refresh(first.refreshToken),
        'REFRESH_TOKEN_REUSED',
      );
      expect(h.audit.entries).toEqual([
        {
          actorId: null,
          action: 'AGENT_REFRESH_TOKEN_REUSED',
          entity: 'agent',
          entityId: 'agent-1',
        },
      ]);
    });

    it("reuse revokes that agent's tokens only", async () => {
      const first = await signedIn();
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000002',
      });
      const other = asAgent(await h.signInAs('+919000000002'));
      await h.signIn.refresh(first.refreshToken);
      await expectServiceError(
        h.signIn.refresh(first.refreshToken),
        'REFRESH_TOKEN_REUSED',
      );
      await expect(h.signIn.refresh(other.refreshToken)).resolves.toBeDefined();
    });

    it('an unknown token is REFRESH_TOKEN_INVALID', async () => {
      await expectServiceError(
        h.signIn.refresh('nope'),
        'REFRESH_TOKEN_INVALID',
      );
    });

    it('an expired token is REFRESH_TOKEN_EXPIRED', async () => {
      const session = await signedIn();
      h.clock.advance(REFRESH_TTL * 1000);
      await expectServiceError(
        h.signIn.refresh(session.refreshToken),
        'REFRESH_TOKEN_EXPIRED',
      );
    });

    it('an empty token is a validation failure', async () => {
      await expectServiceError(h.signIn.refresh(''), 'VALIDATION_FAILED');
    });

    it.each([
      'PENDING_APPROVAL',
      'REJECTED',
      'ACTIVE',
      'SUSPENDED',
      'TERMINATED',
    ])('a %s agent can refresh', async (status) => {
      const session = await signedIn(status);
      await expect(
        h.signIn.refresh(session.refreshToken),
      ).resolves.toMatchObject({
        scope: 'AGENT',
      });
    });

    it('a status the program does not know cannot refresh', async () => {
      const session = await signedIn();
      await h.agents.update('agent-1', { status: 'WEIRD' as never });
      await expectServiceError(
        h.signIn.refresh(session.refreshToken),
        'REFRESH_TOKEN_INVALID',
      );
    });

    it('a token whose agent is gone is REFRESH_TOKEN_INVALID', async () => {
      const session = await signedIn();
      jest.spyOn(h.agents, 'findById').mockResolvedValueOnce(null);
      await expectServiceError(
        h.signIn.refresh(session.refreshToken),
        'REFRESH_TOKEN_INVALID',
      );
    });

    it('two uses of the same token at once: one wins, the other is REFRESH_TOKEN_REUSED and everything is revoked', async () => {
      const session = await signedIn();
      const results = await Promise.allSettled([
        h.signIn.refresh(session.refreshToken),
        h.signIn.refresh(session.refreshToken),
      ]);
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      const failed = results.find((r) => r.status === 'rejected');
      expect((failed as PromiseRejectedResult).reason).toMatchObject({
        code: 'REFRESH_TOKEN_REUSED',
      });
      const winner = results.find(
        (r): r is PromiseFulfilledResult<AgentSession> =>
          r.status === 'fulfilled',
      )!.value;
      await expectServiceError(
        h.signIn.refresh(winner.refreshToken),
        'REFRESH_TOKEN_REUSED',
      );
    });

    it('rolls the rotation back when the access token cannot be signed', async () => {
      const session = await signedIn();
      h.signer.failing = true;
      await expect(h.signIn.refresh(session.refreshToken)).rejects.toThrow(
        'signer unavailable',
      );
      h.signer.failing = false;
      await expect(
        h.signIn.refresh(session.refreshToken),
      ).resolves.toBeDefined();
    });
  });

  describe('logout', () => {
    const claimsFor = (
      sub: string,
      scope: 'AGENT' | 'APPLICANT' = 'AGENT',
    ) => ({
      sub,
      scope,
      aud: AUTH_OPTIONS.audience,
      iss: AUTH_OPTIONS.issuer,
      iat: 0,
      exp: 1,
    });

    it('revokes the given refresh token', async () => {
      await h.seedAgent('ACTIVE');
      const session = asAgent(await h.signInAs());
      await h.signIn.logout(claimsFor('agent-1'), session.refreshToken);
      const row = await h.tokens.findByHash(
        hashRefreshToken(session.refreshToken, AUTH_OPTIONS.refreshTokenPepper),
      );
      expect(row!.revokedAt).toEqual(h.clock.now());
    });

    it("leaves the agent's other sessions alone", async () => {
      await h.seedAgent('ACTIVE');
      const phone = asAgent(await h.signInAs());
      const web = asAgent(await h.signInAs());
      await h.signIn.logout(claimsFor('agent-1'), phone.refreshToken);
      await expect(h.signIn.refresh(web.refreshToken)).resolves.toBeDefined();
    });

    it('is idempotent: unknown and already-revoked tokens are fine', async () => {
      await h.seedAgent('ACTIVE');
      const session = asAgent(await h.signInAs());
      await h.signIn.logout(claimsFor('agent-1'), session.refreshToken);
      await expect(
        h.signIn.logout(claimsFor('agent-1'), session.refreshToken),
      ).resolves.toBeUndefined();
      await expect(
        h.signIn.logout(claimsFor('agent-1'), 'never-issued'),
      ).resolves.toBeUndefined();
    });

    it("does not revoke another agent's token", async () => {
      await h.seedAgent('ACTIVE');
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000002',
      });
      const victim = asAgent(await h.signInAs('+919000000002'));
      await h.signIn.logout(claimsFor('agent-1'), victim.refreshToken);
      await expect(
        h.signIn.refresh(victim.refreshToken),
      ).resolves.toBeDefined();
    });

    it('is refused for an applicant session (there is nothing to revoke)', async () => {
      await expectServiceError(
        h.signIn.logout(claimsFor('some-hash', 'APPLICANT'), 'x'),
        'UNAUTHORIZED',
      );
    });

    it('needs a refresh token', async () => {
      await expectServiceError(
        h.signIn.logout(claimsFor('agent-1'), ''),
        'VALIDATION_FAILED',
      );
    });
  });
});
