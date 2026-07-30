import type { DiscoverProfileDto } from '../../matches/dto/discover-profile.response.dto';
import { DISCOVER_PROFILE_EXAMPLE } from '../../interests/dto/interest-response.dto';

/** One row of `GET /users/blocked` — the blocked member's public profile
 *  card (the exact Discover card shape) plus when the caller blocked them. */
export interface BlockedUserItemDto {
  id: string;
  blockedAt: string;
  profile: DiscoverProfileDto;
}

/** Paginated envelope for `GET /users/blocked` — `hasMore` drives the
 *  client's infinite scroll without it tracking totals itself. */
export interface BlockedUsersPageDto {
  items: BlockedUserItemDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

// ── Swagger examples ──────────────────────────────────────────────────────
// DISCOVER_PROFILE_EXAMPLE is a compact (partial-field) example object, not
// a full DiscoverProfileDto — matching how it's already reused as-is for
// InterestListItemDto's own example (interests/dto/interest-response.dto.ts),
// so these stay untyped literals too rather than forcing a cast.

export const BLOCKED_USER_ITEM_EXAMPLE = {
  id: DISCOVER_PROFILE_EXAMPLE.id,
  blockedAt: '2026-07-20T10:15:00.000Z',
  profile: DISCOVER_PROFILE_EXAMPLE,
};

export const BLOCKED_USERS_PAGE_EXAMPLE = {
  items: [BLOCKED_USER_ITEM_EXAMPLE],
  page: 1,
  limit: 20,
  total: 1,
  hasMore: false,
};
