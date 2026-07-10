import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { LoginDto } from '../dto/login.dto';

// firebase-admin/auth transitively pulls in jwks-rsa -> jose (ESM-only),
// which Jest's default CJS transform can't parse. Mocking both entry
// points keeps this a pure unit test — AuthService itself is mocked
// below anyway. See firebase.service.spec.ts for the same isolation.
jest.mock('firebase-admin/app', () => ({
  getApps: jest.fn(() => []),
  initializeApp: jest.fn(),
  cert: jest.fn(),
}));
jest.mock('firebase-admin/auth', () => ({
  getAuth: jest.fn(),
}));

import { AuthController } from '../controllers/auth.controller';
import { AuthService, FirebaseAuthResult } from '../services/auth.service';

describe('AuthController', () => {
  function buildController(authenticateWithFirebase: jest.Mock) {
    const authService = { authenticateWithFirebase } as unknown as AuthService;
    return new AuthController(authService);
  }

  it('delegates to AuthService.authenticateWithFirebase with the provided idToken', async () => {
    const response: FirebaseAuthResult = {
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      user: { id: 'user-1' } as FirebaseAuthResult['user'],
      needsEmailVerification: false,
    };
    const authenticateWithFirebase = jest.fn().mockResolvedValue(response);
    const controller = buildController(authenticateWithFirebase);

    const result = await controller.loginWithFirebase({
      idToken: 'firebase-id-token',
    });

    expect(authenticateWithFirebase).toHaveBeenCalledWith('firebase-id-token');
    expect(authenticateWithFirebase).toHaveBeenCalledTimes(1);
    expect(result).toBe(response);
  });

  it('propagates errors from AuthService without swallowing them', async () => {
    const error = new Error('invalid token');
    const authenticateWithFirebase = jest.fn().mockRejectedValue(error);
    const controller = buildController(authenticateWithFirebase);

    await expect(
      controller.loginWithFirebase({ idToken: 'bad-token' }),
    ).rejects.toBe(error);
  });
});

describe('LoginDto', () => {
  it('accepts a non-empty idToken string', async () => {
    const dto = plainToInstance(LoginDto, { idToken: 'firebase-id-token' });

    const errors = await validate(dto);

    expect(errors).toHaveLength(0);
  });

  it('rejects a missing idToken', async () => {
    const dto = plainToInstance(LoginDto, {});

    const errors = await validate(dto);

    expect(errors.length).toBeGreaterThan(0);
  });

  it('rejects an empty idToken', async () => {
    const dto = plainToInstance(LoginDto, { idToken: '' });

    const errors = await validate(dto);

    expect(errors.length).toBeGreaterThan(0);
  });
});
