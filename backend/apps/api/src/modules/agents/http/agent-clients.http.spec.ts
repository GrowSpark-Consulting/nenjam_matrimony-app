import { type INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe } from '@app/common';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import { AgentClientDraftService } from '../clients/agent-client-draft.service';
import { AgentConfigService } from '../config/agent-config.service';
import { AGENT_CLIENTS_ENABLED_KEY } from '../settings/agent-clients-switch';
import { AGENT_CLIENT_DRAFT_LIMIT_KEY } from '../settings/agent-program-settings';
import { FakeAgentSettings } from '../testing/fake-agent-platform';
import {
  AUTH_OPTIONS,
  CLIENT_DETAILS,
  CLIENT_DETAILS_SEEN,
  CLIENT_PHONE,
  CLIENT_PHONE_2,
  CLIENT_TOKEN_OPTIONS,
  makeAgentHarness,
  PHONE,
  UNAPPROVED_PHONE,
  type AgentHarness,
} from '../testing/agent-test-harness';
import { AgentClientsController } from './agent-clients.controller';
import { AgentController } from './agent.controller';
import { AgentAccessGuard, ClientInviteGuard } from './agent-http';
import { AGENT_PROGRAM, type AgentProgram } from './agent-program';
import { ClientInvitesController } from './client-invites.controller';

const SECRET = 'test-only-agent-jwt-secret-not-real-0000';
/** CLIENT_DETAILS with the last name changed. */
const RAMAN = {
  ...CLIENT_DETAILS,
  basicDetails: { ...CLIENT_DETAILS.basicDetails, lastName: 'Raman' },
};
const NO_SUCH = '11111111-1111-4111-8111-000000000009';

interface World {
  h: AgentHarness;
  program: AgentProgram;
  app: INestApplication<App>;
}

async function boot(over: Partial<AgentProgram> = {}): Promise<World> {
  let jwt!: AgentJwtTokenSigner;
  let clientJwt!: AgentJwtTokenSigner;
  const h = makeAgentHarness(
    { 'payout.minimum_amount_paise': 50000 },
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
      // The same secret on purpose: only the audience and scope keep the
      // two tokens apart.
      clientSignerFor: (clock) =>
        (clientJwt = new AgentJwtTokenSigner(
          { secret: SECRET, ...CLIENT_TOKEN_OPTIONS, scopes: ['CLIENT'] },
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
    money: h.money,
    // Real ids: the routes take a UUID.
    clients: new AgentClientDraftService({
      access: h.me,
      drafts: h.drafts,
      attributions: h.attributions,
      accounts: h.clientAccount,
      proof: h.clientProof,
      referenceData: h.referenceData,
      hasher: h.hasher,
      sealer: h.sealer,
      settings: h.settings,
      content: h.content,
      uow: h.uow,
      audit: h.audit,
      clock: h.clock,
    }),
    clientInvites: h.clientInvites,
    tokens: jwt,
    clientTokens: clientJwt,
    piiSealing: true,
    requesterKey: () => 'v1:hashed-test-ip',
    ...over,
  };
  const moduleRef = await Test.createTestingModule({
    controllers: [
      AgentClientsController,
      ClientInvitesController,
      AgentController,
    ],
    providers: [
      { provide: AGENT_PROGRAM, useValue: program },
      AgentAccessGuard,
      ClientInviteGuard,
    ],
  }).compile();
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
const http = (w: World) => request(w.app.getHttpServer());

async function agentToken(
  w: World,
  status = 'ACTIVE',
  phone = PHONE,
  id = 'agent-1',
) {
  await w.h.seedAgent(status, { id, phoneE164: phone });
  return (await w.h.signInAs(phone)).accessToken;
}

async function addClient(w: World, token: string, phone = CLIENT_PHONE) {
  const res = await http(w)
    .post('/agent/clients')
    .set(bearer(token))
    .send({ phone, consentConfirmed: true, details: CLIENT_DETAILS })
    .expect(201);
  return (res.body as { id: string }).id;
}

/** A client's request + verify over HTTP, with the code she would have received. */
async function clientToken(w: World, phone = CLIENT_PHONE) {
  await http(w).post('/client-invites/otp/request').send({ phone }).expect(200);
  const pointer = await w.h.consentCodes.find([
    w.h.hasher.hash('PHONE', phone),
  ]);
  const res = await http(w)
    .post('/client-invites/otp/verify')
    .send({ phone, code: w.h.otp.codeFor(pointer!.challengeId) })
    .expect(200);
  return (res.body as { accessToken: string }).accessToken;
}

describe('agent-added clients over HTTP', () => {
  let w: World;
  afterEach(() => w?.app.close());

  describe('the whole flow', () => {
    beforeEach(async () => (w = await boot()));

    it('add, edit, submit; the client verifies, sees it and accepts; the agent sees ACCEPTED', async () => {
      const agent = await agentToken(w);
      const created = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send({
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: CLIENT_DETAILS,
        })
        .expect(201);
      expect(created.headers['content-version']).toBe('1');
      expect(created.body).toMatchObject({
        status: 'DRAFT',
        displayName: 'Priya S.',
        phoneMasked: '+91 90***001',
        details: CLIENT_DETAILS,
        editable: true,
      });
      const id = (created.body as { id: string }).id;

      await http(w)
        .patch(`/agent/clients/${id}`)
        .set(bearer(agent))
        .send({ details: RAMAN })
        .expect(200);
      const submitted = await http(w)
        .post(`/agent/clients/${id}/submit`)
        .set(bearer(agent))
        .expect(200);
      expect(submitted.body).toMatchObject({
        status: 'WAITING_FOR_CLIENT',
        displayName: 'Priya R.',
        editable: false,
      });

      const sent = await http(w)
        .post('/client-invites/otp/request')
        .send({ phone: CLIENT_PHONE })
        .expect(200);
      expect(sent.body).toEqual({
        expiresInSeconds: 300,
        resendAfterSeconds: 30,
      });
      const client = await clientToken(w);
      const invites = await http(w)
        .get('/client-invites')
        .set(bearer(client))
        .expect(200);
      expect(invites.body).toEqual({
        items: [
          {
            id,
            agentDisplayName: 'Ravi K.',
            details: {
              ...CLIENT_DETAILS_SEEN,
              basicDetails: RAMAN.basicDetails,
            },
            expiresOn: '2026-11-11',
            referredMemberDiscountPercent: 5,
          },
        ],
      });

      const accepted = await http(w)
        .post(`/client-invites/${id}/accept`)
        .set(bearer(client))
        .expect(200);
      expect(accepted.body).toEqual({
        firebaseCustomToken: 'custom-token-firebase-uid-1-1',
        agentDisplayName: 'Ravi K.',
        windowEndsAt: '2026-12-27',
      });
      const seen = await http(w)
        .get(`/agent/clients/${id}`)
        .set(bearer(agent))
        .expect(200);
      expect(seen.body).toMatchObject({
        status: 'ACCEPTED',
        details: null,
        acceptedOn: '2026-10-28',
        referralId: 'client-attribution-1',
      });
    });

    it('lists with a cursor and a status filter', async () => {
      const agent = await agentToken(w);
      await addClient(w, agent);
      w.h.clock.advance(1000);
      await addClient(w, agent, CLIENT_PHONE_2);
      const page = await http(w)
        .get('/agent/clients?limit=1')
        .set(bearer(agent))
        .expect(200);
      const body = page.body as { items: unknown[]; nextCursor: string };
      expect(body.items).toHaveLength(1);
      const rest = await http(w)
        .get(`/agent/clients?limit=1&cursor=${body.nextCursor}`)
        .set(bearer(agent))
        .expect(200);
      expect((rest.body as { nextCursor: unknown }).nextCursor).toBeNull();
      const drafts = await http(w)
        .get('/agent/clients?status=WAITING_FOR_CLIENT')
        .set(bearer(agent))
        .expect(200);
      expect((drafts.body as { items: unknown[] }).items).toEqual([]);
      await http(w)
        .get('/agent/clients?status=OPEN')
        .set(bearer(agent))
        .expect(400);
    });

    it('discard is 204; reject is 204, again 204, and that agent can never add the phone again', async () => {
      const agent = await agentToken(w);
      const draft = await addClient(w, agent, CLIENT_PHONE_2);
      await http(w)
        .delete(`/agent/clients/${draft}`)
        .set(bearer(agent))
        .expect(204);
      const id = await addClient(w, agent);
      await http(w)
        .post(`/agent/clients/${id}/submit`)
        .set(bearer(agent))
        .expect(200);
      const client = await clientToken(w);
      await http(w)
        .post(`/client-invites/${id}/reject`)
        .set(bearer(client))
        .expect(204);
      await http(w)
        .post(`/client-invites/${id}/reject`)
        .set(bearer(client))
        .expect(204);
      const again = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send({
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: CLIENT_DETAILS,
        })
        .expect(422);
      expect(again.body).toEqual({
        statusCode: 422,
        error: 'Unprocessable Entity',
        code: 'CLIENT_PHONE_UNAVAILABLE',
        message: 'This phone number cannot be added.',
      });
    });
  });

  describe('agent.clients_enabled off', () => {
    beforeEach(async () => (w = await boot()));

    it('every one of the 11 routes answers 403 CLIENT_INVITES_DISABLED (with a valid token where one is needed)', async () => {
      const agent = await agentToken(w);
      const id = await addClient(w, agent);
      await http(w)
        .post(`/agent/clients/${id}/submit`)
        .set(bearer(agent))
        .expect(200);
      const client = await clientToken(w);
      w.h.settings.remove(AGENT_CLIENTS_ENABLED_KEY);
      const calls = [
        () =>
          http(w).post('/agent/clients').set(bearer(agent)).send({
            phone: CLIENT_PHONE_2,
            consentConfirmed: true,
            details: CLIENT_DETAILS,
          }),
        () => http(w).get('/agent/clients').set(bearer(agent)),
        () => http(w).get(`/agent/clients/${id}`).set(bearer(agent)),
        () =>
          http(w)
            .patch(`/agent/clients/${id}`)
            .set(bearer(agent))
            .send({ details: CLIENT_DETAILS }),
        () => http(w).delete(`/agent/clients/${id}`).set(bearer(agent)),
        () => http(w).post(`/agent/clients/${id}/submit`).set(bearer(agent)),
        () =>
          http(w)
            .post('/client-invites/otp/request')
            .send({ phone: CLIENT_PHONE }),
        () =>
          http(w)
            .post('/client-invites/otp/verify')
            .send({ phone: CLIENT_PHONE, code: '123456' }),
        () => http(w).get('/client-invites').set(bearer(client)),
        () => http(w).post(`/client-invites/${id}/accept`).set(bearer(client)),
        () => http(w).post(`/client-invites/${id}/reject`).set(bearer(client)),
      ];
      for (const call of calls) {
        const res = await call();
        expect([res.status, (res.body as { code?: string }).code]).toEqual([
          403,
          'CLIENT_INVITES_DISABLED',
        ]);
      }
    });

    it('/agent/config still answers 200 and says clients are not enabled', async () => {
      const agent = await agentToken(w);
      w.h.settings.set(AGENT_CLIENTS_ENABLED_KEY, false);
      const res = await http(w)
        .get('/agent/config')
        .set(bearer(agent))
        .expect(200);
      expect((res.body as { clients: unknown }).clients).toEqual({
        enabled: false,
        draftLimit: 3,
        expiryDays: 14,
      });
    });
  });

  describe('/agent/config never fails because of Way 2', () => {
    beforeEach(async () => (w = await boot()));

    it('shows the client labels and the settings while on', async () => {
      const agent = await agentToken(w);
      const res = await http(w)
        .get('/agent/config')
        .set(bearer(agent))
        .expect(200);
      expect(res.body).toMatchObject({
        clients: { enabled: true, draftLimit: 3, expiryDays: 14 },
        clientStatusLabels: {
          WAITING_FOR_CLIENT: { en: 'Waiting for client' },
        },
      });
    });

    it('a missing or bad Way 2 setting: 200, enabled false, the number null', async () => {
      const agent = await agentToken(w);
      w.h.settings.remove(AGENT_CLIENT_DRAFT_LIMIT_KEY);
      let res = await http(w)
        .get('/agent/config')
        .set(bearer(agent))
        .expect(200);
      expect((res.body as { clients: unknown }).clients).toEqual({
        enabled: false,
        draftLimit: null,
        expiryDays: 14,
      });
      w.h.settings.set(AGENT_CLIENT_DRAFT_LIMIT_KEY, 'ten');
      res = await http(w).get('/agent/config').set(bearer(agent)).expect(200);
      expect(
        (res.body as { clients: { draftLimit: unknown } }).clients.draftLimit,
      ).toBeNull();
    });

    it('Way 2 settings that cannot be read at all: still 200', async () => {
      const agent = await agentToken(w);
      // The config's own settings still read fine; only Way 2's fail.
      const readable = new FakeAgentSettings({
        'referral.credit_window_days': 60,
        'payout.minimum_amount_paise': 50000,
        'referral.member_discount_bps': 500,
      });
      jest
        .spyOn(w.h.settings, 'getMany')
        .mockImplementation((keys) =>
          keys.includes(AGENT_CLIENTS_ENABLED_KEY)
            ? Promise.reject(new Error('settings unavailable'))
            : readable.getMany(keys),
        );
      const res = await http(w)
        .get('/agent/config')
        .set(bearer(agent))
        .expect(200);
      expect((res.body as { clients: unknown }).clients).toEqual({
        enabled: false,
        draftLimit: null,
        expiryDays: null,
      });
    });
  });

  describe('the two tokens never pass for each other', () => {
    beforeEach(async () => (w = await boot()));

    it('a client token is 401 on every agent route; an agent token is 401 on the client routes', async () => {
      const agent = await agentToken(w);
      const client = await clientToken(w);
      for (const path of ['/agent/clients', '/agent/me', '/agent/config']) {
        const res = await http(w).get(path).set(bearer(client));
        expect([
          path,
          res.status,
          (res.body as { code?: string }).code,
        ]).toEqual([path, 401, 'UNAUTHORIZED']);
      }
      const res = await http(w).get('/client-invites').set(bearer(agent));
      expect(res.status).toBe(401);
      expect(res.body).toMatchObject({
        code: 'UNAUTHORIZED',
        message: 'A valid client token is required.',
      });
      await http(w)
        .post(`/client-invites/${NO_SUCH}/accept`)
        .set(bearer(agent))
        .expect(401);
      await http(w).get('/client-invites').expect(401);
    });

    it('an expired client token is TOKEN_EXPIRED', async () => {
      const client = await clientToken(w);
      w.h.clock.advance(900_000);
      const res = await http(w)
        .get('/client-invites')
        .set(bearer(client))
        .expect(401);
      expect(res.body).toMatchObject({ code: 'TOKEN_EXPIRED' });
    });
  });

  describe('refusals over HTTP', () => {
    beforeEach(async () => (w = await boot()));

    it('a phone that is not an approved test number is 503 OTP_DELIVERY_UNAVAILABLE, on add and on request', async () => {
      const agent = await agentToken(w);
      const add = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send({
          phone: UNAPPROVED_PHONE,
          consentConfirmed: true,
          details: CLIENT_DETAILS,
        })
        .expect(503);
      expect(add.body).toMatchObject({ code: 'OTP_DELIVERY_UNAVAILABLE' });
      const req = await http(w)
        .post('/client-invites/otp/request')
        .send({ phone: UNAPPROVED_PHONE })
        .expect(503);
      expect(req.body).toMatchObject({ code: 'OTP_DELIVERY_UNAVAILABLE' });
    });

    it('validation: an extra property, a missing field, a bad id', async () => {
      const agent = await agentToken(w);
      for (const body of [
        {
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: { ...CLIENT_DETAILS, caste: 'x' },
        },
        {
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: { firstName: 'Priya' },
        },
        {
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: CLIENT_DETAILS,
          agentId: 'x',
        },
        { phone: '12345', consentConfirmed: true, details: CLIENT_DETAILS },
      ]) {
        const res = await http(w)
          .post('/agent/clients')
          .set(bearer(agent))
          .send(body);
        expect([res.status, (res.body as { code?: string }).code]).toEqual([
          400,
          'VALIDATION_FAILED',
        ]);
      }
      await http(w)
        .get('/agent/clients/not-a-uuid')
        .set(bearer(agent))
        .expect(400);
    });

    it('409 CLIENT_DRAFT_EXISTS, 422 CLIENT_DRAFT_LIMIT_REACHED, 409 CLIENT_DRAFT_LOCKED, 404 CLIENT_DRAFT_NOT_FOUND', async () => {
      const agent = await agentToken(w);
      const id = await addClient(w, agent);
      const code = async (res: request.Test) => {
        const r = await res;
        return [r.status, (r.body as { code?: string }).code];
      };
      expect(
        await code(
          http(w).post('/agent/clients').set(bearer(agent)).send({
            phone: CLIENT_PHONE,
            consentConfirmed: true,
            details: CLIENT_DETAILS,
          }),
        ),
      ).toEqual([409, 'CLIENT_DRAFT_EXISTS']);
      w.h.settings.set(AGENT_CLIENT_DRAFT_LIMIT_KEY, 1);
      expect(
        await code(
          http(w).post('/agent/clients').set(bearer(agent)).send({
            phone: CLIENT_PHONE_2,
            consentConfirmed: true,
            details: CLIENT_DETAILS,
          }),
        ),
      ).toEqual([422, 'CLIENT_DRAFT_LIMIT_REACHED']);
      await http(w)
        .post(`/agent/clients/${id}/submit`)
        .set(bearer(agent))
        .expect(200);
      expect(
        await code(
          http(w)
            .patch(`/agent/clients/${id}`)
            .set(bearer(agent))
            .send({ details: CLIENT_DETAILS }),
        ),
      ).toEqual([409, 'CLIENT_DRAFT_LOCKED']);
      expect(
        await code(http(w).get(`/agent/clients/${NO_SUCH}`).set(bearer(agent))),
      ).toEqual([404, 'CLIENT_DRAFT_NOT_FOUND']);
      const other = await agentToken(w, 'ACTIVE', UNAPPROVED_PHONE, 'agent-2');
      expect(
        await code(http(w).get(`/agent/clients/${id}`).set(bearer(other))),
      ).toEqual([404, 'CLIENT_DRAFT_NOT_FOUND']);
    });

    it('a paused agent: reads work, adding is 403 AGENT_NOT_ACTIVE with the status', async () => {
      const agent = await agentToken(w, 'SUSPENDED');
      await http(w).get('/agent/clients').set(bearer(agent)).expect(200);
      const res = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send({
          phone: CLIENT_PHONE,
          consentConfirmed: true,
          details: CLIENT_DETAILS,
        })
        .expect(403);
      expect(res.body).toMatchObject({
        code: 'AGENT_NOT_ACTIVE',
        agentStatus: 'SUSPENDED',
      });
    });

    it('the client side: 401 OTP_INVALID, 429 with Retry-After, 404 INVITE_NOT_FOUND, 409 INVITE_UNAVAILABLE and ALREADY_MEMBER', async () => {
      const agent = await agentToken(w);
      const wrong = await http(w)
        .post('/client-invites/otp/verify')
        .send({ phone: CLIENT_PHONE, code: '999999' })
        .expect(401);
      expect(wrong.body).toMatchObject({ code: 'OTP_INVALID' });
      const id = await addClient(w, agent);
      await http(w)
        .post(`/agent/clients/${id}/submit`)
        .set(bearer(agent))
        .expect(200);
      const client = await clientToken(w);
      // The submit sent one and the sign-in another: the third is the last allowed.
      for (let i = 0; i < 1; i += 1) {
        await http(w)
          .post('/client-invites/otp/request')
          .send({ phone: CLIENT_PHONE })
          .expect(200);
      }
      const limited = await http(w)
        .post('/client-invites/otp/request')
        .send({ phone: CLIENT_PHONE })
        .expect(429);
      expect(limited.headers['retry-after']).toBeDefined();
      await http(w)
        .post(`/client-invites/${NO_SUCH}/accept`)
        .set(bearer(client))
        .expect(404);

      w.h.clientAccount.addMember('member-9', CLIENT_PHONE);
      const member = await http(w)
        .post(`/client-invites/${id}/accept`)
        .set(bearer(client))
        .expect(409);
      expect(member.body).toMatchObject({ code: 'ALREADY_MEMBER' });
      const closed = await http(w)
        .post(`/client-invites/${id}/accept`)
        .set(bearer(client))
        .expect(409);
      expect(closed.body).toMatchObject({ code: 'INVITE_UNAVAILABLE' });
    });

    it('no response body ever carries the plain phone', async () => {
      const agent = await agentToken(w);
      const id = await addClient(w, agent);
      const bodies = [
        (await http(w).get('/agent/clients').set(bearer(agent))).text,
        (await http(w).get(`/agent/clients/${id}`).set(bearer(agent))).text,
        (await http(w).post(`/agent/clients/${id}/submit`).set(bearer(agent)))
          .text,
      ];
      for (const text of bodies) expect(text).not.toContain('9000000001');
    });
  });

  describe('server not set up', () => {
    it('without the PII key every Way 2 route is 503 AGENT_PROGRAM_UNAVAILABLE', async () => {
      w = await boot({ piiSealing: false });
      const agent = await agentToken(w);
      for (const res of [
        await http(w).get('/agent/clients').set(bearer(agent)),
        await http(w)
          .post('/client-invites/otp/request')
          .send({ phone: CLIENT_PHONE }),
      ]) {
        expect([res.status, (res.body as { code?: string }).code]).toEqual([
          503,
          'AGENT_PROGRAM_UNAVAILABLE',
        ]);
      }
    });

    it('without the token secret the client routes are 503 before any code is sent', async () => {
      w = await boot({ clientTokens: null });
      const send = jest.spyOn(w.h.otp, 'send');
      await http(w)
        .post('/client-invites/otp/request')
        .send({ phone: CLIENT_PHONE })
        .expect(503);
      await http(w).get('/client-invites').set(bearer('x')).expect(503);
      expect(send).not.toHaveBeenCalled();
    });
  });
});

describe('the full profile over HTTP', () => {
  let w: World;
  afterEach(() => w?.app.close());
  beforeEach(async () => (w = await boot()));

  it('POST without consentConfirmed true is 400 VALIDATION_FAILED naming it', async () => {
    const agent = await agentToken(w);
    for (const body of [
      { phone: CLIENT_PHONE, details: CLIENT_DETAILS },
      { phone: CLIENT_PHONE, consentConfirmed: false, details: CLIENT_DETAILS },
      { phone: CLIENT_PHONE, consentConfirmed: 'yes', details: CLIENT_DETAILS },
    ]) {
      const res = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send(body);
      expect([res.status, (res.body as { code?: string }).code]).toEqual([
        400,
        'VALIDATION_FAILED',
      ]);
    }
  });

  it('a draft may start empty; submit is 422 CLIENT_PROFILE_INCOMPLETE with missingFields until it is filled', async () => {
    const agent = await agentToken(w);
    const created = await http(w)
      .post('/agent/clients')
      .set(bearer(agent))
      .send({ phone: CLIENT_PHONE, consentConfirmed: true })
      .expect(201);
    const id = (created.body as { id: string }).id;
    expect(created.body).toMatchObject({
      details: {},
      displayName: '+91 90***001',
    });
    const refused = await http(w)
      .post(`/agent/clients/${id}/submit`)
      .set(bearer(agent))
      .expect(422);
    expect(refused.body).toEqual({
      statusCode: 422,
      error: 'Unprocessable Entity',
      code: 'CLIENT_PROFILE_INCOMPLETE',
      message: 'Fill in the required fields before submitting.',
      missingFields: [
        'basicDetails.firstName',
        'basicDetails.lastName',
        'basicDetails.gender',
        'basicDetails.dob',
        'basicDetails.maritalStatus',
        'religionDetails.religionCode',
        'locationDetails.stateCode',
        'locationDetails.cityCode',
        'educationDetails.qualification',
      ],
    });
    const edited = await http(w)
      .patch(`/agent/clients/${id}`)
      .set(bearer(agent))
      .send({ details: CLIENT_DETAILS })
      .expect(200);
    expect(
      (edited.body as { missingRequired: unknown }).missingRequired,
    ).toEqual([]);
    await http(w)
      .post(`/agent/clients/${id}/submit`)
      .set(bearer(agent))
      .expect(200);
  });

  it('a field the wizard does not have, or "who is this profile for", is 400', async () => {
    const agent = await agentToken(w);
    for (const details of [
      { basicDetails: { profileCreatedFor: 'Myself' } },
      { basicDetails: { numberOfChildren: 1 } },
      { photos: ['x'] },
    ]) {
      const res = await http(w)
        .post('/agent/clients')
        .set(bearer(agent))
        .send({ phone: CLIENT_PHONE, consentConfirmed: true, details });
      expect(res.status).toBe(400);
    }
  });
});
