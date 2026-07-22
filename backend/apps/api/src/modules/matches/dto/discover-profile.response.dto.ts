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
}

// Paginated envelope. `hasMore` lets the client drive infinite scroll without
// tracking totals itself.
export interface DiscoverFeedResponseDto {
  items: DiscoverProfileDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}
