import type { InterestStatus } from '../../../../../../libs/database/generated/client';
import type { DiscoverProfileDto } from '../../matches/dto/discover-profile.response.dto';

/** Lowercase wire values matching Flutter's `InterestStatus` enum names
 *  exactly (`pending`/`accepted`/`declined`). */
export type InterestStatusWire = 'pending' | 'accepted' | 'declined';

const STATUS_TO_WIRE: Record<InterestStatus, InterestStatusWire> = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  DECLINED: 'declined',
};

export function interestStatusToWire(
  status: InterestStatus,
): InterestStatusWire {
  return STATUS_TO_WIRE[status];
}

/**
 * `POST /matches/interest` (send) response — the created record's identity and
 * status. The client already holds the profile it sent to, so only these three
 * fields come back (see InterestsRepositoryImpl.sendInterest).
 */
export interface SendInterestResponseDto {
  id: string;
  sentAt: string;
  status: InterestStatusWire;
}

/** One row of `GET /interests/received` | `GET /interests/sent` — the interest
 *  plus the *counterpart's* public profile card (sender for received, receiver
 *  for sent). */
export interface InterestListItemDto {
  id: string;
  sentAt: string;
  status: InterestStatusWire;
  profile: DiscoverProfileDto;
}

// ── Swagger examples ──────────────────────────────────────────────────────

/** Compact example of a DiscoverProfileDto for docs (the full card has more
 *  fields — see DiscoverProfileDto). */
export const DISCOVER_PROFILE_EXAMPLE = {
  id: '5f2b1c8e-1a2b-4c3d-9e8f-0a1b2c3d4e5f',
  name: 'Priya R',
  age: 27,
  location: 'Chennai, Tamil Nadu',
  profession: 'Software Engineer',
  photoUrls: ['https://…/signed-photo.jpg'],
  religion: 'Hindu',
  gender: 'female',
};

export const SEND_INTEREST_RESPONSE_EXAMPLE: SendInterestResponseDto = {
  id: '9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
  sentAt: '2026-07-25T10:15:00.000Z',
  status: 'pending',
};

export const INTEREST_LIST_ITEM_EXAMPLE = {
  ...SEND_INTEREST_RESPONSE_EXAMPLE,
  profile: DISCOVER_PROFILE_EXAMPLE,
};
