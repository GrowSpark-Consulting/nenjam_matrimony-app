import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { Auth, DecodedIdToken, getAuth } from 'firebase-admin/auth';
import { AppConfigService } from '@app/config';

@Injectable()
export class FirebaseService implements OnModuleInit {
  private readonly logger = new Logger(FirebaseService.name);
  private app!: App;

  constructor(private readonly configService: AppConfigService) {}

  onModuleInit(): void {
    const { projectId, clientEmail, privateKey } = this.configService.firebase;

    if (!projectId || !clientEmail || !privateKey) {
      const message =
        'Firebase Admin credentials are missing. Set FIREBASE_PROJECT_ID, ' +
        'FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY.';
      this.logger.error(message);
      throw new Error(message);
    }

    const existingApps = getApps();

    try {
      this.app =
        existingApps.length > 0
          ? existingApps[0]
          : initializeApp({
              credential: cert({ projectId, clientEmail, privateKey }),
            });
    } catch (error) {
      this.logger.error(
        `Firebase Admin initialization failed: ${this.describeError(error)}`,
      );
      throw error;
    }

    this.logger.log(
      [
        '=====================================',
        'FIREBASE ADMIN',
        '',
        `Project     : ${projectId}`,
        `Initialized : ${existingApps.length > 0 ? 'REUSED EXISTING APP' : 'SUCCESS'}`,
        '',
        '=====================================',
      ].join('\n'),
    );
  }

  getAuth(): Auth {
    return getAuth(this.app);
  }

  async verifyIdToken(idToken: string): Promise<DecodedIdToken> {
    try {
      return await this.getAuth().verifyIdToken(idToken);
    } catch (error) {
      this.logger.warn(
        `Firebase ID token verification failed: ${this.describeError(error)}`,
      );
      throw error;
    }
  }

  async createCustomToken(uid: string, claims?: object): Promise<string> {
    try {
      return await this.getAuth().createCustomToken(uid, claims);
    } catch (error) {
      this.logger.error(
        `Firebase custom token creation failed: ${this.describeError(error)}`,
      );
      throw error;
    }
  }

  // Firebase Auth errors carry a stable "auth/..." code — classify the ones
  // callers are most likely to hit so logs stay actionable.
  private describeError(error: unknown): string {
    const err = error as { code?: string; message?: string } | undefined;

    switch (err?.code) {
      case 'auth/id-token-expired':
        return 'Firebase ID token has expired.';
      case 'auth/id-token-revoked':
        return 'Firebase ID token has been revoked.';
      case 'auth/argument-error':
        return 'Malformed Firebase ID token.';
      case 'auth/invalid-credential':
        return 'Invalid Firebase Admin credentials (check FIREBASE_* env vars).';
      default:
        return err?.message ?? 'Unknown Firebase Auth error.';
    }
  }
}
