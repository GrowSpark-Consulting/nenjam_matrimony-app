import { Test } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import { PrismaService } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { RedisService } from '@app/cache';
import { SettingsController } from '../controllers/settings.controller';
import { SettingsService } from '../services/settings.service';
import { SettingsRepository } from '../repositories/settings.repository';
import { AccountDeletionService } from '../services/account-deletion.service';
import { EntitlementService } from '../../entitlements/services/entitlement.service';
import type { PrivacySettingsResponse } from '../dto/privacy-settings.response.dto';

// `GET /settings` + `PATCH /settings/privacy` over real HTTP, through the real
// FirebaseAuthGuard, controller, service and repository and the same global
// ValidationPipe main.ts installs. Only the edges are faked: Firebase token
// verification, premium entitlement, and Prisma — an in-memory `user` table,
// so this runs in `pnpm test` without touching a database. The persisted value
// is read back from that table, not from the response, to prove the write.

interface UserRow {
  id: string;
  firebaseUid: string;
  email: string;
  phone: string | null;
  status: string;
  deletedAt: Date | null;
  profileVisibleToPremiumOnly: boolean;
  hidePhotosFromNonConnections: boolean;
}

const ALICE = 'user-alice'; // premium
const BOB = 'user-bob'; // not premium

function row(id: string, uid: string): UserRow {
  return {
    id,
    firebaseUid: uid,
    email: `${uid}@test.local`,
    phone: null,
    status: 'ACTIVE',
    deletedAt: null,
    profileVisibleToPremiumOnly: false,
    hidePhotosFromNonConnections: false,
  };
}

function pick(user: UserRow, select?: Record<string, boolean>) {
  if (!select) return { ...user };
  return Object.fromEntries(
    Object.keys(select).map((k) => [k, user[k as keyof UserRow]]),
  );
}

describe('Settings privacy over HTTP', () => {
  let app: INestApplication<App>;
  let users: Map<string, UserRow>;
  const premium = new Set<string>([ALICE]);

  const prisma = {
    user: {
      findUnique: jest.fn(
        ({
          where,
          select,
        }: {
          where: Partial<UserRow>;
          select?: Record<string, boolean>;
        }) => {
          const [key, value] = Object.entries(where)[0];
          const found = [...users.values()].find(
            (u) => u[key as keyof UserRow] === value,
          );
          return Promise.resolve(found ? pick(found, select) : null);
        },
      ),
      update: jest.fn(
        ({
          where,
          data,
          select,
        }: {
          where: { id: string };
          data: Partial<UserRow>;
          select?: Record<string, boolean>;
        }) => {
          const found = users.get(where.id);
          if (!found)
            return Promise.reject(
              Object.assign(new Error(), { code: 'P2025' }),
            );
          Object.assign(found, data);
          return Promise.resolve(pick(found, select));
        },
      ),
    },
  };

  const verifyIdToken = jest.fn((token: string) => {
    if (token === 'token-alice') return Promise.resolve({ uid: 'uid-alice' });
    if (token === 'token-bob') return Promise.resolve({ uid: 'uid-bob' });
    return Promise.reject(new Error('invalid token'));
  });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [SettingsController],
      providers: [
        SettingsService,
        SettingsRepository,
        { provide: AccountDeletionService, useValue: {} },
        {
          provide: EntitlementService,
          useValue: {
            hasActivePremiumSubscription: (userId: string) =>
              Promise.resolve(premium.has(userId)),
          },
        },
        { provide: PrismaService, useValue: prisma },
        { provide: FirebaseService, useValue: { verifyIdToken } },
        // Redis "not ready": the guard's auth cache falls through to Prisma.
        {
          provide: RedisService,
          useValue: { getClient: () => ({ status: 'end' }) },
        },
      ],
    }).compile();

    app = moduleRef.createNestApplication();
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

  beforeEach(() => {
    users = new Map([
      [ALICE, row(ALICE, 'uid-alice')],
      [BOB, row(BOB, 'uid-bob')],
    ]);
    prisma.user.update.mockClear();
  });

  const http = () => request(app.getHttpServer());
  const get = (token: string) =>
    http().get('/settings').set('Authorization', `Bearer ${token}`);
  const patch = (token: string, body: object) =>
    http()
      .patch('/settings/privacy')
      .set('Authorization', `Bearer ${token}`)
      .send(body);

  describe('authentication', () => {
    it('rejects GET without an Authorization header', async () => {
      await http().get('/settings').expect(401);
    });

    it('rejects PATCH without an Authorization header, writing nothing', async () => {
      await http()
        .patch('/settings/privacy')
        .send({ hideMyProfile: true })
        .expect(401);
      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('rejects an invalid bearer token', async () => {
      await http()
        .get('/settings')
        .set('Authorization', 'Bearer forged')
        .expect(401);
    });
  });

  it('reads the caller’s current setting', async () => {
    users.get(ALICE)!.profileVisibleToPremiumOnly = true;
    const res = await get('token-alice').expect(200);
    expect(res.body).toEqual<PrivacySettingsResponse>({
      isPremium: true,
      hideMyProfile: true,
      hidePhotosFromNonConnections: false,
      profileVisibleToPremiumOnly: true,
    });
  });

  it('premium: OFF → ON → OFF persists each value and reads it back', async () => {
    const on = await patch('token-alice', { hideMyProfile: true }).expect(200);
    expect((on.body as PrivacySettingsResponse).hideMyProfile).toBe(true);
    expect(users.get(ALICE)!.profileVisibleToPremiumOnly).toBe(true);
    const readOn = await get('token-alice').expect(200);
    expect((readOn.body as PrivacySettingsResponse).hideMyProfile).toBe(true);

    const off = await patch('token-alice', { hideMyProfile: false }).expect(
      200,
    );
    expect((off.body as PrivacySettingsResponse).hideMyProfile).toBe(false);
    expect(users.get(ALICE)!.profileVisibleToPremiumOnly).toBe(false);
    const readOff = await get('token-alice').expect(200);
    expect((readOff.body as PrivacySettingsResponse).hideMyProfile).toBe(false);
  });

  it('only ever writes the caller’s own row', async () => {
    await patch('token-alice', { hideMyProfile: true }).expect(200);
    expect(users.get(ALICE)!.profileVisibleToPremiumOnly).toBe(true);
    expect(users.get(BOB)!.profileVisibleToPremiumOnly).toBe(false);
  });

  it('refuses a userId in the body (400), so nobody can target another member', async () => {
    await patch('token-alice', { hideMyProfile: true, userId: BOB }).expect(
      400,
    );
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(users.get(BOB)!.profileVisibleToPremiumOnly).toBe(false);
  });

  it('refuses a client-asserted isPremium (400)', async () => {
    await patch('token-bob', { hideMyProfile: true, isPremium: true }).expect(
      400,
    );
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('refuses a non-boolean value (400)', async () => {
    await patch('token-alice', { hideMyProfile: 'yes' }).expect(400);
  });

  describe('non-premium member (privacy controls temporarily free)', () => {
    it('Hide My Profile: read → ON → read → OFF → read, isPremium stays false', async () => {
      const initial = await get('token-bob').expect(200);
      expect(initial.body).toMatchObject({
        isPremium: false,
        hideMyProfile: false,
      });

      const on = await patch('token-bob', { hideMyProfile: true }).expect(200);
      expect(on.body).toEqual<PrivacySettingsResponse>({
        isPremium: false,
        hideMyProfile: true,
        hidePhotosFromNonConnections: false,
        profileVisibleToPremiumOnly: true,
      });
      expect(users.get(BOB)!.profileVisibleToPremiumOnly).toBe(true);
      const readOn = await get('token-bob').expect(200);
      expect(readOn.body).toMatchObject({
        isPremium: false,
        hideMyProfile: true,
      });

      const off = await patch('token-bob', { hideMyProfile: false }).expect(
        200,
      );
      expect((off.body as PrivacySettingsResponse).hideMyProfile).toBe(false);
      expect(users.get(BOB)!.profileVisibleToPremiumOnly).toBe(false);
      const readOff = await get('token-bob').expect(200);
      expect(readOff.body).toMatchObject({
        isPremium: false,
        hideMyProfile: false,
      });
    });

    it('photo privacy: read → ON → read → OFF → read, isPremium stays false', async () => {
      const on = await patch('token-bob', {
        hidePhotosFromNonConnections: true,
      }).expect(200);
      expect(on.body).toEqual<PrivacySettingsResponse>({
        isPremium: false,
        hideMyProfile: false,
        hidePhotosFromNonConnections: true,
        profileVisibleToPremiumOnly: false,
      });
      expect(users.get(BOB)!.hidePhotosFromNonConnections).toBe(true);
      const readOn = await get('token-bob').expect(200);
      expect(readOn.body).toMatchObject({
        isPremium: false,
        hidePhotosFromNonConnections: true,
      });

      const off = await patch('token-bob', {
        hidePhotosFromNonConnections: false,
      }).expect(200);
      expect(
        (off.body as PrivacySettingsResponse).hidePhotosFromNonConnections,
      ).toBe(false);
      expect(users.get(BOB)!.hidePhotosFromNonConnections).toBe(false);
      const readOff = await get('token-bob').expect(200);
      expect(readOff.body).toMatchObject({
        isPremium: false,
        hidePhotosFromNonConnections: false,
      });
    });

    it('both at once: persisted together, isPremium stays false', async () => {
      await patch('token-bob', {
        hideMyProfile: true,
        hidePhotosFromNonConnections: true,
      }).expect(200);
      expect(users.get(BOB)).toMatchObject({
        profileVisibleToPremiumOnly: true,
        hidePhotosFromNonConnections: true,
      });

      const read = await get('token-bob').expect(200);
      expect(read.body).toEqual<PrivacySettingsResponse>({
        isPremium: false,
        hideMyProfile: true,
        hidePhotosFromNonConnections: true,
        profileVisibleToPremiumOnly: true,
      });
      // Only Bob's row changed.
      expect(users.get(ALICE)).toMatchObject({
        profileVisibleToPremiumOnly: false,
        hidePhotosFromNonConnections: false,
      });
    });
  });
});
