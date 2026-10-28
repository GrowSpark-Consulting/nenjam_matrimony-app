import {
  ExecutionContext,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { FirebaseAuthGuard } from './firebase-auth.guard';
import type { FirebaseService } from '@app/firebase';
import type { PrismaService } from '@app/database';
import type { RedisService } from '@app/cache';

const UID = 'firebase-uid-1';
const TOKEN = 'a.valid.looking.jwt';

interface RequestWithUser {
  headers: Record<string, string | undefined>;
  user?: { id: string; uid: string };
}

function contextFor(authorization?: string): {
  ctx: ExecutionContext;
  request: RequestWithUser;
} {
  const request: RequestWithUser = { headers: { authorization } };
  const ctx = {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { ctx, request };
}

/** Redis reporting "not ready" — the fail-open path the guard already
 *  tolerates, which keeps these tests on the authoritative DB branch. */
function redisDown(): RedisService {
  return {
    getClient: () => ({ status: 'connecting' }),
  } as unknown as RedisService;
}

/** Redis serving one cached account, so the guard takes its fast path. */
function redisServing(value: unknown): RedisService {
  return {
    getClient: () => ({
      status: 'ready',
      get: () => Promise.resolve(JSON.stringify(value)),
      set: () => Promise.resolve('OK'),
    }),
  } as unknown as RedisService;
}

function buildGuard(opts: {
  verifyIdToken: jest.Mock;
  findUnique?: jest.Mock;
  upsert?: jest.Mock;
  update?: jest.Mock;
  redis?: RedisService;
}) {
  const findUnique = opts.findUnique ?? jest.fn(() => Promise.resolve(null));
  const upsert =
    opts.upsert ?? jest.fn(() => Promise.resolve({ id: 'internal-1' }));
  const update = opts.update ?? jest.fn();

  const prisma = {
    user: { findUnique, upsert, update },
  } as unknown as PrismaService;

  const firebase = {
    verifyIdToken: opts.verifyIdToken,
  } as unknown as FirebaseService;

  return {
    guard: new FirebaseAuthGuard(firebase, prisma, opts.redis ?? redisDown()),
    findUnique,
    upsert,
  };
}

describe('FirebaseAuthGuard', () => {
  describe('bearer token handling', () => {
    it.each([
      ['no header at all', undefined],
      ['a non-bearer scheme', 'Basic dXNlcjpwYXNz'],
      ['an empty bearer', 'Bearer    '],
    ])('rejects %s', async (_label, header) => {
      const { guard } = buildGuard({ verifyIdToken: jest.fn() });
      const { ctx } = contextFor(header as string | undefined);

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });

    it('rejects a token Firebase will not verify', async () => {
      const { guard } = buildGuard({
        verifyIdToken: jest.fn(() => Promise.reject(new Error('expired'))),
      });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });

    it('never trusts an id the client supplied', async () => {
      // The internal id must come from the DB row the verified uid resolves
      // to, never from the request — this is the whole basis of ownership.
      const { guard } = buildGuard({
        verifyIdToken: jest.fn(() => Promise.resolve({ uid: UID })),
        findUnique: jest.fn(() => Promise.resolve({ id: 'internal-1' })),
      });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);
      request.user = { id: 'attacker-supplied', uid: 'attacker-uid' };

      await guard.canActivate(ctx);

      expect(request.user).toMatchObject({ id: 'internal-1', uid: UID });
    });
  });

  describe('creating an account for an unknown uid', () => {
    it('re-verifies with revocation checking before creating a row', async () => {
      // Signature verification alone cannot tell a first-ever sign-in from a
      // token belonging to an account that was just deleted — an ID token
      // stays valid for up to an hour after deletion.
      const verifyIdToken = jest.fn(() => Promise.resolve({ uid: UID }));
      const { guard, upsert } = buildGuard({ verifyIdToken });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await guard.canActivate(ctx);

      expect(verifyIdToken).toHaveBeenCalledTimes(2);
      expect(verifyIdToken).toHaveBeenNthCalledWith(1, TOKEN, false);
      expect(verifyIdToken).toHaveBeenNthCalledWith(2, TOKEN, true);
      expect(upsert).toHaveBeenCalled();
    });

    it('does not resurrect a deleted account', async () => {
      // Second call is the revocation check: Firebase says the account is
      // gone. Nothing may be written — otherwise the row the member asked to
      // have erased comes back as a fresh, profile-less account.
      const verifyIdToken = jest
        .fn()
        .mockResolvedValueOnce({ uid: UID })
        .mockRejectedValueOnce(new Error('auth/user-not-found'));
      const { guard, upsert } = buildGuard({ verifyIdToken });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(upsert).not.toHaveBeenCalled();
    });
  });

  describe('existing accounts', () => {
    it('skips the revocation check when the uid already has a row', async () => {
      // The extra Admin SDK round trip is confined to genuinely new accounts;
      // finding a row is itself proof the account is real, and this is the hot
      // path of every authenticated request.
      const verifyIdToken = jest.fn(() => Promise.resolve({ uid: UID }));
      const { guard } = buildGuard({
        verifyIdToken,
        findUnique: jest.fn(() => Promise.resolve({ id: 'internal-1' })),
      });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);

      await guard.canActivate(ctx);

      expect(verifyIdToken).toHaveBeenCalledTimes(1);
      expect(verifyIdToken).toHaveBeenCalledWith(TOKEN, false);
      expect(request.user?.id).toBe('internal-1');
    });

    it('re-links a rotated uid instead of creating a duplicate', async () => {
      // Firebase UIDs are not permanently stable; email is the durable
      // identity. Creating a second row would crash on the unique constraint.
      const findUnique = jest
        .fn()
        .mockResolvedValueOnce(null) // by firebaseUid
        .mockResolvedValueOnce({ id: 'internal-1', firebaseUid: 'old-uid' }); // by email
      const update = jest.fn(() => Promise.resolve({ id: 'internal-1' }));
      const verifyIdToken = jest.fn(() =>
        Promise.resolve({ uid: UID, email: 'member@example.com' }),
      );
      const { guard, upsert } = buildGuard({
        verifyIdToken,
        findUnique,
        update,
      });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);

      await guard.canActivate(ctx);

      expect(update).toHaveBeenCalled();
      expect(upsert).not.toHaveBeenCalled();
      // A re-link found a real account, so no revocation round trip either.
      expect(verifyIdToken).toHaveBeenCalledTimes(1);
      expect(request.user?.id).toBe('internal-1');
    });

    // A new Firebase account that merely claims an admin's email or phone must
    // not inherit the admin row — that would make anyone who can register the
    // address (or mint a dummy-OTP session for the number) an admin.
    it.each([
      ['email', { uid: UID, email: 'admin@example.com' }],
      ['phone', { uid: UID, phone_number: '+919999999999' }],
    ])(
      'never re-links a staff row matched by %s to another Firebase account',
      async (_by, decoded) => {
        const findUnique = jest
          .fn()
          .mockResolvedValueOnce(null) // by firebaseUid
          .mockResolvedValueOnce({ id: 'admin-row', role: 'ADMIN' });
        const update = jest.fn();
        const { guard, upsert } = buildGuard({
          verifyIdToken: jest.fn(() => Promise.resolve(decoded)),
          findUnique,
          update,
        });
        const { ctx, request } = contextFor(`Bearer ${TOKEN}`);

        await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
          ForbiddenException,
        );
        expect(update).not.toHaveBeenCalled();
        expect(upsert).not.toHaveBeenCalled();
        expect(request.user).toBeUndefined();
      },
    );
  });
  // The bypass this guard used to carry, and must never carry again.
  //
  // `X-Dev-Auth-Phone` was honoured whenever `dummyAuthAllows()` passed, and
  // `DUMMY_OTP_ENABLED=true` makes that accept any well-formed E.164 number
  // with no NODE_ENV restriction. Measured against a backend running
  // NODE_ENV=production with that single flag, the header alone reached an
  // authenticated 404 rather than a 401 — it had already established identity.
  //
  // These deliberately run with the flags at their most permissive: that is
  // the configuration in which honouring the header would be dangerous, so it
  // is the configuration worth pinning.
  describe('accounts that may no longer use the API', () => {
    // Authentication answers "who is this"; this answers "are they still
    // allowed in". Before this existed a banned member kept full read access
    // to Discover and Search — every profile in the product, a page at a time.
    const verifyIdToken = () => jest.fn(() => Promise.resolve({ uid: UID }));

    it.each(['SUSPENDED', 'BANNED', 'DEACTIVATED'])(
      'refuses a %s account found in the database',
      async (status) => {
        const { guard } = buildGuard({
          verifyIdToken: verifyIdToken(),
          findUnique: jest.fn(() =>
            Promise.resolve({ id: 'internal-1', status, deletedAt: null }),
          ),
        });
        const { ctx } = contextFor(`Bearer ${TOKEN}`);

        // 403, not 401: the token is valid and signing in again changes
        // nothing.
        await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
          ForbiddenException,
        );
      },
    );

    it('refuses a soft-deleted account', async () => {
      const { guard } = buildGuard({
        verifyIdToken: verifyIdToken(),
        findUnique: jest.fn(() =>
          Promise.resolve({
            id: 'internal-1',
            status: 'PENDING_VERIFICATION',
            deletedAt: new Date(),
          }),
        ),
      });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    });

    it('refuses a suspended account served from the cache, without a DB read', async () => {
      // Otherwise a member suspended a moment ago keeps browsing for the rest
      // of the cache TTL.
      const findUnique = jest.fn();
      const { guard } = buildGuard({
        verifyIdToken: verifyIdToken(),
        findUnique,
        redis: redisServing({
          id: 'internal-1',
          status: 'SUSPENDED',
          deleted: false,
        }),
      });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(findUnique).not.toHaveBeenCalled();
    });

    it('still admits a normal account from the cache', async () => {
      const { guard } = buildGuard({
        verifyIdToken: verifyIdToken(),
        redis: redisServing({
          id: 'internal-1',
          status: 'PENDING_VERIFICATION',
          deleted: false,
        }),
      });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).resolves.toBe(true);
      expect(request.user?.id).toBe('internal-1');
    });

    it('admits PENDING_VERIFICATION and ACTIVE — the states every real member is in', async () => {
      for (const status of ['PENDING_VERIFICATION', 'ACTIVE']) {
        const { guard } = buildGuard({
          verifyIdToken: verifyIdToken(),
          findUnique: jest.fn(() =>
            Promise.resolve({ id: 'internal-1', status, deletedAt: null }),
          ),
        });
        const { ctx } = contextFor(`Bearer ${TOKEN}`);
        await expect(guard.canActivate(ctx)).resolves.toBe(true);
      }
    });

    it('admits a freshly created account', async () => {
      // The upsert path: a brand-new row is PENDING_VERIFICATION and must not
      // be caught by the denylist.
      const { guard } = buildGuard({
        verifyIdToken: verifyIdToken(),
        upsert: jest.fn(() =>
          Promise.resolve({
            id: 'internal-1',
            status: 'PENDING_VERIFICATION',
            deletedAt: null,
          }),
        ),
      });
      const { ctx } = contextFor(`Bearer ${TOKEN}`);

      await expect(guard.canActivate(ctx)).resolves.toBe(true);
    });
  });

  describe('the X-Dev-Auth-Phone bypass is closed', () => {
    const original = { ...process.env };

    beforeEach(() => {
      process.env.NODE_ENV = 'production';
      process.env.DUMMY_OTP_ENABLED = 'true';
      process.env.DEV_AUTH_ENABLED = 'true';
      delete process.env.DUMMY_OTP_PHONES;
      delete process.env.USE_REAL_OTP;
    });

    afterEach(() => {
      process.env = { ...original };
    });

    it('refuses the header alone', async () => {
      const verifyIdToken = jest.fn();
      const { guard, upsert } = buildGuard({ verifyIdToken });
      const { ctx, request } = contextFor(undefined);
      request.headers['x-dev-auth-phone'] = '+919876543210';

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      // No identity, and no account quietly provisioned for one either.
      expect(request.user).toBeUndefined();
      expect(upsert).not.toHaveBeenCalled();
      expect(verifyIdToken).not.toHaveBeenCalled();
    });

    it('does not let the header rescue an unverifiable token', async () => {
      const verifyIdToken = jest.fn(() => Promise.reject(new Error('bad sig')));
      const { guard, upsert } = buildGuard({ verifyIdToken });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);
      request.headers['x-dev-auth-phone'] = '+919876543210';

      await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(request.user).toBeUndefined();
      expect(upsert).not.toHaveBeenCalled();
    });

    it('still authenticates a valid token when the header is present', async () => {
      // The header must be inert, not poisonous: a genuine session alongside
      // it is unaffected, and identity comes from the token.
      const verifyIdToken = jest.fn(() => Promise.resolve({ uid: 'uid-1' }));
      const { guard } = buildGuard({ verifyIdToken });
      const { ctx, request } = contextFor(`Bearer ${TOKEN}`);
      request.headers['x-dev-auth-phone'] = '+919999999999';

      await expect(guard.canActivate(ctx)).resolves.toBe(true);
      expect(request.user?.uid).toBe('uid-1');
    });
  });
});
