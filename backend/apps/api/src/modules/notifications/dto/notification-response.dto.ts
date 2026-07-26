import type { NotificationType } from '../../../../../../libs/database/generated/client';

/** The person a notification is about (interest sender, shortlister, …), or
 *  null for actor-less notices (system, verification, subscription). */
export interface NotificationActorDto {
  id: string;
  name: string;
  photoUrl: string | null;
}

/**
 * One notification item. Field-for-field the shape Flutter's
 * NotificationModel.fromJson expects. `type` is the raw backend enum string
 * (e.g. "INTEREST_RECEIVED") — the client maps unknown values to a generic
 * category, so adding a new NotificationType never breaks this contract.
 */
export interface NotificationItemDto {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string;
  actor: NotificationActorDto | null;
  referenceId: string | null;
  metadata: Record<string, unknown>;
}

/** Paginated envelope for GET /notifications — `hasMore` drives the client's
 *  infinite scroll without it tracking totals itself. */
export interface NotificationsPageDto {
  items: NotificationItemDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

/** GET /notifications/unread-count. */
export interface UnreadCountDto {
  count: number;
}

// ── Swagger examples ──────────────────────────────────────────────────────

export const NOTIFICATION_ITEM_EXAMPLE = {
  id: 'b1e7c2a4-9f3d-4a6b-8c7e-1d2f3a4b5c6d',
  type: 'INTEREST_RECEIVED',
  title: 'New interest received',
  message: 'Someone has expressed interest in your profile.',
  isRead: false,
  createdAt: '2026-07-25T10:15:00.000Z',
  actor: {
    id: '5f2b1c8e-1a2b-4c3d-9e8f-0a1b2c3d4e5f',
    name: 'Priya R',
    photoUrl: 'https://…/signed-photo.jpg',
  },
  referenceId: '9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
  metadata: {
    actorId: '5f2b1c8e-1a2b-4c3d-9e8f-0a1b2c3d4e5f',
    referenceId: '9a8b7c6d-5e4f-3a2b-1c0d-9e8f7a6b5c4d',
  },
};

export const NOTIFICATIONS_PAGE_EXAMPLE = {
  items: [NOTIFICATION_ITEM_EXAMPLE],
  page: 1,
  limit: 20,
  total: 1,
  hasMore: false,
};
