import { activePremiumSubscriptionWhere } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';

/**
 * Photo privacy — "Hide Photos from Non-Connections" — in one place, shared by
 * every surface that signs another member's photo (profile cards via
 * ProfileFeedMapper, notification actor avatars).
 *
 * Rule: a member's photos are withheld from a viewer only when ALL hold:
 *  1. the member switched `hidePhotosFromNonConnections` on;
 *  2. the member has an active premium subscription — photo privacy is a
 *     premium feature, so for everyone else the flag is ignored;
 *  3. the viewer is not a connection. A connection is an accepted interest in
 *     either direction, the app's own definition of a match.
 */

/**
 * The per-viewer probes [arePhotosHidden] reads, as a `User` select fragment.
 * Every probe is a `take: 1` nested select on a query that already runs, so a
 * page of 20 cards stays one query — never 20 connection or subscription
 * lookups.
 */
export function photoPrivacySelectFor(viewerId: string, now: Date) {
  return {
    hidePhotosFromNonConnections: true,
    // Any active premium subscription of the member's own.
    subscriptions: {
      where: activePremiumSubscriptionWhere(now),
      select: { id: true },
      take: 1,
    },
    // They accepted an interest I sent.
    receivedInterests: {
      where: { senderId: viewerId, status: 'ACCEPTED' as const },
      select: { id: true },
      take: 1,
    },
    // I accepted an interest they sent.
    sentInterests: {
      where: { receiverId: viewerId, status: 'ACCEPTED' as const },
      select: { id: true },
      take: 1,
    },
  } satisfies Prisma.UserSelect;
}

/** The fields [photoPrivacySelectFor] returns; all optional because a row
 *  selected without the probes must still be handled (see below). */
export interface PhotoPrivacyProbes {
  hidePhotosFromNonConnections?: boolean;
  subscriptions?: Array<{ id: string }>;
  receivedInterests?: Array<{ id: string }>;
  sentInterests?: Array<{ id: string }>;
}

/**
 * Whether this member's photos must be withheld from the viewer the probes
 * were selected for.
 *
 * Fails CLOSED: when the flag is on but a probe is missing — a row fetched
 * without [photoPrivacySelectFor] — the member is assumed premium and the
 * viewer unconnected, so a caller that forgets the viewer-aware select hides
 * photos rather than leaking them. The flag itself is always selected, so a
 * member who never turned it on is never affected by a missing probe.
 */
export function arePhotosHidden(user: PhotoPrivacyProbes): boolean {
  if (user.hidePhotosFromNonConnections !== true) return false;

  const ownerIsPremium =
    user.subscriptions === undefined || user.subscriptions.length > 0;
  if (!ownerIsPremium) return false;

  const connected =
    (user.receivedInterests?.length ?? 0) > 0 ||
    (user.sentInterests?.length ?? 0) > 0;
  return !connected;
}

/** Whether the member has an active premium subscription, for display (the
 *  card's premium badge). Unlike the photo gate this is not a security
 *  decision, so a missing probe reads as "not premium". */
export function isPremiumMember(user: PhotoPrivacyProbes): boolean {
  return (user.subscriptions?.length ?? 0) > 0;
}
