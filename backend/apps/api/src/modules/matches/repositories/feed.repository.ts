import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  Prisma,
  Gender,
} from '../../../../../../libs/database/generated/client';

// The exact columns ProfileFeedMapper reads — nothing more. An explicit
// `select` (vs. a bare `include`, which hydrates all ~48 UserProfile columns)
// keeps each feed/search row to the ~25 fields the card actually uses, so the
// query returns a narrower payload from Postgres and Prisma hydrates less per
// page. Centralised so the feed query, the search query, and the mapper all
// agree on one row shape — update this set whenever the mapper reads a new
// column, or that column silently comes back undefined.
export const FEED_PROFILE_SELECT = {
  userId: true,
  firstName: true,
  lastName: true,
  dob: true,
  gender: true,
  maritalStatus: true,
  religion: true,
  caste: true,
  community: true,
  motherTongue: true,
  languagesKnown: true,
  heightCm: true,
  physicalStatus: true,
  annualIncomeLakhs: true,
  highestEducation: true,
  profession: true,
  employerName: true,
  currentCity: true,
  currentState: true,
  bio: true,
  dietaryHabits: true,
  smokingHabits: true,
  drinkingHabits: true,
  hobbies: true,
  profileCompletePct: true,
  // Scoring inputs. `updatedAt` stands in for activity (there is no
  // lastActiveAt column — see ACTIVITY_NOTE in matching-weights.config.ts).
  updatedAt: true,
  // Deterministic tie-break for ranking. Two candidates on the same score must
  // order identically on every request, or one can appear on both page 1 and
  // page 2 while another is skipped entirely.
  createdAt: true,
  user: {
    select: {
      phone: true,
      // Trust signal for the verification component.
      trustScore: true,
      // The candidate's OWN preference, for the mutual direction of the score.
      // Selected here rather than fetched per row on purpose: this is a nested
      // select on a query that already runs, so mutual scoring costs zero extra
      // round trips. Fetching it per candidate would be a textbook N+1 — 20
      // profiles becoming 21 queries.
      partnerPreference: {
        select: {
          minAge: true,
          maxAge: true,
          minHeightCm: true,
          maxHeightCm: true,
          preferredReligions: true,
          preferredCastes: true,
          preferredMotherTongues: true,
          preferredEducation: true,
          preferredOccupations: true,
          preferredCities: true,
          preferredStates: true,
          maritalStatusPref: true,
          minIncomeLakhs: true,
          extendedPreferences: true,
        },
      },
      photos: {
        orderBy: [{ isPrimary: 'desc' }, { order: 'asc' }],
        select: { s3Key: true },
      },
    },
  },
} satisfies Prisma.UserProfileSelect;

// A finalized profile row plus the joined user/photos the card needs.
export type FeedProfileRow = Record<string, unknown>;

// The caller's own attributes the feed needs: gender for opposite-gender
// matching, and caste/city/state/tongue to resolve relative "Same X" prefs.
export interface SelfProfile {
  gender: Gender;
  caste: string;
  currentCity: string;
  currentState: string;
  motherTongue: string;
  // ── scoring inputs ───────────────────────────────────────────────────────
  // The mutual half of the compatibility score runs the CANDIDATE's saved
  // preference against the SEEKER, so the seeker's own attributes are needed
  // too — not just the four "Same X" fields the WHERE builder resolves.
  //
  // These are added to a query that already runs once per feed request, so
  // mutual scoring costs no extra round trip. That matters here: a round trip
  // to this database measures ~250ms inside the feed's WHERE, and the feed
  // already spends ~1s in its query stage.
  userId: string;
  dob: Date | null;
  heightCm: number | null;
  religion: string | null;
  community: string | null;
  highestEducation: string | null;
  profession: string | null;
  maritalStatus: string | null;
  dietaryHabits: string | null;
  smokingHabits: string | null;
  drinkingHabits: string | null;
  profileCompletePct: number | null;
  updatedAt: Date | null;
}

@Injectable()
export class FeedRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** The caller's own matchable attributes: gender (for opposite-gender
   *  matching) plus the fields a relative "Same X" preference resolves against
   *  (caste / city / state / mother tongue). Null if they haven't finalized a
   *  profile yet. */
  async findSelf(userId: string): Promise<SelfProfile | null> {
    const row = await this.prisma.userProfile.findUnique({
      where: { userId },
      select: {
        gender: true,
        caste: true,
        currentCity: true,
        currentState: true,
        motherTongue: true,
        userId: true,
        dob: true,
        heightCm: true,
        religion: true,
        community: true,
        highestEducation: true,
        profession: true,
        maritalStatus: true,
        dietaryHabits: true,
        smokingHabits: true,
        drinkingHabits: true,
        profileCompletePct: true,
        updatedAt: true,
      },
    });
    return row ?? null;
  }

  /**
   * Runs the (already-built) dynamic WHERE against user_profiles, newest
   * first, paginated. Count + page share the same WHERE.
   *
   * Concurrent, not `$transaction([...])`: at READ COMMITTED (this database's
   * default) each statement takes its own snapshot, so wrapping the two in a
   * transaction never actually made `total` consistent with the page — it only
   * added a sequential BEGIN before and COMMIT after. Measured at 307ms in a
   * transaction vs 74ms concurrently against this database.
   */
  async findMatching(
    where: Prisma.UserProfileWhereInput,
    { skip, take }: { skip: number; take: number },
  ): Promise<{ rows: FeedProfileRow[]; total: number }> {
    const [rows, total] = await Promise.all([
      this.prisma.userProfile.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take,
        select: FEED_PROFILE_SELECT,
      }),
      this.prisma.userProfile.count({ where }),
    ]);
    return { rows: rows as FeedProfileRow[], total };
  }

  /**
   * Cheap existence/count probe — no `include`, no row fetch. Used by
   * ProgressiveFallbackStrategy to test each fallback tier's WHERE before
   * paying for the full row fetch, so only the winning tier ever runs
   * [findRows].
   */
  countMatching(where: Prisma.UserProfileWhereInput): Promise<number> {
    return this.prisma.userProfile.count({ where });
  }

  /** The paginated rows for an already-confirmed-non-empty WHERE — same shape
   *  and ordering as [findMatching], split out so the caller can reuse a count
   *  it already has instead of paying for it twice. */
  async findRows(
    where: Prisma.UserProfileWhereInput,
    { skip, take }: { skip: number; take: number },
  ): Promise<FeedProfileRow[]> {
    const rows = await this.prisma.userProfile.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip,
      take,
      select: FEED_PROFILE_SELECT,
    });
    return rows as FeedProfileRow[];
  }
}
