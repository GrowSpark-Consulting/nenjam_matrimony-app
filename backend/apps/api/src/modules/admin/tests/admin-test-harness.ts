import { DynamicModule, INestApplication, Type } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes } from 'node:crypto';
import request from 'supertest';
import type { App } from 'supertest/types';
import { ApiValidationPipe } from '@app/common';
import { AppConfigService } from '@app/config';
import { PrismaService, type PrismaClient } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { RedisService } from '@app/cache';
import { base32Decode, hotp, totpStep } from '../auth/totp';
import { grantAdminRole } from '../provisioning/admin-provisioning';

/**
 * Shared setup for HTTP-level admin integration specs: a Nest app on the
 * isolated test schema where only Firebase token verification is a stand-in
 * (the bearer token is the person's key in [people]).
 */
export interface TestPerson {
  uid: string;
  email: string;
}

export async function createAdminTestApp(
  prisma: PrismaClient,
  people: Record<string, TestPerson>,
  modules: Array<Type<unknown>>,
): Promise<INestApplication<App>> {
  const verifyIdToken = (token: string) => {
    const person = people[token];
    return person
      ? Promise.resolve({ uid: person.uid, email: person.email })
      : Promise.reject(new Error('invalid token'));
  };
  const infra: DynamicModule = {
    module: class TestInfraModule {},
    global: true,
    providers: [
      { provide: PrismaService, useValue: prisma },
      { provide: FirebaseService, useValue: { verifyIdToken } },
      // "Not ready": the auth guard's cache fails open to the database.
      {
        provide: RedisService,
        useValue: { getClient: () => ({ status: 'connecting' }) },
      },
    ],
    exports: [PrismaService, FirebaseService, RedisService],
  };
  const moduleRef = await Test.createTestingModule({
    imports: [infra, ...modules],
  })
    .overrideProvider(AppConfigService)
    .useValue({
      admin: { mfaEncryptionKey: randomBytes(32).toString('base64') },
      membership: { enforcementMode: 'shadow' },
      razorpay: {},
      identifierHash: {},
      agentOtp: { dummyEnabled: false, dummyPhones: [] },
    })
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
  return app;
}

/** The current authenticator code; clears the replay marker first so a spec
 *  can use several codes inside one 30-second step. */
export async function freshCode(
  prisma: PrismaClient,
  email: string,
  secret: string,
): Promise<string> {
  await prisma.adminAccount.updateMany({
    where: { user: { email } },
    data: { mfaLastUsedStep: null },
  });
  return hotp(base32Decode(secret), totpStep(Date.now()));
}

/** Provision → enrol over HTTP → an admin session token. */
export async function provisionAndEnrol(
  app: INestApplication<App>,
  prisma: PrismaClient,
  token: string,
  person: TestPerson,
  roleKey: string,
): Promise<{ session: string; secret: string }> {
  const { enrollmentCode } = await grantAdminRole(prisma, {
    firebaseUid: person.uid,
    email: person.email,
    roleKey,
    reason: 'integration test',
  });
  const auth = { Authorization: `Bearer ${token}` };
  const started = await request(app.getHttpServer())
    .post('/admin/auth/mfa/enrollment')
    .set(auth)
    .send({ enrollmentCode })
    .expect(201);
  const secret = (started.body as { secret: string }).secret;
  const confirmed = await request(app.getHttpServer())
    .post('/admin/auth/mfa/enrollment/confirm')
    .set(auth)
    .send({
      enrollmentCode,
      code: await freshCode(prisma, person.email, secret),
    })
    .expect(201);
  return {
    session: (confirmed.body as { sessionToken: string }).sessionToken,
    secret,
  };
}
