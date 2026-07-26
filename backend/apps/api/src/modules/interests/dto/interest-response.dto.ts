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
