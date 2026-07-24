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
  //
  // On a cache miss, the Admin SDK fetches Google's public signing certs over
  // HTTPS before it can verify the signature. Neither the SDK nor Node's
  // underlying http client apply a timeout to that fetch, so if outbound
  // HTTPS to Google (proxy/firewall/DNS) is blocked or black-holed, this call
  // hangs forever with no error — every request behind FirebaseAuthGuard
  // stalls silently. The explicit timeout below turns that into a fast,
  // diagnosable error instead.
  async verifyIdToken(idToken: string): Promise<DecodedIdToken> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    return this.withTimeout(
      getAuth(this.app).verifyIdToken(idToken),
      10_000,
      'Firebase token verification timed out — check outbound network ' +
        'connectivity to Google (securetoken.google.com / googleapis.com).',
    );
  }

  /**
   * Permanently deletes the Firebase Auth user, revoking every session plus all
   * ID/refresh tokens so a deleted account can never authenticate again. Used by
   * the hard account-deletion flow.
   *
   * Idempotent and non-fatal by design: a missing user (`auth/user-not-found`)
   * is treated as already-done, and a missing Admin SDK config or any other
   * failure is logged rather than thrown — account deletion (the DB + storage
   * cleanup) must not be blocked by an auth-provider hiccup.
   */
  async deleteUser(firebaseUid: string): Promise<void> {
    if (!this.app) {
      this.logger.warn(
        'Firebase Admin SDK not configured — skipping auth user deletion.',
      );
      return;
    }
    try {
      await this.withTimeout(
        getAuth(this.app).deleteUser(firebaseUid),
        10_000,
        'Firebase deleteUser timed out — check outbound connectivity to Google.',
      );
      this.logger.log(`Deleted Firebase auth user "${firebaseUid}".`);
    } catch (error) {
      if ((error as { code?: string }).code === 'auth/user-not-found') {
        return;
      }
      this.logger.error(
        `Failed to delete Firebase auth user "${firebaseUid}": ${(error as Error).message}`,
      );
    }
  }

  private withTimeout<T>(
    promise: Promise<T>,
    timeoutMs: number,
    timeoutMessage: string,
  ): Promise<T> {
    let timer: NodeJS.Timeout;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(
        () => reject(new Error(timeoutMessage)),
        timeoutMs,
      );
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }
}
