import {
  type CanActivate,
  type ExecutionContext,
  type INestApplication,
  UnauthorizedException,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe, FirebaseAuthGuard } from '@app/common';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import { AgentConfigService } from '../config/agent-config.service';
import {
  AUTH_OPTIONS,
  makeAgentHarness,
  PHONE,
  type AgentHarness,
} from '../testing/agent-test-harness';
import { AgentAuthController } from './agent-auth.controller';
import { AgentController } from './agent.controller';
import { AgentAccessGuard } from './agent-http';
import { AGENT_PROGRAM, type AgentProgram } from './agent-program';
import { MemberReferralController } from './member-referral.controller';

const SECRET = 'test-only-agent-jwt-secret-not-real-0000';
const OTHER_PHONE = '+919000000001';
const CODE = 'NM7K2P9X';
const REF_OWN = '11111111-1111-4111-8111-000000000001';
const REF_OTHER = '11111111-1111-4111-8111-000000000002';

/** The member guard stand-in: the member id comes from a test header. */
class StandInMemberGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context
      .switchToHttp()
      .getRequest<{ headers: Record<string, string>; user?: unknown }>();
    const id = req.headers['x-test-member'];
    if (!id) throw new UnauthorizedException();
    req.user = { id };
    return true;
  }
}

interface World {
  h: AgentHarness;
  program: AgentProgram;
  app: INestApplication<App>;
}

async function boot(
  over: Partial<AgentProgram> = {},
  settings: Record<string, unknown> = {},
): Promise<World> {
  let jwt!: AgentJwtTokenSigner;
  const h = makeAgentHarness(
    { 'payout.minimum_amount_paise': 50000, ...settings },
    {
      signerFor: (clock) =>
        (jwt = new AgentJwtTokenSigner(
          {
            secret: SECRET,
            issuer: AUTH_OPTIONS.issuer,
            audience: AUTH_OPTIONS.audience,
          },
          clock,
        )),
    },
  );
  const program: AgentProgram = {
    signIn: h.signIn,
    application: h.application,
    me: h.me,
    config: new AgentConfigService(h.settings, h.content, {
      getActiveHoldDays: () => Promise.resolve(14),
    }),
    referrals: h.referrals,
    referralCodes: h.referralCodes,
    tokens: jwt,
    piiSealing: true,
    requesterKey: () => 'v1:hashed-test-ip',
    ...over,
  };
  const moduleRef = await Test.createTestingModule({
    controllers: [
      AgentAuthController,
      AgentController,
      MemberReferralController,
    ],
    providers: [
      { provide: AGENT_PROGRAM, useValue: program },
      AgentAccessGuard,
    ],
  })
    .overrideGuard(FirebaseAuthGuard)
    .useClass(StandInMemberGuard)
    .compile();
  const app = moduleRef.createNestApplication<INestApplication<App>>();
  app.useGlobalPipes(
    new ApiValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  await app.init();
  return { h, program, app };
}

const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });

/** OTP request + verify over HTTP, with the fake OTP's code. */
async function signInOverHttp(w: World, phone = PHONE) {
  const sent = await request(w.app.getHttpServer())
    .post('/agent/auth/otp/request')
    .send({ phone })
    .expect(200);
  const challengeId = (sent.body as { challengeId: string }).challengeId;
  const verified = await request(w.app.getHttpServer())
    .post('/agent/auth/otp/verify')
    .send({ challengeId, code: w.h.otp.codeFor(challengeId) })
    .expect(200);
  return verified.body as {
    accessToken: string;
    refreshToken?: string;
    scope: string;
  };
}

async function agentToken(w: World, status = 'ACTIVE'): Promise<string> {
  await w.h.seedAgent(status);
  return (await signInOverHttp(w)).accessToken;
}

describe('agent routes over HTTP', () => {
  let w: World;
  afterEach(() => w?.app.close());

  describe('Accept-Version', () => {
    beforeEach(async () => (w = await boot()));

    it('missing is version 1, and every answer says Content-Version: 1', async () => {
      const res = await request(w.app.getHttpServer())
        .post('/agent/auth/otp/request')
        .send({ phone: PHONE })
        .expect(200);
      expect(res.headers['content-version']).toBe('1');
    });

    it('1 is accepted; anything else is 406 UNSUPPORTED_VERSION, also on member routes', async () => {
      await request(w.app.getHttpServer())
        .post('/agent/auth/otp/request')
        .set('Accept-Version', '1')
        .send({ phone: PHONE })
        .expect(200);
      for (const path of [
        '/agent/auth/otp/request',
        '/referrals/codes/validate',
      ]) {
        const res = await request(w.app.getHttpServer())
          .post(path)
          .set('Accept-Version', '2')
          .send({});
        expect(res.status).toBe(406);
        expect(res.body).toMatchObject({ code: 'UNSUPPORTED_VERSION' });
        expect(res.headers['content-version']).toBe('1');
      }
    });
  });

  describe('POST /agent/auth/otp/request and /verify', () => {
    beforeEach(async () => (w = await boot()));

    it('request answers the challenge and the resend time from settings', async () => {
      const res = await request(w.app.getHttpServer())
        .post('/agent/auth/otp/request')
        .send({ phone: PHONE })
        .expect(200);
      expect(res.body).toEqual({
        challengeId: expect.any(String) as string,
        expiresInSeconds: 300,
        resendAfterSeconds: 30,
      });
    });

    it('a bad, missing or extra field is 400 VALIDATION_FAILED', async () => {
      for (const body of [{ phone: '98765' }, {}, { phone: PHONE, x: 1 }]) {
        const res = await request(w.app.getHttpServer())
          .post('/agent/auth/otp/request')
          .send(body);
        expect(res.status).toBe(400);
        expect(res.body).toMatchObject({ code: 'VALIDATION_FAILED' });
      }
    });

    it('too many requests is 429 RATE_LIMITED with Retry-After', async () => {
      const send = () =>
        request(w.app.getHttpServer())
          .post('/agent/auth/otp/request')
          .send({ phone: PHONE });
      for (let i = 0; i < 3; i++) await send().expect(200);
      const res = await send();
      expect(res.status).toBe(429);
      expect(res.body).toMatchObject({ code: 'RATE_LIMITED' });
      expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
    });

    it('a wrong code is 401 OTP_INVALID', async () => {
      const sent = await request(w.app.getHttpServer())
        .post('/agent/auth/otp/request')
        .send({ phone: PHONE });
      const res = await request(w.app.getHttpServer())
        .post('/agent/auth/otp/verify')
        .send({
          challengeId: (sent.body as { challengeId: string }).challengeId,
          code: '000000',
        });
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({ code: 'OTP_INVALID' });
    });

    it('a new phone gets an APPLICANT session (no refresh token); an agent an AGENT session', async () => {
      const applicant = await signInOverHttp(w);
      expect(applicant.scope).toBe('APPLICANT');
      expect(applicant.refreshToken).toBeUndefined();
      await w.h.seedAgent('PENDING_APPROVAL', {
        id: 'agent-2',
        phoneE164: OTHER_PHONE,
      });
      const agent = await signInOverHttp(w, OTHER_PHONE);
      expect(agent.scope).toBe('AGENT');
      expect(typeof agent.refreshToken).toBe('string');
    });
  });

  describe('refresh and logout', () => {
    beforeEach(async () => (w = await boot()));

    it('refresh rotates; the old token again is 401 REFRESH_TOKEN_REUSED', async () => {
      await w.h.seedAgent('ACTIVE');
      const first = await signInOverHttp(w);
      const next = await request(w.app.getHttpServer())
        .post('/agent/auth/refresh')
        .send({ refreshToken: first.refreshToken })
        .expect(200);
      expect((next.body as { scope: string }).scope).toBe('AGENT');
      const again = await request(w.app.getHttpServer())
        .post('/agent/auth/refresh')
        .send({ refreshToken: first.refreshToken });
      expect(again.status).toBe(401);
      expect(again.body).toMatchObject({ code: 'REFRESH_TOKEN_REUSED' });
    });

    it('an unknown refresh token is 401 REFRESH_TOKEN_INVALID; none is 400', async () => {
      const res = await request(w.app.getHttpServer())
        .post('/agent/auth/refresh')
        .send({ refreshToken: 'not-a-token' });
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({ code: 'REFRESH_TOKEN_INVALID' });
      await request(w.app.getHttpServer())
        .post('/agent/auth/refresh')
        .send({})
        .expect(400);
    });

    it('logout is 204 with the agent token, 401 without', async () => {
      await w.h.seedAgent('ACTIVE');
      const s = await signInOverHttp(w);
      await request(w.app.getHttpServer())
        .post('/agent/auth/logout')
        .send({ refreshToken: s.refreshToken })
        .expect(401);
      await request(w.app.getHttpServer())
        .post('/agent/auth/logout')
        .set(bearer(s.accessToken))
        .send({ refreshToken: s.refreshToken })
        .expect(204);
    });
  });

  describe('the agent token guard', () => {
    beforeEach(async () => (w = await boot()));

    it('no token, a non-Bearer header or a tampered token is 401 UNAUTHORIZED', async () => {
      const token = await agentToken(w);
      const tampered = `${token.slice(0, -2)}${token.endsWith('AA') ? 'BB' : 'AA'}`;
      for (const headers of [
        {},
        { Authorization: `Basic ${token}` },
        { Authorization: `Bearer ${token} extra` },
        bearer(tampered),
      ]) {
        const res = await request(w.app.getHttpServer())
          .get('/agent/me')
          .set(headers);
        expect(res.status).toBe(401);
        expect(res.body).toMatchObject({ code: 'UNAUTHORIZED' });
      }
    });

    it('a token signed with another secret is 401 UNAUTHORIZED, never TOKEN_EXPIRED', async () => {
      const token = await agentToken(w);
      const other = new AgentJwtTokenSigner(
        {
          secret: 'another-test-only-secret-not-real-00000',
          issuer: AUTH_OPTIONS.issuer,
          audience: AUTH_OPTIONS.audience,
        },
        w.h.clock,
      );
      const claims = await w.h.claimsOf({ accessToken: token });
      const forged = await other.sign({ ...claims, exp: claims.iat + 1 });
      w.h.clock.advance(3_600_000);
      const res = await request(w.app.getHttpServer())
        .get('/agent/me')
        .set(bearer(forged));
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({ code: 'UNAUTHORIZED' });
    });

    it('a genuine expired token is 401 TOKEN_EXPIRED', async () => {
      const token = await agentToken(w);
      w.h.clock.advance(901_000);
      const res = await request(w.app.getHttpServer())
        .get('/agent/me')
        .set(bearer(token));
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({ code: 'TOKEN_EXPIRED' });
    });

    it('an APPLICANT token can call only the application and GET /agent/me (404)', async () => {
      const applicant = (await signInOverHttp(w)).accessToken;
      const me = await request(w.app.getHttpServer())
        .get('/agent/me')
        .set(bearer(applicant));
      expect(me.status).toBe(404);
      expect(me.body).toMatchObject({ code: 'AGENT_NOT_FOUND' });
      const refused: Array<[string, string]> = [
        ['get', '/agent/config'],
        ['get', '/agent/referral-links'],
        ['get', '/agent/referrals'],
        ['get', `/agent/referrals/${REF_OWN}`],
        ['patch', '/agent/me/payout-details'],
        ['post', '/agent/auth/logout'],
      ];
      for (const [method, path] of refused) {
        const res = await request(w.app.getHttpServer())
          [method as 'get'](path)
          .set(bearer(applicant))
          .send({ upi: { vpa: 'ravi@okbank' }, refreshToken: 'x' });
        expect([path, res.status]).toEqual([path, 401]);
      }
    });
  });

  describe('POST /agent/application', () => {
    beforeEach(async () => (w = await boot()));

    it('an applicant gets 201 and an AGENT session; applying again is 409 APPLICATION_EXISTS', async () => {
      const applicant = (await signInOverHttp(w)).accessToken;
      const res = await request(w.app.getHttpServer())
        .post('/agent/application')
        .set(bearer(applicant))
        .send({ name: 'Ravi Kumar', city: 'Coimbatore', state: 'Tamil Nadu' })
        .expect(201);
      const session = res.body as {
        scope: string;
        accessToken: string;
        agent: { status: string };
      };
      expect(session.scope).toBe('AGENT');
      expect(session.agent.status).toBe('PENDING_APPROVAL');
      const again = await request(w.app.getHttpServer())
        .post('/agent/application')
        .set(bearer(session.accessToken))
        .send({ name: 'Ravi Kumar', city: 'Coimbatore', state: 'Tamil Nadu' });
      expect(again.status).toBe(409);
      expect(again.body).toMatchObject({
        code: 'APPLICATION_EXISTS',
        agentStatus: 'PENDING_APPROVAL',
      });
    });

    it('a bad body is 400', async () => {
      const applicant = (await signInOverHttp(w)).accessToken;
      for (const body of [
        { name: 'Ravi Kumar', city: 'Coimbatore' },
        { name: 'Ravi', city: 'C', state: 'T', pan: 'nope' },
        { name: 'Ravi', city: 'C', state: 'T', phone: PHONE },
      ]) {
        const res = await request(w.app.getHttpServer())
          .post('/agent/application')
          .set(bearer(applicant))
          .send(body);
        expect(res.status).toBe(400);
        expect(res.body).toMatchObject({ code: 'VALIDATION_FAILED' });
      }
    });
  });

  describe('GET /agent/me and PATCH /agent/me/payout-details', () => {
    beforeEach(async () => (w = await boot()));

    it('me is the caller own profile', async () => {
      const token = await agentToken(w);
      const res = await request(w.app.getHttpServer())
        .get('/agent/me')
        .set(bearer(token))
        .expect(200);
      expect(res.body).toMatchObject({ id: 'agent-1', status: 'ACTIVE' });
    });

    it('ACTIVE saves a masked summary; PENDING_APPROVAL is 403 AGENT_NOT_ACTIVE', async () => {
      const token = await agentToken(w);
      const ok = await request(w.app.getHttpServer())
        .patch('/agent/me/payout-details')
        .set(bearer(token))
        .send({ upi: { vpa: 'ravi@okbank' } })
        .expect(200);
      expect(JSON.stringify(ok.body)).not.toContain('ravi@okbank');

      await w.app.close();
      w = await boot();
      const pending = await agentToken(w, 'PENDING_APPROVAL');
      const res = await request(w.app.getHttpServer())
        .patch('/agent/me/payout-details')
        .set(bearer(pending))
        .send({ upi: { vpa: 'ravi@okbank' } });
      expect(res.status).toBe(403);
      expect(res.body).toMatchObject({
        code: 'AGENT_NOT_ACTIVE',
        agentStatus: 'PENDING_APPROVAL',
      });
    });

    it('an extra nested field is 400', async () => {
      const token = await agentToken(w);
      await request(w.app.getHttpServer())
        .patch('/agent/me/payout-details')
        .set(bearer(token))
        .send({ upi: { vpa: 'ravi@okbank', extra: 1 } })
        .expect(400);
    });
  });

  describe('GET /agent/config', () => {
    it('answers the displayed settings, read at request time', async () => {
      w = await boot();
      const token = await agentToken(w, 'PENDING_APPROVAL');
      await request(w.app.getHttpServer())
        .get('/agent/config')
        .set(bearer(token))
        .expect(200);
    });

    it('with no commission policy yet it is 503 AGENT_PROGRAM_UNAVAILABLE', async () => {
      const first = await boot();
      w = await boot({
        config: new AgentConfigService(first.h.settings, first.h.content, {
          getActiveHoldDays: () => Promise.resolve(null),
        }),
      });
      await first.app.close();
      const token = await agentToken(w);
      const res = await request(w.app.getHttpServer())
        .get('/agent/config')
        .set(bearer(token));
      expect(res.status).toBe(503);
      expect(res.body).toMatchObject({ code: 'AGENT_PROGRAM_UNAVAILABLE' });
    });
  });

  describe('referral links and referrals (own agent only)', () => {
    beforeEach(async () => (w = await boot()));

    it('links are 200 for an ACTIVE agent', async () => {
      const token = await agentToken(w);
      const res = await request(w.app.getHttpServer())
        .get('/agent/referral-links')
        .set(bearer(token))
        .expect(200);
      expect(res.body).toHaveProperty('items');
    });

    it('the list and the detail show only the caller own referrals', async () => {
      const token = await agentToken(w);
      await w.h.seedReferral({ id: REF_OWN, agentId: 'agent-1' });
      await w.h.seedReferral({ id: REF_OTHER, agentId: 'agent-2' });
      const list = await request(w.app.getHttpServer())
        .get('/agent/referrals')
        .set(bearer(token))
        .expect(200);
      const ids = (list.body as { items: Array<{ id: string }> }).items.map(
        (i) => i.id,
      );
      expect(ids).toEqual([REF_OWN]);
      await request(w.app.getHttpServer())
        .get(`/agent/referrals/${REF_OWN}`)
        .set(bearer(token))
        .expect(200);
      const other = await request(w.app.getHttpServer())
        .get(`/agent/referrals/${REF_OTHER}`)
        .set(bearer(token));
      expect(other.status).toBe(404);
      expect(other.body).toMatchObject({ code: 'REFERRAL_NOT_FOUND' });
    });

    it('a non-uuid id, a bad limit or a bad stage is 400 VALIDATION_FAILED', async () => {
      const token = await agentToken(w);
      for (const path of [
        '/agent/referrals/not-a-uuid',
        '/agent/referrals?limit=0',
        '/agent/referrals?limit=51',
        '/agent/referrals?stage=PAID',
      ]) {
        const res = await request(w.app.getHttpServer())
          .get(path)
          .set(bearer(token));
        expect([path, res.status]).toEqual([path, 400]);
        expect(res.body).toMatchObject({ code: 'VALIDATION_FAILED' });
      }
    });
  });

  describe('member routes', () => {
    beforeEach(async () => {
      w = await boot();
      await w.h.seedAgent('ACTIVE');
      await w.h.codes.create({
        id: 'code-1',
        agentId: 'agent-1',
        code: CODE,
        isPrimary: true,
        isActive: true,
        createdAt: new Date('2026-10-28T10:00:00.000Z'),
      });
    });

    it('validate needs no token: valid and invalid look as the contract says', async () => {
      const ok = await request(w.app.getHttpServer())
        .post('/referrals/codes/validate')
        .send({ code: CODE })
        .expect(200);
      expect(ok.body).toEqual({ valid: true, agentDisplayName: 'Ravi K.' });
      const bad = await request(w.app.getHttpServer())
        .post('/referrals/codes/validate')
        .send({ code: 'NM0000000' })
        .expect(200);
      expect(bad.body).toEqual({ valid: false, agentDisplayName: null });
      await request(w.app.getHttpServer())
        .post('/referrals/codes/validate')
        .send({})
        .expect(400);
    });

    it('validate over the attempt limit is 429 with Retry-After', async () => {
      let last = 200;
      let retryAfter: string | undefined;
      for (let i = 0; i < 6 && last === 200; i++) {
        const res = await request(w.app.getHttpServer())
          .post('/referrals/codes/validate')
          .send({ code: CODE });
        last = res.status;
        retryAfter = String(res.headers['retry-after']);
      }
      expect(last).toBe(429);
      expect(Number(retryAfter)).toBeGreaterThan(0);
    });

    it('attach needs the member token, then credits once', async () => {
      w.h.seedMember('member-1');
      await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .send({ code: CODE })
        .expect(401);
      const ok = await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .set('x-test-member', 'member-1')
        .send({ code: CODE })
        .expect(200);
      expect(ok.body).toMatchObject({
        attached: true,
        agentDisplayName: 'Ravi K.',
      });
      const again = await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .set('x-test-member', 'member-1')
        .send({ code: CODE });
      expect(again.status).toBe(409);
      expect(again.body).toMatchObject({ code: 'ALREADY_ATTRIBUTED' });
    });

    it('attach refusals: unknown code 404, own phone 422 SELF_REFERRAL, no phone 422', async () => {
      w.h.seedMember('member-2');
      const unknown = await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .set('x-test-member', 'member-2')
        .send({ code: 'NM2K2P9A' });
      expect(unknown.status).toBe(404);
      expect(unknown.body).toMatchObject({ code: 'CODE_NOT_FOUND' });

      w.h.seedMember('member-self', {
        phoneHash: w.h.hasher.hash('PHONE', PHONE),
      });
      const self = await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .set('x-test-member', 'member-self')
        .send({ code: CODE });
      expect(self.status).toBe(422);
      expect(self.body).toMatchObject({ code: 'SELF_REFERRAL' });

      w.h.seedMember('member-nophone', { phoneHash: null });
      const nophone = await request(w.app.getHttpServer())
        .post('/registration/referral-code')
        .set('x-test-member', 'member-nophone')
        .send({ code: CODE });
      expect(nophone.status).toBe(422);
      expect(nophone.body).toMatchObject({ code: 'PHONE_NOT_VERIFIED' });
    });
  });

  describe('missing secret or key', () => {
    it('no AGENT_JWT_SECRET: sign-in, refresh and every guarded route are 503', async () => {
      w = await boot({ tokens: null });
      for (const [method, path, body] of [
        ['post', '/agent/auth/otp/request', { phone: PHONE }],
        [
          'post',
          '/agent/auth/otp/verify',
          { challengeId: 'c', code: '123456' },
        ],
        ['post', '/agent/auth/refresh', { refreshToken: 'r' }],
        ['get', '/agent/me', {}],
        ['get', '/agent/config', {}],
      ] as const) {
        const res = await request(w.app.getHttpServer())
          [method](path)
          .send(body);
        expect([path, res.status, (res.body as { code: string }).code]).toEqual(
          [path, 503, 'AGENT_PROGRAM_UNAVAILABLE'],
        );
      }
    });

    it('no AGENT_PII_ENCRYPTION_KEY: OTP, application and payout details are 503, before any OTP is sent', async () => {
      w = await boot({ piiSealing: false });
      const sendSpy = jest.spyOn(w.h.otp, 'send');
      const res = await request(w.app.getHttpServer())
        .post('/agent/auth/otp/request')
        .send({ phone: PHONE });
      expect(res.status).toBe(503);
      expect(sendSpy).not.toHaveBeenCalled();
    });
  });
});
