import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
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

function buildGuard(opts: {
  verifyIdToken: jest.Mock;
  findUnique?: jest.Mock;
  upsert?: jest.Mock;
  update?: jest.Mock;
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
    guard: new FirebaseAuthGuard(firebase, prisma, redisDown()),
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
  });
});
