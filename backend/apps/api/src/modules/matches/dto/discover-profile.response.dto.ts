// Compatibility scores. Phase 1 leaves every score at 0 (no matching engine
// yet); Phase 2's RecommendationService fills these in. Shape mirrors the
// Flutter CompatibilityEntity so the wire contract is stable across phases.
export interface CompatibilityDto {
  aiMatchPercent: number;
  astroMatchPercent: number;
  psychologyMatchPercent: number;
  overallCompatibility: number;
}

// One card in the Discover feed. Field-for-field the shape Flutter's
// DiscoveryProfileModel.fromJson expects — only public, display-safe data.
// No email / phone number / firebaseUid / tokens are ever included.
export interface DiscoverProfileDto {
  id: string;
  matrimonyId: string;
  name: string;
  age: number;
  location: string;
  profession: string;
  education: string;
  photoUrls: string[];
  isVerified: boolean;
  isPremium: boolean;
  isPsychologyCompleted: boolean;
  isOnline: boolean;
  horoscopeAvailable: boolean;
  photoProtected: boolean;
  phoneVerified: boolean;
  compatibility: CompatibilityDto;
  tags: string[];
  religion: string;
  caste: string;
  community: string;
  height: string;
  diet: string;
  distanceKm: number | null;
  gender: string;
  // Additional public profile fields the card/tags render. Empty string / []
  // when the (optional) source field wasn't filled — the client just omits the
  // corresponding chip. All display-safe; no contact/identity data.
  maritalStatus: string;
  motherTongue: string;
  smoking: string;
  drinking: string;
  physicalStatus: string;
  company: string;
  annualIncome: string;
  bio: string;
  languages: string[];
  hobbies: string[];
  // Full-profile completeness (UserProfile.profileCompletePct >= 100) —
  // distinct from Discover eligibility, which only requires the mandatory
  // Steps 1-4 (see UserProfile.isProfileComplete / buildFeedWhere). A caller
  // can be feed-eligible with profileComplete: false; the client shows a
  // "Building profile" badge in that case.
  profileComplete: boolean;
}

// Paginated envelope. `hasMore` lets the client drive infinite scroll without
// tracking totals itself.
export interface DiscoverFeedResponseDto {
  items: DiscoverProfileDto[];
  page: number;
  limit: number;
  /**
   * Total matching profiles — SEARCH ONLY, and absent from `/discover`.
   *
   * Search shows a result count, and its query returns one anyway. Discover
   * never displayed it: the Flutter client parses `items`, `page`, `hasMore`
   * and `nextCursor` and nothing else. Producing it there cost a COUNT over
   * the whole matching set on every feed request, so the feed no longer sends
   * it and derives `hasMore` from the rows instead.
   */
  total?: number;
  hasMore: boolean;
  /** Opaque cursor for the next page, or null at the end. Additive: clients
   *  still using `page`/`limit` can ignore it entirely. */
  nextCursor?: string | null;
  /** Monotonic feed version for this member. Bumped whenever their profile,
   *  preferences or blocks change. A client holding an older value knows its
   *  cached feed — and any cursor from it — is stale. 0 when Redis is
   *  unavailable, which is a stable value rather than a changing one, so it
   *  never triggers a refetch loop. */
  version?: number;
  // ProgressiveFallbackStrategy metadata. `tier` 1 = exact match on the
  // caller's saved preferences; higher tiers mean the search was
  // progressively widened (see tier-plan.ts). `fallbackUsed` is the single
  // flag Flutter needs to decide whether to show the "widened your
  // preferences" banner.
  tier: number;
  fallbackUsed: boolean;
  reason: string;
  relaxedFilters: string[];
}
