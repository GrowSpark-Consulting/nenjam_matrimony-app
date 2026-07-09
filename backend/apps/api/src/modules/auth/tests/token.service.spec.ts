import { JwtService } from '@nestjs/jwt';
import { User, UserStatus } from '@app/database';
import { JwtPayload, TokenService } from '../services/token.service';

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

describe('TokenService', () => {
  const jwtService = new JwtService({ secret: 'test-secret-value' });
  const service = new TokenService(jwtService);

  it('generates an access token carrying only application identity claims', () => {
    const user = buildUser();

    const token = service.generateAccessToken(user);
    const payload = jwtService.verify<JwtPayload>(token);

    expect(payload.userId).toBe(user.id);
    expect(payload.firebaseUid).toBe(user.firebaseUid);
    expect(payload.phoneNumber).toBe(user.phone);
    expect(payload.type).toBe('access');
  });

  it('generates a refresh token distinguishable from an access token', () => {
    const user = buildUser();

    const token = service.generateRefreshToken(user);
    const payload = jwtService.verify<JwtPayload>(token);

    expect(payload.type).toBe('refresh');
    expect(payload.userId).toBe(user.id);
  });

  it('generates a token pair with independently valid access and refresh tokens', () => {
    const user = buildUser();

    const { accessToken, refreshToken } = service.generateTokenPair(user);

    expect(jwtService.verify<JwtPayload>(accessToken).type).toBe('access');
    expect(jwtService.verify<JwtPayload>(refreshToken).type).toBe('refresh');
    expect(accessToken).not.toBe(refreshToken);
  });

  it('carries a null phoneNumber when the user has none', () => {
    const user = buildUser({ phone: null });

    const token = service.generateAccessToken(user);
    const payload = jwtService.verify<JwtPayload>(token);

    expect(payload.phoneNumber).toBeNull();
  });

  it('does not leak Firebase-specific or email claims into the payload', () => {
    const user = buildUser();

    const token = service.generateAccessToken(user);
    const payload = jwtService.decode<Record<string, unknown>>(token);

    expect(payload).not.toHaveProperty('firebase');
    expect(payload).not.toHaveProperty('uid');
    expect(payload).not.toHaveProperty('email');
    expect(payload).not.toHaveProperty('role');
  });
});
