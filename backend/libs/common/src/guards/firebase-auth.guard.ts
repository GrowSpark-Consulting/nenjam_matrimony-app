import {
  CanActivate,
  ExecutionContext,
  Injectable,
  InternalServerErrorException,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { FirebaseService } from '@app/firebase';
import { PrismaService } from '@app/database';
import { RedisService } from '@app/cache';
import type { AuthenticatedUser } from '../decorators/current-user.decorator';
import { getCachedUserId, setCachedUserId } from '../auth/auth-user-cache';

interface RequestWithUser extends Request {
  user?: AuthenticatedUser;
}

// Verifies the `Authorization: Bearer <Firebase ID Token>` header via the
// Firebase Admin SDK, then just-in-time provisions (or reuses) the matching
// internal User row keyed by the token's `uid`. request.user.id is that
// internal row's id — every downstream repository/service call filters by
// it, which is 1:1 with the Firebase UID via User.firebaseUid's unique
// constraint, so ownership is always derived from the verified token, never
// from anything the client sends.
@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private readonly logger = new Logger(FirebaseAuthGuard.name);

  constructor(
    private readonly firebaseService: FirebaseService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithUser>();

    const authHeader = request.headers.authorization;

    // A verified Firebase ID token is the ONLY thing that authenticates a
    // request. There is deliberately no second mechanism.
    //
    // There used to be one: an `X-Dev-Auth-Phone` header, honoured whenever
    // `dummyAuthAllows()` passed. The comment here used to claim it was
    // "local development only" and dead in production. It was not.
    // `DUMMY_OTP_ENABLED=true` makes that helper accept any well-formed E.164
    // number with NO NODE_ENV restriction, so on a deployed server the header
    // alone authenticated the caller as any member — no token, no OTP, no
    // Firebase. Measured against a backend running NODE_ENV=production with
    // that single flag: `curl -H 'X-Dev-Auth-Phone: +91…' /profiles/me`
    // returned 404 ("no profile yet"), i.e. it had already authenticated.
    //
    // It also resolved to a SECOND identity — `devauth:<phone>` — distinct
    // from the real Firebase uid the same person gets from
    // `POST /auth/dummy-otp/session`, so one number could own two accounts and
    // split its data between them.
    //
    // Every client path now ends in a real Firebase session: signup and
    // mobile+OTP login exchange the dummy code for a custom token, and
    // mobile+password login does the same after its account check. Nothing is
    // left for a header to fill in.
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException(
        'Missing "Authorization: Bearer <Firebase ID Token>" header.',
      );
    }
    const idToken = authHeader.slice('Bearer '.length).trim();
    if (!idToken) {
      throw new UnauthorizedException('Empty bearer token.');
    }

    const decoded = await this.verify(idToken);
    request.user = await this.resolveUser(decoded, idToken);
    return true;
  }

  private async verify(idToken: string, checkRevoked = false) {
    try {
      return await this.firebaseService.verifyIdToken(idToken, checkRevoked);
    } catch (error) {
      if (error instanceof InternalServerErrorException) {
        // Server misconfiguration (no Firebase Admin credentials) — not the
        // client's fault, so this must not be reported as a 401.
        throw error;
      }
      this.logger.warn(
        `Rejected Firebase ID token: ${(error as Error).message}`,
      );
      throw new UnauthorizedException('Invalid or expired Firebase ID token.');
    }
  }

  private async resolveUser(
    decoded: {
      uid: string;
      email?: string;
      phone_number?: string;
    },
    idToken: string,
  ): Promise<AuthenticatedUser> {
    // Fast path: the firebaseUid → internal user.id mapping is near-immutable,
    // so a cache hit lets us skip the DB round trip entirely (the only DB hop
    // on the hot path of every authenticated request). uid/email/phone_number
    // below come from the verified token, not the DB, so a cached id is enough
    // to build the full AuthenticatedUser. Fails open — a miss / Redis-down
    // just falls through to the authoritative DB reconciliation below.
    const cachedId = await getCachedUserId(this.redis, decoded.uid);
    if (cachedId) {
      return {
        id: cachedId,
        uid: decoded.uid,
        email: decoded.email,
        phone_number: decoded.phone_number,
      };
    }

    // User.email is required + unique in the schema; phone-only Firebase
    // accounts have no email, so we synthesize a stable placeholder keyed to
    // the uid — it's never shown to the user and never collides.
    const email = decoded.email ?? `${decoded.uid}@firebase.invalid`;

    // Firebase UIDs are not permanently stable for a given person — the
    // Firebase account can be deleted and re-created (routine during dev/QA
    // testing, but also possible in production account-recovery flows)
    // while `email` remains this system's durable identity. Upserting on
    // firebaseUid alone would then try to CREATE a second row with the same
    // email and crash on the unique constraint (this is exactly what
    // produced a bare 500 on PATCH /profiles/draft/basic-details). Reconcile
    // by firebaseUid first, then fall back to re-linking an existing row
    // found by email instead of failing.
    let user = await this.prisma.user.findUnique({
      where: { firebaseUid: decoded.uid },
    });

    if (!user && decoded.email) {
      const existingByEmail = await this.prisma.user.findUnique({
        where: { email: decoded.email },
      });
      if (existingByEmail) {
        this.logger.log(
          `Re-linking existing user ${existingByEmail.id} to new Firebase uid=${decoded.uid} (was ${existingByEmail.firebaseUid})`,
        );
        user = await this.prisma.user.update({
          where: { id: existingByEmail.id },
          data: {
            firebaseUid: decoded.uid,
            ...(decoded.phone_number ? { phone: decoded.phone_number } : {}),
          },
        });
      }
    }

    // Same rotation problem for phone-only accounts (no email at all) —
    // without this, a phone-only user's UID rotation silently creates a
    // second User row via the upsert below instead of re-linking.
    if (!user && !decoded.email && decoded.phone_number) {
      const existingByPhone = await this.prisma.user.findUnique({
        where: { phone: decoded.phone_number },
      });
      if (existingByPhone) {
        this.logger.log(
          `Re-linking existing user ${existingByPhone.id} to new Firebase uid=${decoded.uid} (was ${existingByPhone.firebaseUid})`,
        );
        user = await this.prisma.user.update({
          where: { id: existingByPhone.id },
          data: { firebaseUid: decoded.uid },
        });
      }
    }

    // Nothing matched by uid, email or phone, so the next step CREATES an
    // account. Before it does, re-verify the token against Firebase with
    // revocation checking.
    //
    // Signature verification alone cannot tell a first-ever sign-in from a
    // token belonging to an account that was just deleted: an ID token stays
    // cryptographically valid for up to an hour afterwards. AccountDeletion
    // deletes the Firebase user, then the row, then the cache — but a stale
    // token arriving inside that hour would land here and the upsert would
    // silently re-create the row the user asked to have erased, as a fresh
    // account with no profile. `checkRevoked` asks Firebase whether the
    // account still exists and the token still stands, which is the only
    // thing that can distinguish the two cases.
    //
    // Deliberately only on this path. It costs an extra Admin SDK round trip,
    // and every other path above already found a row — proof the account is
    // real — so the hot path of authenticated requests is untouched. This
    // runs once per genuinely new account.
    if (!user) {
      await this.verify(idToken, true);
    }

    user ??= await this.prisma.user.upsert({
      where: { firebaseUid: decoded.uid },
      update: {
        ...(decoded.email ? { email: decoded.email } : {}),
        ...(decoded.phone_number ? { phone: decoded.phone_number } : {}),
      },
      create: {
        firebaseUid: decoded.uid,
        email,
        phone: decoded.phone_number,
      },
    });

    // Populate the cache so subsequent requests for this UID skip the DB. Best
    // effort — a Redis failure here must not fail the request.
    await setCachedUserId(this.redis, decoded.uid, user.id);

    return {
      id: user.id,
      uid: decoded.uid,
      email: decoded.email,
      phone_number: decoded.phone_number,
    };
  }
}
