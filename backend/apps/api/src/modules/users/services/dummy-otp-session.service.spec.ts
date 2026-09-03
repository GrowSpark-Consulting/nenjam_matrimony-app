import {
  ForbiddenException,
  InternalServerErrorException,
} from '@nestjs/common';
import { DummyOtpSessionService } from './dummy-otp-session.service';

/**
 * The exchange that makes a dummy OTP produce a REAL account.
 *
 * Two things are worth pinning here. The first is that it is bounded exactly
 * like the header it replaces — minting a session for a number nobody sent an
 * SMS to must not be reachable anywhere `dev-auth.ts` would refuse. The second
 * is that it never leaves a member half-provisioned: one Firebase account and
 * one `users` row per person however many times they retry, and no token
 * handed out for an identity the database does not carry.
 */
describe('DummyOtpSessionService', () => {
  const PHONE = '+919876543210';
  const EMAIL = 'member@example.com';
  const original = { ...process.env };

  afterEach(() => {
    process.env = { ...original };
    jest.clearAllMocks();
  });

  const enableDevMode = () => {
    process.env.NODE_ENV = 'development';
    process.env.DEV_AUTH_ENABLED = 'true';
    delete process.env.USE_REAL_OTP;
    delete process.env.DUMMY_OTP_ENABLED;
  };

  const firebase = {
    findOrCreateUser: jest.fn(),
    createCustomToken: jest.fn(),
  };

  /// Typed so the `where` a mock implementation destructures is not `any` —
  /// the assertions below read fields off it.
  type UserWhere = { firebaseUid?: string; email?: string; phone?: string };
  type FoundUser = { id: string } | null;

  const prisma = {
    user: {
      findUnique: jest.fn<Promise<FoundUser>, [{ where: UserWhere }]>(),
      create: jest.fn<
        Promise<FoundUser>,
        [{ data: Record<string, unknown> }]
      >(),
      update: jest.fn<
        Promise<FoundUser>,
        [{ where: { id: string }; data: Record<string, unknown> }]
      >(),
    },
  };

  const build = () =>
    new DummyOtpSessionService(firebase as never, prisma as unknown as never);

  beforeEach(() => {
    firebase.findOrCreateUser.mockResolvedValue({
      uid: 'firebase-uid-1',
      created: true,
    });
    firebase.createCustomToken.mockResolvedValue('a-custom-token');
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({ id: 'user-1' });
    prisma.user.update.mockResolvedValue({ id: 'user-1' });
  });

  describe('where it does not apply', () => {
    it('refuses when every dummy-OTP flag is off', async () => {
      process.env.NODE_ENV = 'production';
      delete process.env.DEV_AUTH_ENABLED;
      delete process.env.DUMMY_OTP_ENABLED;

      await expect(build().start({ phone: PHONE })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      // Refused before it touched Firebase — the bypass is not merely
      // unreported, it does not happen.
      expect(firebase.findOrCreateUser).not.toHaveBeenCalled();
    });

    it('refuses a number outside the production whitelist', async () => {
      process.env.NODE_ENV = 'production';
      process.env.DUMMY_OTP_ENABLED = 'true';
      process.env.DUMMY_OTP_PHONES = '+919000000000';

      await expect(build().start({ phone: PHONE })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(firebase.findOrCreateUser).not.toHaveBeenCalled();
    });

    it('refuses once USE_REAL_OTP is set, whatever else is', async () => {
      process.env.NODE_ENV = 'development';
      process.env.DEV_AUTH_ENABLED = 'true';
      process.env.DUMMY_OTP_ENABLED = 'true';
      process.env.DUMMY_OTP_PHONES = PHONE;
      process.env.USE_REAL_OTP = 'true';

      await expect(build().start({ phone: PHONE })).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    });
  });

  describe('a new member', () => {
    it('provisions a Firebase account, a users row, and a token', async () => {
      enableDevMode();

      const result = await build().start({ phone: PHONE, email: EMAIL });

      expect(firebase.findOrCreateUser).toHaveBeenCalledWith({
        phone: PHONE,
        email: EMAIL,
      });
      // The address reaches Firebase only as something to look an existing
      // account up by — never written onto one. An unverified address on the
      // account is what routes a member to a verify-email screen they cannot
      // pass; see FirebaseService.findOrCreateUser.
      expect(firebase.createCustomToken).toHaveBeenCalledWith('firebase-uid-1');
      expect(prisma.user.create.mock.calls[0][0].data).toMatchObject({
        firebaseUid: 'firebase-uid-1',
        phone: PHONE,
        email: EMAIL,
      });
      expect(result).toEqual({
        customToken: 'a-custom-token',
        uid: 'firebase-uid-1',
        userId: 'user-1',
      });
    });

    it(
      'gives a phone-only signup the same placeholder address the guard ' +
        'uses',
      async () => {
        enableDevMode();

        await build().start({ phone: PHONE });

        // `User.email` is required and unique; inventing a second convention
        // for that gap is how the guard and this endpoint would start
        // disagreeing about who a phone-only member is.
        expect(prisma.user.create.mock.calls[0][0].data).toMatchObject({
          email: 'firebase-uid-1@firebase.invalid',
        });
      },
    );
  });

  describe('retries and reconciliation', () => {
    it('reuses the existing row when the same number signs up again', async () => {
      enableDevMode();
      firebase.findOrCreateUser.mockResolvedValue({
        uid: 'firebase-uid-1',
        created: false,
      });
      prisma.user.findUnique.mockImplementation(({ where }) =>
        Promise.resolve(where.firebaseUid ? { id: 'user-1' } : null),
      );

      const result = await build().start({ phone: PHONE });

      expect(prisma.user.create).not.toHaveBeenCalled();
      expect(result.userId).toBe('user-1');
    });

    it('re-links an account that already exists under another uid', async () => {
      enableDevMode();
      // The Firebase account was re-created (routine in QA), so the uid moved
      // while the address stayed. Everything this member owns hangs off the
      // internal id, so it must be re-linked rather than duplicated.
      prisma.user.findUnique.mockImplementation(({ where }) =>
        Promise.resolve(where.email === EMAIL ? { id: 'existing-user' } : null),
      );

      const result = await build().start({ phone: PHONE, email: EMAIL });

      expect(prisma.user.create).not.toHaveBeenCalled();
      const [updateArg] = prisma.user.update.mock.calls[0];
      expect(updateArg.where).toEqual({ id: 'existing-user' });
      expect(updateArg.data).toMatchObject({ firebaseUid: 'firebase-uid-1' });
      expect(result.userId).toBe('existing-user');
    });
  });

  describe('when provisioning goes wrong', () => {
    it('fails loudly if the users row cannot be written, and mints no token', async () => {
      enableDevMode();
      prisma.user.create.mockRejectedValue(new Error('db down'));

      await expect(build().start({ phone: PHONE })).rejects.toBeInstanceOf(
        InternalServerErrorException,
      );

      // A token for an identity the database does not carry is exactly the
      // half-signed-up state this endpoint exists to prevent.
      expect(firebase.createCustomToken).not.toHaveBeenCalled();
    });
  });
});
