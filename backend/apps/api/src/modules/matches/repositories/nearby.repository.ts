import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Gender,
  Prisma,
} from '../../../../../../libs/database/generated/client';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import { feedProfileSelectFor, type FeedProfileRow } from './feed.repository';
import { boundingBoxFor, type GeoPoint } from '../geo/haversine';

/** The caller's own attributes Near Me needs: gender (to match the opposite)
 *  and their last stored coordinates (used when the request omits them). */
export interface NearbySelf {
  gender: Gender;
  latitude: number | null;
  longitude: number | null;
}

/** One geographic hit: who, and how far. No other columns — the display row
 *  is fetched separately, through the safety filters. */
export interface NearbyCandidate {
  userId: string;
  distanceKm: number;
}

/** Raw shape Postgres returns from the distance query. */
interface CandidateRow {
  user_id: string;
  distance_km: number;
}

/**
 * Ceiling on how many geographic candidates one request considers.
 *
 * The distance query is ordered nearest-first, so this is "the 400 closest
 * eligible people", not an arbitrary slice — anyone cut off is further away
 * than 400 others already returned, and the largest page this endpoint serves
 * is 50. It exists because the bounding box around a dense city could
 * otherwise match tens of thousands of rows, and every one of them would be
 * sorted and then re-fetched through Prisma.
 *
 * The trade-off is honest: if more than 400 people within the radius pass the
 * geographic filter but nearly all of them are blocked/declined (removed in
 * the second phase below), the last page can come back short. That needs ~400
 * blocks against one member to trigger, and the alternative — pushing the
 * block/interest joins into the raw SQL — would fork the safety rules away
 * from eligibility.builder.ts, which is the one place they are allowed to live.
 */
const MAX_CANDIDATES = 400;

/**
 * Proximity queries for Near Me.
 *
 * Runs in two phases on purpose:
 *
 *   1. [findCandidatesWithin] — raw SQL. Narrows by a bounding box the
 *      composite `(latitude, longitude)` index can range-scan, computes the
 *      true Haversine distance, drops the box's corners that fall outside the
 *      circle, and returns ids + distances nearest-first. Only the cheap,
 *      highly selective column filters (gender, profile completeness) ride
 *      along here, so the candidate set is already mostly correct.
 *
 *   2. [findVisibleProfiles] — Prisma. Re-fetches those ids through
 *      [buildEligibilityConditions], the SAME rules every Discover tier and
 *      Search use, so blocks, mutually-declined interests and suspended accounts are
 *      enforced by one implementation rather than a second copy transcribed
 *      into SQL. That duplication is the bug this split exists to avoid: a
 *      block rule fixed in one place and missed in the other means showing
 *      someone a person who blocked them.
 */
@Injectable()
export class NearbyRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Caller's gender + last stored coordinates. Null when they have not
   *  finalized a profile (no UserProfile row exists yet). */
  async findSelf(userId: string): Promise<NearbySelf | null> {
    const row = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: { gender: true, latitude: true, longitude: true },
    });
    return row ?? null;
  }

  /**
   * The nearest eligible profiles to [centre] within [radiusKm], nearest
   * first.
   *
   * The Haversine expression is computed once in a subquery and referenced by
   * alias in the outer WHERE/ORDER BY, rather than written out twice — writing
   * it twice is how the SELECT and the filter drift apart under later edits.
   *
   * Every value is interpolated through Prisma's tagged template, so each one
   * becomes a bound parameter ($1, $2, …) and never string-concatenated SQL.
   */
  async findCandidatesWithin(
    centre: GeoPoint,
    radiusKm: number,
    oppositeGender: Gender,
    currentUserId: string,
  ): Promise<NearbyCandidate[]> {
    const box = boundingBoxFor(centre, radiusKm);

    const rows = await this.prisma.$queryRaw<CandidateRow[]>`
      SELECT user_id, distance_km
      FROM (
        SELECT
          "user_id",
          -- Haversine, in kilometres, against the mean Earth radius. LEAST(1, …)
          -- guards ASIN's domain: floating-point rounding can push the operand a
          -- few ulps above 1 for near-antipodal pairs, which would return NULL.
          2 * 6371.0088 * ASIN(LEAST(1, SQRT(
            POWER(SIN(RADIANS("latitude" - ${centre.latitude}) / 2), 2)
            + COS(RADIANS(${centre.latitude}))
            * COS(RADIANS("latitude"))
            * POWER(SIN(RADIANS("longitude" - ${centre.longitude}) / 2), 2)
          ))) AS distance_km
        FROM "user_profiles"
        WHERE "latitude" IS NOT NULL
          AND "longitude" IS NOT NULL
          -- Bounding box first: this is the part an index can serve. Everything
          -- below it is arithmetic over the surviving rows.
          AND "latitude" BETWEEN ${box.minLatitude} AND ${box.maxLatitude}
          AND "longitude" BETWEEN ${box.minLongitude} AND ${box.maxLongitude}
          AND "user_id" <> ${currentUserId}
          AND "is_profile_complete" = true
          AND "gender" = ${oppositeGender}::"gender"
      ) AS candidates
      WHERE distance_km <= ${radiusKm}
      ORDER BY distance_km ASC
      LIMIT ${MAX_CANDIDATES}
    `;

    return rows.map((row) => ({
      userId: row.user_id,
      // Postgres DOUBLE PRECISION arrives as a JS number, but a driver-level
      // change to string (as happens with NUMERIC) would otherwise silently
      // produce NaN comparisons downstream.
      distanceKm: Number(row.distance_km),
    }));
  }

  /**
   * Display rows for [userIds], filtered through the shared eligibility rules.
   *
   * Returns FEED_PROFILE_SELECT — the same column set the Discover feed uses —
   * so ProfileFeedMapper can map these rows unchanged and Near Me cards are
   * field-for-field identical to feed cards.
   *
   * Ordering is NOT meaningful here: Postgres returns `IN (…)` matches in
   * whatever order it likes. The caller re-sorts by distance.
   */
  async findVisibleProfiles(
    userIds: string[],
    currentUserId: string,
    myGender: Gender,
  ): Promise<FeedProfileRow[]> {
    if (userIds.length === 0) return [];

    // The full shared eligibility, not just the parts the SQL above skipped:
    // re-asserting gender, completeness and self-exclusion costs nothing on a
    // set this small, and it means Near Me cannot drift from Discover.
    const where: Prisma.UserProfileWhereInput = {
      AND: [
        { userId: { in: userIds } },
        ...buildEligibilityConditions({ currentUserId, myGender }),
      ],
    };

    const rows = await this.prisma.userProfile.findMany({
      where,
      select: feedProfileSelectFor(currentUserId),
    });
    return rows;
  }
}
