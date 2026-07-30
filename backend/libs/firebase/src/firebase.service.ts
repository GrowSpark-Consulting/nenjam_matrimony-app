import {
  Injectable,
  InternalServerErrorException,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { cert, getApps, initializeApp, App } from 'firebase-admin/app';
import { getAuth, DecodedIdToken } from 'firebase-admin/auth';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';
import { AppConfigService } from '@app/config';

// FCM error codes that mean the token itself is dead and will never succeed
// again — as opposed to a transient failure (quota, network) that should
// leave the token alone and just be retried later.
const UNREGISTERED_TOKEN_ERROR_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// sendEachForMulticast caps out at 500 tokens per call.
const FCM_MULTICAST_BATCH_SIZE = 500;

export interface PushSendResult {
  /** Tokens FCM rejected as permanently dead — the caller should deactivate
   *  these so they're never retried. */
  invalidTokens: string[];
}

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

  /**
   * Sends one notification + data payload to a batch of FCM device tokens.
   * `data` values must already be strings (FCM's wire requirement — callers
   * are responsible for stringifying). Never throws for a bad individual
   * token — those come back via `invalidTokens` so the caller can deactivate
   * them; only a total transport/config failure throws.
   */
  async sendMulticastPush(
    tokens: string[],
    notification: { title: string; body: string },
    data?: Record<string, string>,
  ): Promise<PushSendResult> {
    if (!this.app) {
      this.logger.warn(
        'Firebase Admin SDK not configured — skipping push send.',
      );
      return { invalidTokens: [] };
    }
    if (tokens.length === 0) return { invalidTokens: [] };

    const messaging = getMessaging(this.app);
    const invalidTokens: string[] = [];

    for (let i = 0; i < tokens.length; i += FCM_MULTICAST_BATCH_SIZE) {
      const batch = tokens.slice(i, i + FCM_MULTICAST_BATCH_SIZE);
      const message: MulticastMessage = { tokens: batch, notification, data };
      const response = await messaging.sendEachForMulticast(message);
      response.responses.forEach((result, index) => {
        if (result.success) return;
        const code = result.error?.code;
        if (code && UNREGISTERED_TOKEN_ERROR_CODES.has(code)) {
          invalidTokens.push(batch[index]);
        } else {
          this.logger.warn(
            `Push send failed for a device token (${code ?? 'unknown error'}): ${result.error?.message}`,
          );
        }
      });
    }

    return { invalidTokens };
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
