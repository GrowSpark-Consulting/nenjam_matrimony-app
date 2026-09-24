import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService, hiddenFromDiscoveryWhere } from '@app/database';
import { MailService } from '@app/mail';

/** How far back "new this week" reaches. */
const DIGEST_WINDOW_DAYS = 7;
/** Profiles shown in the email body. The CTA covers the rest. */
const MATCHES_PER_DIGEST = 3;
/** Users loaded per pass — bounds memory and the per-user query fan-out. */
const USER_BATCH_SIZE = 200;

/**
 * Weekly "new matches for you" digest.
 *
 * Deliberately simple matching: opposite gender, inside the member's stated
 * age range, profile finalized, joined within the window. It does NOT reuse
 * ProgressiveFallbackStrategy — that lives in apps/api and is not importable
 * from the scheduler without extracting it to a shared lib. A digest is a
 * "here's what's new" nudge rather than a ranked feed, so the simpler query is
 * honest about what it is; if this ever needs real ranking, extract the
 * strategy to libs/ rather than duplicating it here.
 *
 * Sends nothing when a member has no new candidates — an empty digest is worse
 * than no digest.
 */
@Injectable()
export class WeeklyDigestCron {
  private readonly logger = new Logger(WeeklyDigestCron.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly mail: MailService,
  ) {}

  // Sunday 09:00 server time — high-intent browsing window, and far from the
  // weekday transactional peak so a large fan-out cannot delay an OTP.
  // (Priority would protect the OTP anyway; this just avoids the contention.)
  @Cron(CronExpression.EVERY_WEEK)
  async run(): Promise<void> {
    const startedAt = Date.now();
    const since = new Date(Date.now() - DIGEST_WINDOW_DAYS * 24 * 3600 * 1000);
    const week = isoWeekKey(new Date());

    let cursor: string | undefined;
    let queued = 0;
    let skipped = 0;

    try {
      for (;;) {
        const users = await this.prisma.user.findMany({
          where: {
            deletedAt: null,
            status: { notIn: ['BANNED', 'DEACTIVATED', 'SUSPENDED'] },
            profile: { isProfileComplete: true },
          },
          select: {
            id: true,
            email: true,
            profile: { select: { firstName: true, gender: true } },
            partnerPreference: { select: { minAge: true, maxAge: true } },
          },
          orderBy: { id: 'asc' },
          take: USER_BATCH_SIZE,
          ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
        });

        if (users.length === 0) break;
        cursor = users[users.length - 1].id;

        for (const user of users) {
          if (!user.email || !user.profile) {
            skipped++;
            continue;
          }

          const matches = await this.findNewCandidates(user, since);
          if (matches.length === 0) {
            skipped++;
            continue;
          }

          await this.mail.sendWeeklyDigest(
            user.email,
            {
              firstName: user.profile.firstName,
              matchCount: matches.length,
              matches,
              userId: user.id,
            },
            // Deterministic job id: a redeploy, a manual re-run or an overlapping
            // tick cannot mail the same person twice in the same ISO week.
            { dedupeKey: `digest:${user.id}:${week}` },
          );
          queued++;
        }

        if (users.length < USER_BATCH_SIZE) break;
      }

      this.logger.log(
        `Weekly digest ${week}: queued ${queued}, skipped ${skipped} (no email/profile/candidates) in ${Date.now() - startedAt}ms.`,
      );
    } catch (error) {
      // A cron that throws takes the scheduler process down on some runtimes
      // and, worse, silently stops future ticks. Partial progress is kept:
      // already-queued digests stand, and the dedupe key makes a re-run safe.
      this.logger.error(
        `Weekly digest aborted after queuing ${queued}: ${(error as Error).message}`,
      );
    }
  }

  /** Opposite-gender, age-appropriate profiles finalized inside the window. */
  private async findNewCandidates(
    user: {
      id: string;
      profile: { gender: string } | null;
      partnerPreference: {
        minAge: number | null;
        maxAge: number | null;
      } | null;
    },
    since: Date,
  ) {
    const minAge = user.partnerPreference?.minAge ?? 18;
    const maxAge = user.partnerPreference?.maxAge ?? 70;
    // Age range -> DOB range. Inverted: the OLDEST acceptable partner has the
    // EARLIEST birth date.
    const now = new Date();
    const dobFrom = new Date(
      now.getFullYear() - maxAge - 1,
      now.getMonth(),
      now.getDate(),
    );
    const dobTo = new Date(
      now.getFullYear() - minAge,
      now.getMonth(),
      now.getDate(),
    );

    const rows = await this.prisma.userProfile.findMany({
      where: {
        isProfileComplete: true,
        createdAt: { gte: since },
        gender: user.profile?.gender === 'MALE' ? 'FEMALE' : 'MALE',
        dob: { gte: dobFrom, lte: dobTo },
        userId: { not: user.id },
        user: {
          deletedAt: null,
          status: { notIn: ['BANNED', 'DEACTIVATED', 'SUSPENDED'] },
          // Never surface someone either party has blocked, in either
          // direction. blocksMade = blocks this candidate created;
          // blocksReceived = blocks created against them.
          blocksMade: { none: { blockedUserId: user.id } },
          blocksReceived: { none: { blockerId: user.id } },
          // A digest is a discovery surface: never mail out a member who
          // chose "Hide My Profile" (same rule as Discover/Search/Near Me).
          NOT: hiddenFromDiscoveryWhere(now),
        },
      },
      select: {
        userId: true,
        firstName: true,
        dob: true,
        currentCity: true,
      },
      orderBy: { createdAt: 'desc' },
      take: MATCHES_PER_DIGEST,
    });

    return rows.map((row) => ({
      name: row.firstName,
      age: ageFrom(row.dob),
      city: row.currentCity,
      profileUrl: `/profile/${row.userId}`,
    }));
  }
}

/** `2026-W31` — stable within a calendar week, so it is a safe dedupe key. */
export function isoWeekKey(date: Date): string {
  const d = new Date(
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()),
  );
  // ISO weeks run Monday-Sunday and belong to the year containing their Thursday.
  const dayNumber = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNumber);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(
    ((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7,
  );
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

export function ageFrom(dob: Date): number {
  const now = new Date();
  let age = now.getFullYear() - dob.getFullYear();
  const monthDelta = now.getMonth() - dob.getMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getDate() < dob.getDate())) {
    age--;
  }
  return age;
}
