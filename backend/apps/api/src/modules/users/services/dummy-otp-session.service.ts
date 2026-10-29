import {
  ConflictException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@app/database';
import { FirebaseService } from '@app/firebase';
import { dummyAuthAllows, isStaffRole } from '@app/common';
import { DummyOtpSessionResponseDto } from '../dto/dummy-otp-session.dto';

/**
 * Turns a passed dummy OTP into a REAL Firebase session.
 *
 * ## Why this exists
 *
 * Signup collects a whole profile signed out and ends at an OTP screen that
 * verifies nothing (`MockOtpVerifier`, client side) because SMS billing is not
 * on yet. The step used to record a device-local marker and authenticate every
 * later request with an `X-Dev-Auth-Phone` header, which meant a member could
 * finish signup with **no Firebase account and no `users` row** — invisible in
 * the Firebase console, absent from the database, and unable to load their own
 * profile the moment that header was not honoured.
 *
 * This closes that gap without touching the OTP mechanism: the code is still
 * checked by the same mock, and what changes is only what a pass *produces* —
 * a Firebase Auth account, the internal `users` row keyed to its uid, and a
 * custom token the client exchanges for an ordinary session. Everything
 * downstream (FirebaseAuthGuard, `registration_steps`, `user_profiles`,
 * `GET /profiles/draft`) then works through the real uid with no special case.
 *
 * ## Why it is bounded exactly like the header it replaces
 *
 * Minting a session for a number nobody sent an SMS to is a genuine
 * authentication bypass — the same one `dev-auth.ts` already governs — so it
 * answers to the same policy ([dummyAuthAllows]): both flags default to off,
 * a non-empty `DUMMY_OTP_PHONES` narrows it to those numbers (empty admits any
 * well-formed number, in production too), and `USE_REAL_OTP=true` disables it
 * outright.
 * It is deliberately not a second, looser switch.
 */
@Injectable()
export class DummyOtpSessionService {
  private readonly logger = new Logger(DummyOtpSessionService.name);

  constructor(
    private readonly firebase: FirebaseService,
    private readonly prisma: PrismaService,
  ) {}

  async start(params: {
    phone: string;
    email?: string;
  }): Promise<DummyOtpSessionResponseDto> {
    const phone = params.phone.trim();
    const email = params.email?.trim().toLowerCase() || undefined;

    if (!dummyAuthAllows(phone)) {
      // Deliberately the same answer for "the flags are off" and "this number
      // is not on the list": an unauthenticated caller learns only that it
      // cannot have a session, never which of the two it is.
      throw new ForbiddenException(
        'Dummy-OTP sign-in is not enabled for this number on this server.',
      );
    }

    // Each stage is timed separately. This endpoint makes two Admin SDK round
    // trips to Google and one or two database round trips, and when it feels
    // slow the only useful question is which of them was slow — a single
    // total cannot tell an Admin SDK stall from a cold Neon compute. Durations
    // and booleans only: no number, no uid-bearing token, no credentials.
    const startedAt = Date.now();
    const since = (from: number) => `${Date.now() - from}ms`;

    // 1. The Firebase account. Idempotent by phone, so a retry after any
    //    failure below resolves to the same uid instead of a second account.
    const firebaseAt = Date.now();
    const { uid, created } = await this.firebase.findOrCreateUser({ phone });
    const firebaseMs = since(firebaseAt);

    // 2. The internal row for it. A Firebase account whose `users` row failed
    //    to write is exactly the half-finished state this endpoint exists to
    //    prevent, so the failure surfaces rather than being swallowed — the
    //    client must not proceed believing signup succeeded. The Firebase user
    //    is left in place on purpose: it is what makes the retry idempotent.
    // Never for staff: a token minted here would sign the caller in as
    // whichever row the supplied phone or email resolves to. Refused before
    // any row is touched and before a token exists, with the same answer as
    // a number outside the policy, so the refusal reveals nothing.
    await this.refuseStaff({ uid, phone, email });
    await this.refuseClaimedEmail({ uid, phone, email });

    const dbAt = Date.now();
    let userId: string;
    try {
      userId = await this.reconcileUser({ uid, phone, email });
    } catch (error) {
      this.logger.error(
        `Firebase uid "${uid}" provisioned but the users row failed after ` +
          `${since(dbAt)}: ${(error as Error).message}`,
      );
      throw new InternalServerErrorException(
        'Could not create your account record. Please try again.',
      );
    }
    const dbMs = since(dbAt);

    // 3. The credential itself, minted last so a token is never handed out for
    //    an identity the database does not yet carry.
    const tokenAt = Date.now();
    const customToken = await this.firebase.createCustomToken(uid);
    const tokenMs = since(tokenAt);

    this.logger.log(
      `Dummy-OTP session issued for uid "${uid}" ` +
        `(firebase account ${created ? 'created' : 'reused'}, user ${userId}) ` +
        `— firebase ${firebaseMs}, db ${dbMs}, token ${tokenMs}, ` +
        `total ${since(startedAt)}.`,
    );

    return { customToken, uid, userId };
  }

  /**
   * Refuses when [uid] — or, failing that, the supplied email or phone —
   * belongs to a staff row. Dummy OTP verifies nothing, so it must never be a
   * way into an admin account, whether through the Firebase account it
   * resolved or through the `users` row `reconcileUser` would re-link.
   */
  private async refuseStaff(params: {
    uid: string;
    phone: string;
    email?: string;
  }): Promise<void> {
    const { uid, phone, email } = params;
    const lookups: Array<
      { firebaseUid: string } | { email: string } | { phone: string }
    > = [{ firebaseUid: uid }, ...(email ? [{ email }] : []), { phone }];
    for (const where of lookups) {
      const row = await this.prisma.user.findUnique({
        where,
        select: { id: true, role: true },
      });
      if (row && isStaffRole(row.role)) {
        this.logger.warn(
          `Refused a dummy-OTP session that resolves to staff user ${row.id}.`,
        );
        throw new ForbiddenException(
          'Dummy-OTP sign-in is not enabled for this number on this server.',
        );
      }
    }
  }

  /**
   * Refuses a signup whose email already belongs to a DIFFERENT account.
   *
   * The email is only ever something the caller typed — nothing in this flow
   * verifies it — so it may be stored on this person's own row but must never
   * select, or re-link, someone else's. Same row (same uid, or the row this
   * phone already owns) is fine. Checked before any row is touched and before
   * a token exists.
   */
  private async refuseClaimedEmail(params: {
    uid: string;
    phone: string;
    email?: string;
  }): Promise<void> {
    if (!params.email) return;
    const owner = await this.prisma.user.findUnique({
      where: { email: params.email },
      select: { id: true, firebaseUid: true, phone: true },
    });
    if (!owner) return;
    if (owner.firebaseUid === params.uid || owner.phone === params.phone)
      return;
    this.logger.warn(
      `Refused a dummy-OTP signup claiming the email of user ${owner.id}.`,
    );
    throw new ConflictException({
      statusCode: 409,
      error: 'Conflict',
      code: 'EMAIL_ALREADY_REGISTERED',
      message:
        'This email is already registered to another account. Sign in to that account, or use a different email.',
    });
  }

  /**
   * The internal `users` row for [uid], reusing whatever already represents
   * this person.
   *
   * The same reconciliation `FirebaseAuthGuard.resolveUser` performs, and for
   * the same reason: a Firebase account can be deleted and re-created while
   * `email`/`phone` remain this system's durable identity, so matching on uid
   * alone would try to insert a duplicate and crash on the unique constraint.
   * Done here as well as there because this endpoint runs *before* any guarded
   * request — it is the first thing a new member's identity touches, and the
   * guard must find the row already correct when the very next call arrives.
   */
  private async reconcileUser(params: {
    uid: string;
    phone: string;
    email?: string;
  }): Promise<string> {
    const { uid, phone, email } = params;

    const byUid = await this.prisma.user.findUnique({
      where: { firebaseUid: uid },
      select: { id: true },
    });
    if (byUid) {
      await this.prisma.user.update({
        where: { id: byUid.id },
        data: { phone, ...(email ? { email } : {}) },
      });
      return byUid.id;
    }

    // Re-link rather than duplicate: this person already has an account under
    // a previous uid (a re-created Firebase account, or one made by an earlier
    // sign-in path), and everything they own hangs off that internal id.
    // Found by PHONE only — the identifier this flow is about. Never by the
    // claimed email (refuseClaimedEmail has already refused one that belongs
    // to another account).
    const existing = await this.prisma.user.findUnique({
      where: { phone },
      select: { id: true },
    });

    if (existing) {
      this.logger.log(
        `Re-linking existing user ${existing.id} to Firebase uid "${uid}".`,
      );
      await this.prisma.user.update({
        where: { id: existing.id },
        data: { firebaseUid: uid, phone, ...(email ? { email } : {}) },
      });
      return existing.id;
    }

    // `User.email` is required and unique; a phone-only signup has no address,
    // so this mirrors the guard's placeholder rather than inventing a second
    // convention for the same gap.
    const user = await this.prisma.user.create({
      data: {
        firebaseUid: uid,
        phone,
        email: email ?? `${uid}@firebase.invalid`,
      },
      select: { id: true },
    });
    return user.id;
  }
}
