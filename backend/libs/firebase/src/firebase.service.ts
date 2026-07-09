import {
  Injectable,
  InternalServerErrorException,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { cert, getApps, initializeApp, App } from 'firebase-admin/app';
import { getAuth, DecodedIdToken } from 'firebase-admin/auth';
import { AppConfigService } from '@app/config';

@Injectable()
export class FirebaseService implements OnModuleInit {
  private readonly logger = new Logger(FirebaseService.name);
  private app: App | null = null;

  constructor(private readonly configService: AppConfigService) {}

  onModuleInit(): void {
    const { projectId, clientEmail, privateKey } = this.configService.firebase;

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'Firebase Admin SDK not configured (FIREBASE_PROJECT_ID / ' +
          'FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY missing) — ' +
          'endpoints behind FirebaseAuthGuard will fail until these are set.',
      );
      return;
    }

    this.app =
      getApps()[0] ??
      initializeApp({
        credential: cert({ projectId, clientEmail, privateKey }),
      });
    this.logger.log(
      `Firebase Admin SDK initialized for project "${projectId}".`,
    );
  }

  // Verifies a client-supplied Firebase ID token (a signed JWT). Throws on
  // any invalid/expired/malformed token — callers (FirebaseAuthGuard) decide
  // how to map that to an HTTP response.
  async verifyIdToken(idToken: string): Promise<DecodedIdToken> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    return getAuth(this.app).verifyIdToken(idToken);
  }
}
