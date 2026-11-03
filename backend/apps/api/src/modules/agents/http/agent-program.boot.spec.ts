import { type INestApplication, Module } from '@nestjs/common';
import { ConditionalModule, ConfigModule } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import type { App } from 'supertest/types';
import { FirebaseAuthGuard } from '@app/common';
import { AppConfigModule } from '@app/config';
import { AdminModule } from '../../admin/admin.module';
import { PlatformModule } from '../../platform/platform.module';
import { AGENT_REFERRAL_QUOTE } from '../agent-referral-quote.token';
import { AgentJwtTokenSigner } from '../auth/agent-jwt-token-signer';
import { AgentConfigService } from '../config/agent-config.service';
import {
  AUTH_OPTIONS,
  CLIENT_TOKEN_OPTIONS,
  makeAgentHarness,
} from '../testing/agent-test-harness';
import { AGENT_PROGRAM, type AgentProgram } from './agent-program';
import {
  AgentProgramModule,
  agentProgramEnabled,
} from './agent-program.module';

@Module({})
class Empty {}

function program(): AgentProgram {
  let jwt!: AgentJwtTokenSigner;
  let clientJwt!: AgentJwtTokenSigner;
  const h = makeAgentHarness(
    {},
    {
      signerFor: (clock) =>
        (jwt = new AgentJwtTokenSigner(
          {
            secret: 'test-only-agent-jwt-secret-not-real-0000',
            issuer: AUTH_OPTIONS.issuer,
            audience: AUTH_OPTIONS.audience,
          },
          clock,
        )),
      clientSignerFor: (clock) =>
        (clientJwt = new AgentJwtTokenSigner(
          {
            secret: 'test-only-agent-jwt-secret-not-real-0000',
            ...CLIENT_TOKEN_OPTIONS,
            scopes: ['CLIENT'],
          },
          clock,
        )),
    },
  );
  return {
    signIn: h.signIn,
    application: h.application,
    me: h.me,
    config: new AgentConfigService(h.settings, h.content, {
      getActiveHoldDays: () => Promise.resolve(14),
    }),
    referrals: h.referrals,
    referralCodes: h.referralCodes,
    money: h.money,
    clients: h.clients,
    clientInvites: h.clientInvites,
    tokens: jwt,
    clientTokens: clientJwt,
    piiSealing: true,
    requesterKey: () => 'v1:hashed-test-ip',
  };
}

/** Boots the agents' conditional registration exactly as AgentsModule does. */
async function bootWith(flag: string | undefined) {
  if (flag === undefined) delete process.env.AGENT_PROGRAM_ENABLED;
  else process.env.AGENT_PROGRAM_ENABLED = flag;
  const moduleRef = await Test.createTestingModule({
    imports: [
      ConfigModule.forRoot({ ignoreEnvFile: true }),
      ConditionalModule.registerWhen(AgentProgramModule, agentProgramEnabled),
    ],
  })
    .overrideModule(AdminModule)
    .useModule(Empty)
    .overrideModule(PlatformModule)
    .useModule(Empty)
    .overrideModule(AppConfigModule)
    .useModule(Empty)
    .overrideProvider(AGENT_PROGRAM)
    .useValue(program())
    .overrideGuard(FirebaseAuthGuard)
    .useValue({ canActivate: () => false })
    .compile();
  const app = moduleRef.createNestApplication<INestApplication<App>>();
  await app.init();
  return { app, moduleRef };
}

const DRAFT = '/agent/clients/11111111-1111-4111-8111-000000000009';
const INVITE = '/client-invites/11111111-1111-4111-8111-000000000009';

const ROUTES: Array<
  [method: 'get' | 'post' | 'patch' | 'delete', path: string]
> = [
  ['post', '/agent/auth/otp/request'],
  ['post', '/agent/auth/otp/verify'],
  ['post', '/agent/auth/refresh'],
  ['post', '/agent/auth/logout'],
  ['post', '/agent/application'],
  ['get', '/agent/me'],
  ['patch', '/agent/me/payout-details'],
  ['get', '/agent/config'],
  ['get', '/agent/referral-links'],
  ['get', '/agent/referrals'],
  ['get', '/agent/referrals/11111111-1111-4111-8111-000000000001'],
  ['post', '/referrals/codes/validate'],
  ['post', '/registration/referral-code'],
  // Agent-added clients (Way 2).
  ['post', '/agent/clients'],
  ['get', '/agent/clients'],
  ['get', DRAFT],
  ['patch', DRAFT],
  ['delete', DRAFT],
  ['post', `${DRAFT}/submit`],
  ['post', '/client-invites/otp/request'],
  ['post', '/client-invites/otp/verify'],
  ['get', '/client-invites'],
  ['post', `${INVITE}/accept`],
  ['post', `${INVITE}/reject`],
];

describe('AGENT_PROGRAM_ENABLED', () => {
  const saved = process.env.AGENT_PROGRAM_ENABLED;
  afterAll(() => {
    if (saved === undefined) delete process.env.AGENT_PROGRAM_ENABLED;
    else process.env.AGENT_PROGRAM_ENABLED = saved;
  });

  it.each([undefined, '', 'false', '1', 'yes'])(
    'with %p every agent route is 404',
    async (flag) => {
      const { app, moduleRef } = await bootWith(flag);
      try {
        for (const [method, path] of ROUTES) {
          const res = await request(app.getHttpServer())[method](path).send({});
          expect([path, res.status]).toEqual([path, 404]);
        }
        expect(() =>
          moduleRef.get<unknown>(AGENT_REFERRAL_QUOTE, { strict: false }),
        ).toThrow();
      } finally {
        await app.close();
      }
    },
  );

  it.each(['true', 'TRUE', ' true '])(
    'with %p every route exists, and the routes module provides no quote (the quote module does)',
    async (flag) => {
      const { app, moduleRef } = await bootWith(flag);
      try {
        for (const [method, path] of ROUTES) {
          const res = await request(app.getHttpServer())[method](path).send({});
          expect([path, res.status === 404]).toEqual([path, false]);
        }
        expect(() =>
          moduleRef.get<unknown>(AGENT_REFERRAL_QUOTE, { strict: false }),
        ).toThrow();
      } finally {
        await app.close();
      }
    },
  );

  it('agentProgramEnabled is on only for "true"', () => {
    expect(agentProgramEnabled({ AGENT_PROGRAM_ENABLED: 'true' })).toBe(true);
    for (const v of [undefined, '', 'false', '1', 'on', 'truee']) {
      expect(agentProgramEnabled({ AGENT_PROGRAM_ENABLED: v })).toBe(false);
    }
  });
});
