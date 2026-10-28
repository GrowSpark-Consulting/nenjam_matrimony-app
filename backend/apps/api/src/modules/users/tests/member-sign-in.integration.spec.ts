import {
  ConflictException,
  ExecutionContext,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { FirebaseAuthGuard } from '@app/common';
import type { PrismaClient, PrismaService } from '@app/database';
import type { FirebaseService } from '@app/firebase';
import type { RedisService } from '@app/cache';
import {
  connectIsolatedPrisma,
  describeIntegration,
} from '../../profiles/tests/integration-schema-guard';
import { DummyOtpSessionService } from '../services/dummy-otp-session.service';

/**
 * Member registration and sign-in through the REAL dummy-OTP exchange and
 * FirebaseAuthGuard, against a real Postgres — only the Firebase Admin SDK is
 * a stand-in. Pins that refusing to re-link STAFF rows (PR #129) left every
 * member path exactly as it was: new signup, repeat sign-in, and re-linking a
 * member whose Firebase account was re-created.
 */
describeIntegration(
  'member sign-in and registration (dummy OTP + auth guard)',
  () => {
    jest.setTimeout(60_000);
    let prisma: PrismaClient;
    const env = { ...process.env };
    const PREFIX = 'msi-itest';
    const firebaseUids = new Map<string, string>(); // phone -> uid
    let uidSeq = 0;

    const firebase = {
      findOrCreateUser: jest.fn(({ phone }: { phone: string }) => {
        const existing = firebaseUids.get(phone);
        if (existing) return Promise.resolve({ uid: existing, created: false });
        const uid = `${PREFIX}-uid-${++uidSeq}-${Date.now()}`;
        firebaseUids.set(phone, uid);
        return Promise.resolve({ uid, created: true });
      }),
      createCustomToken: jest.fn((uid: string) =>
        Promise.resolve(`custom-${uid}`),
      ),
      verifyIdToken: jest.fn(),
    };
    const redisDown = {
      getClient: () => ({ status: 'connecting' }),
    } as unknown as RedisService;

    const otp = () =>
      new DummyOtpSessionService(
        firebase as unknown as FirebaseService,
        prisma as unknown as PrismaService,
      );
    const guard = () =>
      new FirebaseAuthGuard(
        firebase as unknown as FirebaseService,
        prisma as unknown as PrismaService,
        redisDown,
      );

    /** What the guard decides for a request bearing a token for [decoded]. */
    async function authenticate(decoded: {
      uid: string;
      email?: string;
      email_verified?: boolean;
      phone_number?: string;
    }) {
      firebase.verifyIdToken.mockResolvedValue(decoded);
      const request: {
        headers: Record<string, string>;
        user?: { id: string };
      } = {
        headers: { authorization: 'Bearer a.b.c' },
      };
      const ctx = {
        switchToHttp: () => ({ getRequest: () => request }),
      } as unknown as ExecutionContext;
      await guard().canActivate(ctx);
      return request.user!;
    }

    const phone = (n: number) => `+9190000${String(n).padStart(5, '0')}`;
    const email = (name: string) => `${name}@${PREFIX}.local`;

    async function cleanup() {
      await prisma.user.deleteMany({
        where: {
          OR: [
            { email: { endsWith: `@${PREFIX}.local` } },
            { firebaseUid: { startsWith: PREFIX } },
          ],
        },
      });
    }

    beforeAll(async () => {
      jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
      jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
      process.env.NODE_ENV = 'development';
      process.env.DEV_AUTH_ENABLED = 'true';
      delete process.env.USE_REAL_OTP;
      delete process.env.DUMMY_OTP_PHONES;
      prisma = await connectIsolatedPrisma();
      await cleanup();
    });

    afterAll(async () => {
      process.env = env;
      if (prisma) await cleanup();
      await prisma?.$disconnect();
    });

    it('registers a new member and signs them in on the next request', async () => {
      const session = await otp().start({
        phone: phone(1),
        email: email('new'),
      });
      expect(session.customToken).toBe(`custom-${session.uid}`);
      const row = await prisma.user.findUniqueOrThrow({
        where: { id: session.userId },
      });
      expect(row).toMatchObject({
        firebaseUid: session.uid,
        phone: phone(1),
        email: email('new'),
        role: 'USER',
      });

      const user = await authenticate({
        uid: session.uid,
        phone_number: phone(1),
      });
      expect(user.id).toBe(session.userId);
    });

    it('signs a returning member into the same account, however often', async () => {
      const first = await otp().start({ phone: phone(2) });
      const again = await otp().start({ phone: phone(2) });
      expect(again.userId).toBe(first.userId);
      expect(await prisma.user.count({ where: { phone: phone(2) } })).toBe(1);
    });

    it('still re-links a member whose Firebase account was re-created (by email, in the guard)', async () => {
      const member = await prisma.user.create({
        data: {
          firebaseUid: `${PREFIX}-old-uid-email`,
          email: email('relinked'),
          status: 'ACTIVE',
        },
      });
      const user = await authenticate({
        uid: `${PREFIX}-new-uid-email`,
        email: email('relinked'),
        email_verified: true,
      });
      expect(user.id).toBe(member.id);
      expect(
        (await prisma.user.findUniqueOrThrow({ where: { id: member.id } }))
          .firebaseUid,
      ).toBe(`${PREFIX}-new-uid-email`);
    });

    it('still re-links a member by phone in the dummy-OTP exchange', async () => {
      const member = await prisma.user.create({
        data: {
          firebaseUid: `${PREFIX}-old-uid-phone`,
          email: email('byphone'),
          phone: phone(3),
          status: 'ACTIVE',
        },
      });
      const session = await otp().start({ phone: phone(3) });
      expect(session.userId).toBe(member.id);
    });

    it('refuses to hand a member to someone who only claims their email', async () => {
      const victim = await prisma.user.create({
        data: {
          firebaseUid: `${PREFIX}-victim-uid`,
          email: email('victim'),
          phone: phone(6),
          status: 'ACTIVE',
        },
      });
      // Dummy-OTP signup with a new number and the victim's email.
      await expect(
        otp().start({ phone: phone(7), email: email('victim') }),
      ).rejects.toBeInstanceOf(ConflictException);
      // A fresh Firebase email/password account for the victim's address.
      await expect(
        authenticate({
          uid: `${PREFIX}-attacker-uid-2`,
          email: email('victim'),
          email_verified: false,
        }),
      ).rejects.toBeInstanceOf(ConflictException);

      const after = await prisma.user.findUniqueOrThrow({
        where: { id: victim.id },
      });
      expect(after).toMatchObject({
        firebaseUid: `${PREFIX}-victim-uid`,
        phone: phone(6),
        email: email('victim'),
      });
      expect(await prisma.user.count({ where: { phone: phone(7) } })).toBe(0);
    });

    it('refuses both paths for a staff row, leaving it untouched', async () => {
      const admin = await prisma.user.create({
        data: {
          firebaseUid: `${PREFIX}-admin-uid`,
          email: email('admin'),
          phone: phone(4),
          role: 'ADMIN',
          status: 'ACTIVE',
        },
      });
      await expect(otp().start({ phone: phone(4) })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      await expect(
        otp().start({ phone: phone(5), email: email('admin') }),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(
        authenticate({ uid: `${PREFIX}-attacker-uid`, email: email('admin') }),
      ).rejects.toBeInstanceOf(ForbiddenException);

      const after = await prisma.user.findUniqueOrThrow({
        where: { id: admin.id },
      });
      expect(after.firebaseUid).toBe(`${PREFIX}-admin-uid`);
      expect(after.phone).toBe(phone(4));
    });
  },
);
