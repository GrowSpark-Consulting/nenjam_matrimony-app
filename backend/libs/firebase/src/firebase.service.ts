import {
  Injectable,
  InternalServerErrorException,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { cert, getApps, initializeApp, App } from 'firebase-admin/app';
import { getAuth, DecodedIdToken, UserRecord } from 'firebase-admin/auth';
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
  /**
   * @param checkRevoked also confirm the account still exists and its tokens
   * have not been revoked since issue. This costs an extra Admin SDK lookup
   * per call, so it is opt-in rather than the default: the guard turns it on
   * only where the answer changes an outcome (see FirebaseAuthGuard), not on
   * the hot path of every authenticated request.
   *
   * Signature verification alone cannot see a deleted or revoked account — an
   * ID token stays cryptographically valid for up to an hour after either.
   */
  async verifyIdToken(
    idToken: string,
    checkRevoked = false,
  ): Promise<DecodedIdToken> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    return this.withTimeout(
      getAuth(this.app).verifyIdToken(idToken, checkRevoked),
      10_000,
      'Firebase token verification timed out — check outbound network ' +
        'connectivity to Google (securetoken.google.com / googleapis.com).',
    );
  }

  /**
   * Whether a Firebase Auth account already exists for this email or phone.
   *
   * Firebase Auth is the app's account store — there is no users table to
   * query — so the Admin SDK is the authoritative answer. `auth/user-not-found`
   * is the expected "no" and is not an error.
   *
   * Deliberately returns only a boolean per identifier: the caller is an
   * unauthenticated signup screen, and it has no business learning a uid, a
   * display name, or which provider an existing account uses.
   *
   * Throws when the SDK is unconfigured or the lookup genuinely fails, so a
   * caller can tell "definitely free" from "could not check" — treating the
   * latter as free is how duplicate accounts get created.
   */
  async accountExists(params: {
    email?: string | null;
    phone?: string | null;
  }): Promise<{ emailExists: boolean; phoneExists: boolean }> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    const auth = getAuth(this.app);

    const lookup = async (find: () => Promise<unknown>): Promise<boolean> => {
      try {
        await this.withTimeout(
          find(),
          10_000,
          'Firebase account lookup timed out.',
        );
        return true;
      } catch (error) {
        const code = (error as { code?: string })?.code;
        // The only "no" Firebase gives. Anything else — a network fault, a
        // bad credential — must surface, never be reported as available.
        if (code === 'auth/user-not-found') return false;
        if (
          code === 'auth/invalid-email' ||
          code === 'auth/invalid-phone-number'
        ) {
          return false;
        }
        throw error;
      }
    };

    const email = params.email?.trim().toLowerCase();
    const phone = params.phone?.trim();

    return {
      emailExists: email
        ? await lookup(() => auth.getUserByEmail(email))
        : false,
      phoneExists: phone
        ? await lookup(() => auth.getUserByPhoneNumber(phone))
        : false,
    };
  }

  /**
   * The Firebase Auth account for this phone (and email, when given),
   * creating it only if no account already holds either identifier.
   *
   * This is what makes the dummy-OTP flow produce a *real* account. Firebase
   * Auth is the app's account store, so "sign up" means an account exists
   * here — until this ran, the dummy OTP minted nothing and the member had no
   * Firebase identity at all, only a device-local marker.
   *
   * Idempotent by identifier, which is what the retry cases need:
   *   - same phone signing up again resolves to the same uid;
   *   - an address already used by another account is left alone rather than
   *     stolen from it (the phone is the identity here — see the caller);
   *   - a create that loses a race to a concurrent one re-reads instead of
   *     failing, because `auth/*-already-exists` means the account we wanted
   *     now exists.
   *
   * No password is set. Sign-in happens through a custom token
   * ([createCustomToken]) for exactly as long as the dummy OTP stands in for
   * real verification.
   *
   * [email] is used to FIND an existing account and is never written onto
   * one. An address Firebase has not verified, attached to the account, makes
   * `user.email != null && !user.emailVerified` true — and that is the exact
   * shape the app's routing reads as "this member owes us an email
   * verification", which would drop a dummy-OTP signup onto a verify-email
   * screen with nothing to resend and no way to pass. Nothing in this flow
   * verifies an address, so nothing in it may claim one: the address is kept
   * where it belongs, on the internal `users` row.
   */
  async findOrCreateUser(params: {
    phone: string;
    email?: string | null;
  }): Promise<{ uid: string; created: boolean }> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    const auth = getAuth(this.app);
    const phone = params.phone.trim();
    const email = params.email?.trim().toLowerCase() || undefined;

    const byIdentifier = async (
      find: () => Promise<UserRecord>,
    ): Promise<UserRecord | null> => {
      try {
        return await this.withTimeout(
          find(),
          10_000,
          'Firebase user lookup timed out.',
        );
      } catch (error) {
        const code = (error as { code?: string })?.code;
        if (
          code === 'auth/user-not-found' ||
          code === 'auth/invalid-email' ||
          code === 'auth/invalid-phone-number'
        ) {
          return null;
        }
        throw error;
      }
    };

    // The phone is the identity this flow verifies (however loosely), so it
    // is looked up first: an existing phone account is THE account, whatever
    // address the signup form also carried.
    const existing =
      (await byIdentifier(() => auth.getUserByPhoneNumber(phone))) ??
      (email ? await byIdentifier(() => auth.getUserByEmail(email)) : null);

    if (existing) return { uid: existing.uid, created: false };

    try {
      // Phone only — see the note above on why the address is not written.
      const created = await this.withTimeout(
        auth.createUser({ phoneNumber: phone }),
        10_000,
        'Firebase createUser timed out.',
      );
      this.logger.log(`Created Firebase auth user "${created.uid}".`);
      return { uid: created.uid, created: true };
    } catch (error) {
      const code = (error as { code?: string })?.code;
      // Lost a race to a concurrent signup: the account we wanted now exists,
      // so re-read it rather than failing.
      if (
        code === 'auth/phone-number-already-exists' ||
        code === 'auth/uid-already-exists'
      ) {
        const raced = await byIdentifier(() =>
          auth.getUserByPhoneNumber(phone),
        );
        if (raced) return { uid: raced.uid, created: false };
      }
      throw error;
    }
  }

  /**
   * A short-lived custom token the client exchanges for a real Firebase
   * session (`signInWithCustomToken`), after which it holds ordinary ID
   * tokens and every request authenticates through [verifyIdToken] like any
   * other. Nothing downstream can tell this session apart from one minted by
   * a real SMS — which is the point.
   *
   * Requires the service account to have the "Service Account Token Creator"
   * role; without it the Admin SDK cannot sign, and this throws rather than
   * returning something the client would fail on opaquely.
   */
  async createCustomToken(uid: string): Promise<string> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    return this.withTimeout(
      getAuth(this.app).createCustomToken(uid),
      10_000,
      'Firebase custom token minting timed out — check outbound ' +
        'connectivity to Google and the token-creator role on the service ' +
        'account.',
    );
  }

  /**
   * The Firebase account registered to [email], or null. Read-only; used by
   * the admin provisioning script to link a staff row to the account an
   * operator created in the Firebase console.
   */
  async findUserByEmail(email: string): Promise<{
    uid: string;
    email: string | undefined;
    emailVerified: boolean;
    disabled: boolean;
    hasPhone: boolean;
  } | null> {
    if (!this.app) {
      throw new InternalServerErrorException(
        'Firebase Admin SDK is not configured on this server.',
      );
    }
    try {
      const user = await this.withTimeout(
        getAuth(this.app).getUserByEmail(email.trim().toLowerCase()),
        10_000,
        'Firebase user lookup timed out.',
      );
      return {
        uid: user.uid,
        email: user.email,
        emailVerified: user.emailVerified,
        disabled: user.disabled,
        hasPhone: !!user.phoneNumber,
      };
    } catch (error) {
      if ((error as { code?: string })?.code === 'auth/user-not-found') {
        return null;
      }
      throw error;
    }
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
      timer = setTimeout(() => reject(new Error(timeoutMessage)), timeoutMs);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }
}
