import { Prisma, User, UserStatus } from '@app/database';
import { AuthRepository } from '../repositories/auth.repository';
import { TokenService } from '../services/token.service';
import { AuthService } from '../services/auth.service';

// firebase-admin/auth transitively pulls in jwks-rsa -> jose (ESM-only),
// which Jest's default CJS transform can't parse. Mocking both entry
// points keeps this a pure unit test — FirebaseTokenService itself is
// mocked below anyway. See firebase.service.spec.ts for the same isolation.
jest.mock('firebase-admin/app', () => ({
  getApps: jest.fn(() => []),
  initializeApp: jest.fn(),
  cert: jest.fn(),
}));
jest.mock('firebase-admin/auth', () => ({
  getAuth: jest.fn(),
}));

import { DecodedIdToken } from 'firebase-admin/auth';
import { FirebaseTokenService } from '../services/firebase-token.service';

function buildUser(overrides: Partial<User> = {}): User {
  return {
    id: 'user-1',
    firebaseUid: 'firebase-uid-1',
    email: 'user@example.com',
    emailVerified: true,
    phone: '+919999999999',
    role: 'USER',
    status: UserStatus.ACTIVE,
    trustScore: 0,
    createdAt: new Date(),
    updatedAt: new Date(),
    deletedAt: null,
    ...overrides,
  };
}

function buildDecodedToken(
  overrides: Partial<DecodedIdToken> = {},
): DecodedIdToken {
  return {
    uid: 'firebase-uid-1',
    email: 'user@example.com',
    email_verified: true,
    phone_number: '+919999999999',
    aud: 'demo-project',
    auth_time: 0,
    exp: 0,
    iat: 0,
    iss: 'https://securetoken.google.com/demo-project',
    sub: 'firebase-uid-1',
    firebase: { identities: {}, sign_in_provider: 'phone' },
    ...overrides,
  };
}

describe('AuthService', () => {
  function buildService(overrides?: {
    findByFirebaseUid?: jest.Mock;
    create?: jest.Mock;
    update?: jest.Mock;
    verifyIdToken?: jest.Mock;
    generateTokenPair?: jest.Mock;
  }) {
    const authRepository = {
      findByFirebaseUid: overrides?.findByFirebaseUid ?? jest.fn(),
      create: overrides?.create ?? jest.fn(),
      update: overrides?.update ?? jest.fn(),
    } as unknown as AuthRepository;

    const firebaseTokenService = {
      verifyIdToken: overrides?.verifyIdToken ?? jest.fn(),
    } as unknown as FirebaseTokenService;

    const tokenService = {
      generateTokenPair:
        overrides?.generateTokenPair ??
        jest.fn().mockReturnValue({
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        }),
    } as unknown as TokenService;

    const service = new AuthService(
      authRepository,
      firebaseTokenService,
      tokenService,
    );

    return { service, authRepository, firebaseTokenService, tokenService };
  }

  describe('findOrCreateUser', () => {
    it('updates and returns the existing user by firebaseUid', async () => {
      const existingUser = buildUser();
      const updatedUser = buildUser({ phone: '+911111111111' });
      const findByFirebaseUid = jest.fn().mockResolvedValue(existingUser);
      const update = jest.fn().mockResolvedValue(updatedUser);
      const create = jest.fn();
      const { service } = buildService({ findByFirebaseUid, update, create });

      const result = await service.findOrCreateUser(
        buildDecodedToken({ phone_number: '+911111111111' }),
      );

      expect(update).toHaveBeenCalledWith(existingUser.id, {
        phone: '+911111111111',
        email: 'user@example.com',
        emailVerified: true,
      });
      expect(create).not.toHaveBeenCalled();
      expect(result).toBe(updatedUser);
    });

    it('does not overwrite the stored email when the token carries none', async () => {
      const existingUser = buildUser();
      const findByFirebaseUid = jest.fn().mockResolvedValue(existingUser);
      const update = jest.fn().mockResolvedValue(existingUser);
      const { service } = buildService({ findByFirebaseUid, update });

      await service.findOrCreateUser(
        buildDecodedToken({ email: undefined, email_verified: undefined }),
      );

      expect(update).toHaveBeenCalledWith(existingUser.id, {
        phone: '+919999999999',
      });
    });

    it('does not touch phone when the token carries none', async () => {
      const existingUser = buildUser();
      const findByFirebaseUid = jest.fn().mockResolvedValue(existingUser);
      const update = jest.fn().mockResolvedValue(existingUser);
      const { service } = buildService({ findByFirebaseUid, update });

      await service.findOrCreateUser(
        buildDecodedToken({ phone_number: undefined }),
      );

      expect(update).toHaveBeenCalledWith(existingUser.id, {
        email: 'user@example.com',
        emailVerified: true,
      });
    });

    it('creates a new user from the decoded token when none exists', async () => {
      const findByFirebaseUid = jest.fn().mockResolvedValue(null);
      const createdUser = buildUser();
      const create = jest.fn().mockResolvedValue(createdUser);
      const { service } = buildService({ findByFirebaseUid, create });

      const result = await service.findOrCreateUser(buildDecodedToken());

      expect(create).toHaveBeenCalledWith({
        firebaseUid: 'firebase-uid-1',
        phone: '+919999999999',
        email: 'user@example.com',
        emailVerified: true,
      });
      expect(result).toBe(createdUser);
    });

    it('creates a phone-only user with a null email when Firebase provides none', async () => {
      const findByFirebaseUid = jest.fn().mockResolvedValue(null);
      const create = jest.fn().mockResolvedValue(buildUser({ email: null }));
      const { service } = buildService({ findByFirebaseUid, create });

      await service.findOrCreateUser(
        buildDecodedToken({ email: undefined, email_verified: undefined }),
      );

      expect(create).toHaveBeenCalledWith({
        firebaseUid: 'firebase-uid-1',
        phone: '+919999999999',
        email: null,
        emailVerified: false,
      });
    });

    it('resolves a concurrent-create race by re-fetching the winning row', async () => {
      const winner = buildUser();
      const findByFirebaseUid = jest
        .fn()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(winner);
      const raceError = new Prisma.PrismaClientKnownRequestError('duplicate', {
        code: 'P2002',
        clientVersion: '7.8.0',
      });
      const create = jest.fn().mockRejectedValue(raceError);
      const { service } = buildService({ findByFirebaseUid, create });

      const result = await service.findOrCreateUser(buildDecodedToken());

      expect(result).toBe(winner);
      expect(findByFirebaseUid).toHaveBeenCalledTimes(2);
    });

    it('rethrows non-unique-constraint errors from create', async () => {
      const findByFirebaseUid = jest.fn().mockResolvedValue(null);
      const otherError = new Error('database is down');
      const create = jest.fn().mockRejectedValue(otherError);
      const { service } = buildService({ findByFirebaseUid, create });

      await expect(service.findOrCreateUser(buildDecodedToken())).rejects.toBe(
        otherError,
      );
    });
  });

  describe('authenticateWithFirebase', () => {
    it('verifies the token, syncs the user, and returns tokens with needsEmailVerification=false', async () => {
      const decoded = buildDecodedToken();
      const user = buildUser({
        email: 'user@example.com',
        emailVerified: true,
      });
      const verifyIdToken = jest.fn().mockResolvedValue(decoded);
      const findByFirebaseUid = jest.fn().mockResolvedValue(user);
      const update = jest.fn().mockResolvedValue(user);
      const generateTokenPair = jest.fn().mockReturnValue({
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      });
      const { service } = buildService({
        verifyIdToken,
        findByFirebaseUid,
        update,
        generateTokenPair,
      });

      const result = await service.authenticateWithFirebase('id-token');

      expect(verifyIdToken).toHaveBeenCalledWith('id-token');
      expect(generateTokenPair).toHaveBeenCalledWith(user);
      expect(result).toEqual({
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        user,
        needsEmailVerification: false,
      });
    });

    it('flags needsEmailVerification when the user has no email yet', async () => {
      const user = buildUser({ email: null, emailVerified: false });
      const verifyIdToken = jest
        .fn()
        .mockResolvedValue(
          buildDecodedToken({ email: undefined, email_verified: undefined }),
        );
      const findByFirebaseUid = jest.fn().mockResolvedValue(user);
      const update = jest.fn().mockResolvedValue(user);
      const { service } = buildService({
        verifyIdToken,
        findByFirebaseUid,
        update,
      });

      const result = await service.authenticateWithFirebase('id-token');

      expect(result.needsEmailVerification).toBe(true);
    });

    it('flags needsEmailVerification when the email exists but is unverified', async () => {
      const user = buildUser({
        email: 'user@example.com',
        emailVerified: false,
      });
      const verifyIdToken = jest.fn().mockResolvedValue(buildDecodedToken());
      const findByFirebaseUid = jest.fn().mockResolvedValue(user);
      const update = jest.fn().mockResolvedValue(user);
      const { service } = buildService({
        verifyIdToken,
        findByFirebaseUid,
        update,
      });

      const result = await service.authenticateWithFirebase('id-token');

      expect(result.needsEmailVerification).toBe(true);
    });
  });
});
