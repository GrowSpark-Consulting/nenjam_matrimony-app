import { Test } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import { createHmac } from 'node:crypto';
import { AppConfigService } from '@app/config';
import { PrismaService } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { RedisService } from '@app/cache';
import { PlansController } from '../controllers/plans.controller';
import { CheckoutController } from '../controllers/checkout.controller';
import { RazorpayWebhookController } from '../controllers/razorpay-webhook.controller';
import { PlansService } from '../services/plans.service';
import { CheckoutService } from '../services/checkout.service';
import { RazorpayService } from '../services/razorpay.service';
import { RazorpayWebhookService } from '../services/razorpay-webhook.service';
import { IdentifierHashService } from '../../platform/identifier-hash.service';
import { PlatformSettingsService } from '../../platform/settings/platform-settings.service';
import { PaymentEventDispatcher } from '../events/payment-event-outbox';
import { SubscriptionLifecycleService } from '../services/subscription-lifecycle.service';
import { RazorpaySignatureGuard } from '../guards/razorpay-signature.guard';
import type {
  MyMembershipResponseDto,
  PlanCatalogResponseDto,
} from '../dto/plan.response.dto';
import { SubscriptionRepository } from '../repositories/subscription.repository';
import { PlanCatalogService } from '../../entitlements/catalog/plan-catalog.service';
import { MembershipService } from '../../entitlements/services/membership.service';
import {
  catalogRows,
  catalogService,
  membershipWithPlans,
} from '../../entitlements/tests/catalog-fixtures';

// The membership routes over real HTTP, through the real FirebaseAuthGuard,
// the same global ValidationPipe as main.ts, and `rawBody: true` as main.ts
// creates the app. Edges faked: Firebase token verification, Prisma (only
// the user lookup the guard needs), and the webhook's state changes.

const WEBHOOK_SECRET = 'webhook-secret';

describe('Membership API over HTTP', () => {
  let app: INestApplication<App>;
  const webhookHandle = jest.fn().mockResolvedValue({ status: 'PROCESSED' });
  const user = {
    id: 'user-free',
    firebaseUid: 'uid-free',
    email: 'free@test.local',
    phone: null,
    status: 'ACTIVE',
    deletedAt: null,
  };

  beforeAll(async () => {
    const membership = membershipWithPlans('shadow').service;
    const moduleRef = await Test.createTestingModule({
      controllers: [
        PlansController,
        CheckoutController,
        RazorpayWebhookController,
      ],
      providers: [
        PlansService,
        CheckoutService,
        RazorpayService,
        RazorpaySignatureGuard,
        {
          provide: RazorpayWebhookService,
          useValue: { handle: webhookHandle },
        },
        { provide: SubscriptionLifecycleService, useValue: {} },
        {
          provide: PlatformSettingsService,
          useValue: {
            getMany: () => Promise.resolve({ 'payment.gst_rate_bps': 0 }),
            registerValidator: () => undefined,
          },
        },
        { provide: IdentifierHashService, useValue: { available: false } },
        {
          provide: PaymentEventDispatcher,
          useValue: { dispatchSoon: () => undefined },
        },
        {
          provide: SubscriptionRepository,
          useValue: {
            findScheduled: () => Promise.resolve([]),
            findHeld: () => Promise.resolve([]),
          },
        },
        {
          // Priced and on sale, so purchase options are exercised.
          provide: PlanCatalogService,
          useValue: catalogService(catalogRows({ purchasable: true })),
        },
        { provide: MembershipService, useValue: membership },
        // Checkout keys absent (503); webhook secret present.
        {
          provide: AppConfigService,
          useValue: { razorpay: { webhookSecret: WEBHOOK_SECRET } },
        },
        {
          provide: PrismaService,
          useValue: { user: { findUnique: () => Promise.resolve(user) } },
        },
        {
          provide: FirebaseService,
          useValue: {
            verifyIdToken: (token: string) =>
              token === 'token-free'
                ? Promise.resolve({ uid: 'uid-free' })
                : Promise.reject(new Error('invalid token')),
          },
        },
        {
          provide: RedisService,
          useValue: { getClient: () => ({ status: 'end' }) },
        },
      ],
    }).compile();

    app = moduleRef.createNestApplication({ rawBody: true });
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        transform: true,
        forbidNonWhitelisted: true,
      }),
    );
    await app.init();
  });

  afterAll(() => app.close());

  const http = () => request(app.getHttpServer());
  const authed = (method: 'get' | 'post', path: string) =>
    http()[method](path).set('Authorization', 'Bearer token-free');

  it('requires a signed-in member for every member route', async () => {
    await http().get('/membership/me').expect(401);
    await http().get('/membership/plans').expect(401);
    await http()
      .post('/membership/checkout')
      .send({ planCode: 'GOLD', months: 3 })
      .expect(401);
  });

  it('GET /membership/me resolves a member with no subscription to Free', async () => {
    const body = (await authed('get', '/membership/me').expect(200))
      .body as MyMembershipResponseDto;
    expect(body).toMatchObject({
      plan: { code: 'FREE' },
      source: 'FREE',
      planVersion: 1,
      subscription: null,
      scheduled: [],
      checkoutAvailable: false,
      limitsEnforced: false,
    });
    expect(body.entitlements?.['search.verified_only']).toBe(true);
    // Shadow mode: the caps actually applied are the pre-membership ones —
    // 6 photos (not Free's 5), no shortlist cap.
    expect(body.effectiveCaps['profile.photos']).toBe(6);
    expect(body.effectiveCaps['shortlist.profiles']).toBeNull();
    // A Free member: every plan on sale is a NEW purchase starting now.
    expect(body.purchaseOptions).toHaveLength(4);
    expect(body.purchaseOptions.map((o) => o.kind)).toEqual([
      'NEW',
      'NEW',
      'NEW',
      'NEW',
    ]);
    expect(body.purchaseOptions[0]).toMatchObject({
      planCode: 'GOLD',
      months: 3,
      priceInPaise: 300_000,
      currency: 'INR',
    });
    expect(body.usage).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          feature: 'interests.send',
          limit: 5,
          used: 0,
        }),
      ]),
    );
  });

  it('GET /membership/plans lists all three plans with feature metadata', async () => {
    const body = (await authed('get', '/membership/plans').expect(200))
      .body as PlanCatalogResponseDto;
    expect(body.plans.map((p) => p.code)).toEqual(['FREE', 'GOLD', 'PLATINUM']);
    expect(body.checkoutAvailable).toBe(false);
    expect(body.features).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          key: 'search.verified_only',
          requiredOnEveryPlan: true,
        }),
      ]),
    );
  });

  it('checkout validates its body, then answers 503 while payments are unconfigured', async () => {
    await authed('post', '/membership/checkout')
      .send({ planCode: 'FREE', months: 3 })
      .expect(400);
    await authed('post', '/membership/checkout')
      .send({ planCode: 'GOLD', months: 3, price: 1 })
      .expect(400);
    await authed('post', '/membership/checkout')
      .send({ planCode: 'GOLD', months: 3 })
      .expect(503);
  });

  describe('POST /payments/razorpay/webhook', () => {
    const body = '{"event":"payment.captured","payload":{}}';
    const signature = createHmac('sha256', WEBHOOK_SECRET)
      .update(body)
      .digest('hex');
    const post = () =>
      http()
        .post('/payments/razorpay/webhook')
        .set('Content-Type', 'application/json');

    beforeEach(() => webhookHandle.mockClear());

    it('refuses an unsigned or wrongly signed delivery before the handler runs', async () => {
      await post().send(body).expect(401);
      await post()
        .set('X-Razorpay-Signature', 'ab'.repeat(32))
        .send(body)
        .expect(401);
      expect(webhookHandle).not.toHaveBeenCalled();
    });

    it('accepts a correctly signed delivery, checked over the raw bytes', async () => {
      await post()
        .set('X-Razorpay-Signature', signature)
        .set('X-Razorpay-Event-Id', 'evt_1')
        .send(body)
        .expect(200);
      expect(webhookHandle).toHaveBeenCalledWith(
        'evt_1',
        { event: 'payment.captured', payload: {} },
        Buffer.from(body),
      );
    });

    it('needs no Firebase token (Razorpay is the caller)', async () => {
      await post()
        .set('X-Razorpay-Signature', signature)
        .send(body)
        .expect(200);
    });
  });
});
