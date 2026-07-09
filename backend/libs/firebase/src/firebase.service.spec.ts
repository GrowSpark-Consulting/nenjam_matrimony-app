import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AppConfigService } from '@app/config';
import { FirebaseService } from './firebase.service';

jest.mock('firebase-admin/app', () => ({
  getApps: jest.fn(),
  initializeApp: jest.fn(),
  cert: jest.fn((options: unknown) => options),
}));

jest.mock('firebase-admin/auth', () => ({
  getAuth: jest.fn(),
}));

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

describe('FirebaseService', () => {
  const mockApp = { name: '[DEFAULT]' };
  const mockAuth = {
    verifyIdToken: jest.fn(),
    createCustomToken: jest.fn(),
  };

  const mockConfig = {
    firebase: {
      projectId: 'demo-project',
      clientEmail: 'sa@demo-project.iam.gserviceaccount.com',
      privateKey:
        '-----BEGIN PRIVATE KEY-----\nMOCK\n-----END PRIVATE KEY-----\n',
    },
  } as unknown as AppConfigService;

  async function buildService(
    config: AppConfigService = mockConfig,
  ): Promise<FirebaseService> {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FirebaseService,
        { provide: AppConfigService, useValue: config },
      ],
    }).compile();

    return module.get(FirebaseService);
  }

  beforeEach(() => {
    jest.clearAllMocks();
    (getApps as jest.Mock).mockReturnValue([]);
    (initializeApp as jest.Mock).mockReturnValue(mockApp);
    (getAuth as jest.Mock).mockReturnValue(mockAuth);
  });

  it('initializes a new app when none exists', async () => {
    const service = await buildService();
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    service.onModuleInit();

    expect(cert).toHaveBeenCalledWith({
      projectId: 'demo-project',
      clientEmail: 'sa@demo-project.iam.gserviceaccount.com',
      privateKey: mockConfig.firebase.privateKey,
    });
    expect(initializeApp).toHaveBeenCalled();
    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('FIREBASE ADMIN');
    expect(output).toContain('SUCCESS');

    logSpy.mockRestore();
  });

  it('reuses an existing app instead of re-initializing', async () => {
    (getApps as jest.Mock).mockReturnValue([mockApp]);
    const service = await buildService();
    const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

    service.onModuleInit();

    expect(initializeApp).not.toHaveBeenCalled();
    const output = logSpy.mock.calls.map((call) => String(call[0])).join('\n');
    expect(output).toContain('REUSED EXISTING APP');

    logSpy.mockRestore();
  });

  it('throws when Firebase credentials are missing', async () => {
    const emptyConfig = {
      firebase: { projectId: '', clientEmail: '', privateKey: '' },
    } as unknown as AppConfigService;
    const service = await buildService(emptyConfig);
    const errorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation();

    expect(() => service.onModuleInit()).toThrow(/credentials are missing/i);

    errorSpy.mockRestore();
  });

  it('verifies an ID token via the Auth client', async () => {
    const decoded = { uid: 'abc', email: 'a@b.com' };
    mockAuth.verifyIdToken.mockResolvedValue(decoded);
    const service = await buildService();
    service.onModuleInit();

    const result = await service.verifyIdToken('token-123');

    expect(mockAuth.verifyIdToken).toHaveBeenCalledWith('token-123');
    expect(result).toBe(decoded);
  });

  it('logs and rethrows when token verification fails', async () => {
    const error = Object.assign(new Error('expired'), {
      code: 'auth/id-token-expired',
    });
    mockAuth.verifyIdToken.mockRejectedValue(error);
    const service = await buildService();
    service.onModuleInit();
    const warnSpy = jest.spyOn(Logger.prototype, 'warn').mockImplementation();

    await expect(service.verifyIdToken('token-123')).rejects.toBe(error);
    expect(
      warnSpy.mock.calls.map((call) => String(call[0])).join('\n'),
    ).toContain('expired');

    warnSpy.mockRestore();
  });

  it('creates a custom token via the Auth client', async () => {
    mockAuth.createCustomToken.mockResolvedValue('custom-token');
    const service = await buildService();
    service.onModuleInit();

    const token = await service.createCustomToken('uid-1');

    expect(mockAuth.createCustomToken).toHaveBeenCalledWith('uid-1', undefined);
    expect(token).toBe('custom-token');
  });
});
