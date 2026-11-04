/**
 * `AgentMemberReadPort` over the member tables (read only: agent code never
 * writes member data).
 *
 * - The member's verified phone is `users.phone`: it is only ever written from
 *   a verified source (the Firebase ID token's `phone_number`, or the dummy-OTP
 *   session while testing). No phone means no verified phone, so no credit is
 *   possible (`phoneHash: null`).
 * - The phone hash is made with the NEWEST pepper (`hash`), the same as
 *   attributions store it.
 * - "Has paid" is any payment that ever succeeded (`paid_at` set), including
 *   one refunded later: the first paid plan was still bought.
 * - A deleted member (`deleted_at` set) is gone.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentMemberReadPort,
  AgentMemberSnapshot,
} from '../../ports/agent-data-ports';
import type { AgentClock } from '../../ports/agent-infra-ports';
import type { AgentIdentifierHasher } from '../../ports/agent-platform-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import type {
  ReferralStage,
  ReferralViewSource,
} from '../../referral/agent-referral-view';
import { dbFor } from './prisma-agent-tx';

type ViewFields = Omit<
  ReferralViewSource,
  'attributionId' | 'commissionStatus'
>;

const IST_OFFSET_MS = 330 * 60_000;

/** Whole years from a birth date (stored as UTC midnight of the day it names)
 *  to today's calendar date in India. */
export function ageOnIstDate(dob: Date, now: Date): number {
  const today = new Date(now.getTime() + IST_OFFSET_MS);
  let age = today.getUTCFullYear() - dob.getUTCFullYear();
  const beforeBirthday =
    today.getUTCMonth() < dob.getUTCMonth() ||
    (today.getUTCMonth() === dob.getUTCMonth() &&
      today.getUTCDate() < dob.getUTCDate());
  if (beforeBirthday) age -= 1;
  return Math.max(0, age);
}

export class PrismaAgentMemberRead implements AgentMemberReadPort {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly hasher: AgentIdentifierHasher,
    private readonly clock: AgentClock,
  ) {}

  async getMember(
    memberId: string,
    tx?: AgentTx,
  ): Promise<AgentMemberSnapshot | null> {
    const db = dbFor(this.prisma, tx);
    const user = await db.user.findFirst({
      where: { id: memberId, deletedAt: null },
      select: { id: true, phone: true, createdAt: true },
    });
    if (!user) return null;
    const paid = await db.paymentTransaction.findFirst({
      where: { userId: user.id, paidAt: { not: null } },
      select: { id: true },
    });
    return {
      memberId: user.id,
      phoneHash: user.phone ? this.hasher.hash('PHONE', user.phone) : null,
      signedUpAt: user.createdAt,
      hasPaid: paid !== null,
    };
  }

  async getReferralViewFields(
    memberId: string,
    tx?: AgentTx,
  ): Promise<ViewFields | null> {
    const db = dbFor(this.prisma, tx);
    const user = await db.user.findFirst({
      where: { id: memberId, deletedAt: null },
      select: {
        phone: true,
        createdAt: true,
        profile: {
          select: {
            firstName: true,
            lastName: true,
            dob: true,
            currentCity: true,
            isProfileComplete: true,
            profileCompletePct: true,
          },
        },
      },
    });
    // No phone or no profile yet: nothing the agent may be shown.
    if (!user?.phone || !user.profile) return null;
    const firstPaid = await db.paymentTransaction.findFirst({
      where: { userId: memberId, paidAt: { not: null } },
      orderBy: { paidAt: 'asc' },
      select: {
        paidAt: true,
        subscription: { select: { plan: { select: { displayName: true } } } },
      },
    });
    const profile = user.profile;
    const stage: ReferralStage = firstPaid
      ? 'PURCHASED'
      : profile.isProfileComplete
        ? 'PROFILE_COMPLETE'
        : 'REGISTERED';
    return {
      firstName: profile.firstName,
      lastName: profile.lastName,
      phoneE164: user.phone,
      age: ageOnIstDate(profile.dob, this.clock.now()),
      city: profile.currentCity,
      signedUpAt: user.createdAt,
      stage,
      profileCompletenessPct: profile.profileCompletePct,
      planName: firstPaid?.subscription.plan.displayName ?? null,
      purchasedAt: firstPaid?.paidAt ?? null,
    };
  }
}
