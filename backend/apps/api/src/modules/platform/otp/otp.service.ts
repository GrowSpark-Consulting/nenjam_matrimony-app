import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { AppConfigService } from '@app/config';
import { PrismaService } from '@app/database';
import type { OtpPurpose } from '../../../../../../libs/database/generated/client';

export type { OtpPurpose };

export const OTP_POLICY = {
  /** How long a sent code stays valid. */
  codeTtlMs: 5 * 60_000,
  /** Verify calls per challenge, the right code included. */
  maxAttempts: 5,
  /** The shortest gap between two sends to one phone for one purpose. */
  resendAfterMs: 30_000,
  /** Sends to one phone for one purpose within [sendWindowMs]. */
  maxSendsPerWindow: 5,
  sendWindowMs: 60 * 60_000,
  /** Challenges expired longer than this are deleted, a batch per send. */
  purgeAfterMs: 24 * 60 * 60_000,
  purgeBatch: 100,
} as const;

const E164 = /^\+[1-9]\d{7,14}$/;

export interface OtpChallengeIssued {
  challengeId: string;
  expiresAt: Date;
}

export type OtpVerifyFailure =
  | 'NOT_FOUND'
  | 'EXPIRED'
  | 'ALREADY_USED'
  | 'INVALID_CODE'
  | 'TOO_MANY_ATTEMPTS';

export type OtpVerifyResult =
  { ok: true; phoneE164: string } | { ok: false; reason: OtpVerifyFailure };

/** `send` asked too often for this phone and purpose. */
export class OtpRateLimitError extends Error {
  constructor(public readonly retryAfterSeconds: number) {
    super(`Too many codes requested. Retry in ${retryAfterSeconds}s.`);
    this.name = 'OtpRateLimitError';
  }
}

/** No way to deliver a code to this phone: there is no SMS provider yet, and
 *  the phone is not covered by the dummy mode. Answers 503. */
export class OtpDeliveryUnavailableError extends ServiceUnavailableException {
  constructor() {
    super({
      statusCode: 503,
      error: 'Service Unavailable',
      code: 'OTP_DELIVERY_UNAVAILABLE',
      message: 'Sign-in codes cannot be sent to this number yet.',
    });
  }
}

/**
 * One-time codes for phone sign-in outside Firebase (agents first).
 *
 *  - Bound to a purpose: a challenge never verifies for another purpose — it
 *    answers NOT_FOUND, so nothing about it leaks.
 *  - Verifies once; every verify call uses up an attempt (claimed before the
 *    code is compared, so parallel guesses cannot exceed the limit); after
 *    the limit, or once expired, even the right code fails.
 *  - Codes are stored hashed and compared in constant time; neither a code
 *    nor a phone is ever logged.
 *  - `send` is limited per phone and purpose (OTP_POLICY), exactly: sends for
 *    one phone and purpose are serialised by a transaction lock.
 *
 * Delivery: no SMS provider exists yet, so the only code that can be issued
 * is the dummy one (AGENT_OTP_DUMMY_*), for allow-listed phones — any phone
 * outside production when the list is empty, none in production. Everything
 * else is refused with OtpDeliveryUnavailableError. A real sender will make a
 * random code here and send it.
 */
@Injectable()
export class OtpService {
  private readonly logger = new Logger(OtpService.name);
  private readonly dummy: {
    code: string;
    phones: ReadonlySet<string> | 'ANY';
  } | null;

  constructor(
    private readonly prisma: PrismaService,
    config: AppConfigService,
  ) {
    const { dummyEnabled, dummyPhones, dummyCode } = config.agentOtp;
    if (!dummyEnabled || !dummyCode) {
      this.dummy = null;
    } else if (dummyPhones.length > 0) {
      this.dummy = { code: dummyCode, phones: new Set(dummyPhones) };
    } else if (config.isProduction) {
      this.dummy = null;
      this.logger.warn(
        'AGENT_OTP_DUMMY_ENABLED is on with no AGENT_OTP_DUMMY_PHONES: in production that covers no phone.',
      );
    } else {
      this.dummy = { code: dummyCode, phones: 'ANY' };
    }
    if (this.dummy) {
      this.logger.warn(
        this.dummy.phones === 'ANY'
          ? 'Dummy sign-in codes are ON for every phone (not production). Nothing is sent.'
          : `Dummy sign-in codes are ON for ${this.dummy.phones.size} allow-listed phone(s). Nothing is sent.`,
      );
    }
  }

  /** Issues a challenge for [phoneE164]. Rejects with OtpRateLimitError when
   *  asked too often, or OtpDeliveryUnavailableError when no code can reach
   *  the phone. */
  async send(
    purpose: OtpPurpose,
    phoneE164: string,
    now: Date = new Date(),
  ): Promise<OtpChallengeIssued> {
    if (typeof phoneE164 !== 'string' || !E164.test(phoneE164)) {
      throw new RangeError('phoneE164 must be an E.164 number.');
    }
    const code = this.codeFor(phoneE164);
    const issued = await this.prisma.$transaction(async (tx) => {
      const lockKey = `otp-send:${purpose}:${phoneE164}`;
      await tx.$queryRaw`SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))) AS locked`;
      const recent = await tx.otpChallenge.findMany({
        where: {
          purpose,
          phoneE164,
          createdAt: { gt: new Date(now.getTime() - OTP_POLICY.sendWindowMs) },
        },
        select: { createdAt: true },
        orderBy: { createdAt: 'asc' },
      });
      const waitMs = sendRetryAfterMs(
        recent.map((r) => r.createdAt),
        now,
      );
      if (waitMs > 0) throw new OtpRateLimitError(Math.ceil(waitMs / 1000));
      const id = randomUUID();
      return tx.otpChallenge.create({
        data: {
          id,
          purpose,
          phoneE164,
          codeHash: hashCode(id, code),
          createdAt: now,
          expiresAt: new Date(now.getTime() + OTP_POLICY.codeTtlMs),
        },
        select: { id: true, expiresAt: true },
      });
    });
    await this.purgeExpired(now);
    return { challengeId: issued.id, expiresAt: issued.expiresAt };
  }

  /** The verified phone, or why not. Never throws for a wrong or unknown
   *  challenge or code. */
  async verify(
    purpose: OtpPurpose,
    challengeId: string,
    code: string,
    now: Date = new Date(),
  ): Promise<OtpVerifyResult> {
    if (typeof challengeId !== 'string' || !/^[\w-]{1,64}$/.test(challengeId)) {
      return { ok: false, reason: 'NOT_FOUND' };
    }
    // Use up an attempt before comparing anything.
    const claimed = await this.prisma.otpChallenge.updateMany({
      where: {
        id: challengeId,
        purpose,
        consumedAt: null,
        attempts: { lt: OTP_POLICY.maxAttempts },
        expiresAt: { gt: now },
      },
      data: { attempts: { increment: 1 } },
    });
    const row = await this.prisma.otpChallenge.findUnique({
      where: { id: challengeId },
    });
    if (!row || row.purpose !== purpose) {
      return { ok: false, reason: 'NOT_FOUND' };
    }
    if (claimed.count === 0) {
      return {
        ok: false,
        reason: row.consumedAt
          ? 'ALREADY_USED'
          : row.attempts >= OTP_POLICY.maxAttempts
            ? 'TOO_MANY_ATTEMPTS'
            : 'EXPIRED',
      };
    }
    if (!codeMatches(row.codeHash, challengeId, code)) {
      return { ok: false, reason: 'INVALID_CODE' };
    }
    const consumed = await this.prisma.otpChallenge.updateMany({
      where: { id: challengeId, consumedAt: null },
      data: { consumedAt: now },
    });
    return consumed.count === 1
      ? { ok: true, phoneE164: row.phoneE164 }
      : { ok: false, reason: 'ALREADY_USED' };
  }

  private codeFor(phoneE164: string): string {
    if (
      this.dummy &&
      (this.dummy.phones === 'ANY' || this.dummy.phones.has(phoneE164))
    ) {
      return this.dummy.code;
    }
    throw new OtpDeliveryUnavailableError();
  }

  /** A small batch per send, so the table never grows without a scheduler.
   *  Best effort: a failed purge never fails the send. */
  private async purgeExpired(now: Date): Promise<void> {
    try {
      const stale = await this.prisma.otpChallenge.findMany({
        where: {
          expiresAt: { lt: new Date(now.getTime() - OTP_POLICY.purgeAfterMs) },
        },
        select: { id: true },
        take: OTP_POLICY.purgeBatch,
      });
      if (stale.length > 0) {
        await this.prisma.otpChallenge.deleteMany({
          where: { id: { in: stale.map((s) => s.id) } },
        });
      }
    } catch (error) {
      this.logger.warn(
        `Could not purge expired sign-in codes: ${(error as Error).message}`,
      );
    }
  }
}

/** How long until another send is allowed, given the earlier sends inside
 *  the window (oldest first); 0 when it is allowed now. */
export function sendRetryAfterMs(sentAt: readonly Date[], now: Date): number {
  if (sentAt.length === 0) return 0;
  const waits = [
    sentAt[sentAt.length - 1].getTime() +
      OTP_POLICY.resendAfterMs -
      now.getTime(),
  ];
  if (sentAt.length >= OTP_POLICY.maxSendsPerWindow) {
    const oldestCounted = sentAt[sentAt.length - OTP_POLICY.maxSendsPerWindow];
    waits.push(
      oldestCounted.getTime() + OTP_POLICY.sendWindowMs - now.getTime(),
    );
  }
  return Math.max(0, ...waits);
}

/** Salted with the challenge id, so equal codes never share a hash. */
function hashCode(challengeId: string, code: string): string {
  return createHash('sha256')
    .update(`otp:v1:${challengeId}:${code}`, 'utf8')
    .digest('hex');
}

function codeMatches(
  storedHash: string,
  challengeId: string,
  code: string,
): boolean {
  const given = Buffer.from(
    hashCode(challengeId, typeof code === 'string' ? code : ''),
    'hex',
  );
  const stored = Buffer.from(storedHash, 'hex');
  return stored.length === given.length && timingSafeEqual(stored, given);
}
