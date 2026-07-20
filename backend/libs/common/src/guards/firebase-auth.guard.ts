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
import type { AuthenticatedUser } from '../decorators/current-user.decorator';

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
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithUser>();

    const authHeader = request.headers.authorization;

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
    request.user = await this.resolveUser(decoded);
    return true;
  }

  private async verify(idToken: string) {
    try {
      return await this.firebaseService.verifyIdToken(idToken);
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

  private async resolveUser(decoded: {
    uid: string;
    email?: string;
    phone_number?: string;
  }): Promise<AuthenticatedUser> {
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

    return {
      id: user.id,
      uid: decoded.uid,
      email: decoded.email,
      phone_number: decoded.phone_number,
    };
  }
}
