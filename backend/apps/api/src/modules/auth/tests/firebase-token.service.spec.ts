import { Test, TestingModule } from '@nestjs/testing';
import { FirebaseTokenService } from '../services/firebase-token.service';

// firebase-admin/auth transitively pulls in jwks-rsa -> jose (ESM-only),
// which Jest's default CJS transform can't parse. Mocking both entry
// points here keeps this a pure unit test of the delegation logic below
// without loading the real Firebase Admin SDK. See firebase.service.spec.ts
// for the equivalent isolation on the FirebaseService side.
jest.mock('firebase-admin/app', () => ({
  getApps: jest.fn(() => []),
  initializeApp: jest.fn(),
  cert: jest.fn(),
}));
jest.mock('firebase-admin/auth', () => ({
  getAuth: jest.fn(),
}));

import { FirebaseService } from '@app/firebase';

describe('FirebaseTokenService', () => {
  async function buildService(
    firebaseService: Partial<FirebaseService>,
  ): Promise<FirebaseTokenService> {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FirebaseTokenService,
        { provide: FirebaseService, useValue: firebaseService },
      ],
    }).compile();

    return module.get(FirebaseTokenService);
  }

  it('delegates verification to FirebaseService and returns the decoded token', async () => {
    const decoded = {
      uid: 'uid-1',
      email: 'user@example.com',
      phone_number: '+919999999999',
      email_verified: true,
    };
    const verifyIdToken = jest.fn().mockResolvedValue(decoded);
    const service = await buildService({ verifyIdToken });

    const result = await service.verifyIdToken('token-abc');

    expect(verifyIdToken).toHaveBeenCalledWith('token-abc');
    expect(result).toBe(decoded);
  });

  it('propagates verification failures', async () => {
    const error = new Error('invalid token');
    const verifyIdToken = jest.fn().mockRejectedValue(error);
    const service = await buildService({ verifyIdToken });

    await expect(service.verifyIdToken('bad-token')).rejects.toBe(error);
  });
});
